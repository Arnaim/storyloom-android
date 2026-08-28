import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/settings.dart';
import '../models/analysis.dart';
import '../models/character.dart';
import '../models/scenario.dart';
import '../models/story.dart';
import 'gemini_api.dart';
import 'memory.dart' as mem;
import 'prompt_builder.dart';
import 'world_state.dart';

/// Result of one completed turn.
class TurnResult {
  TurnResult({
    this.userMessage,
    required this.assistantMessage,
    required this.systemMessages,
    required this.analysisOk,
  });

  final StoryMessage? userMessage;
  final StoryMessage assistantMessage;
  final List<StoryMessage> systemMessages;
  final bool analysisOk;
}

/// Port of `story_service.py`: turn pipeline, opening generation, analysis
/// application, and periodic summarization. It owns the DB + Gemini service.
class StoryEngine {
  StoryEngine({required AppSettings settings, GeminiService? gemini})
      : settings = settings,
        gemini = gemini ?? GeminiService(settings: settings);

  final GeminiService gemini;
  AppSettings settings;

  final AppDatabase _db = AppDatabase.instance;

  // ------------------------------------------------------------------- //
  // Story lifecycle
  // ------------------------------------------------------------------- //
  Future<int> createStory(Scenario scenario, Character? character,
      {String? title}) async {
    final state = defaultState(scenario, character);
    final story = Story(
      title: title?.trim().isNotEmpty ?? false
          ? title!.trim()
          : '${scenario.title} — ${character != null && character.name.trim().isNotEmpty ? character.name : 'Adventure'}',
      scenarioId: scenario.id,
      character: character?.isBlank == true ? null : character,
      currentState: state,
    );
    final id = await _db.createStory(story);

    final npcTemplates = scenario.npcs;
    for (final tpl in npcTemplates) {
      final name = ((tpl['name'] as String?) ?? 'Unnamed').trim();
      if (name.isEmpty) continue;
      final details = <String, dynamic>{};
      for (final key in [
        'description', 'personality', 'background', 'goals',
        'fears', 'knowledge', 'secrets',
      ]) {
        final v = tpl[key];
        if (v != null && v.toString().trim().isNotEmpty) details[key] = v.toString();
      }
      await _db.upsertNpc(StoryNPC(
        storyId: id,
        name: name.length > 120 ? name.substring(0, 120) : name,
        details: details,
        relationshipValue: (tpl['relationship'] as num?)?.toDouble() ?? 0,
      ));
    }
    await _db.incrementScenarioPlayCount(scenario.id);
    return id;
  }

  /// Generate + persist the opening narration (with suggestions when possible).
  Future<StoryMessage> generateOpening(int storyId) async {
    final story = await _db.getStory(storyId);
    final scenario = await _db.getScenario(story!.scenarioId);
    if (scenario == null) throw StateError('Scenario missing for story $storyId');

    final prompt = openingUserMessage(scenario,
        buildPlayer(scenario, story.character, story.currentState));
    final opening = (await gemini.generateOpening(prompt)).trim();

    final seq = story.lastMessageSeq + 1;
    await _db.updateStory(story.copyWith(lastMessageSeq: seq));
    final msgId = await _db.insertMessage(StoryMessage(
      storyId: storyId,
      seq: seq,
      role: 'assistant',
      kind: 'narration',
      content: opening,
      variants: [opening],
    ));
    var msg = StoryMessage(
      id: msgId,
      storyId: storyId,
      seq: seq,
      role: 'assistant',
      kind: 'narration',
      content: opening,
      variants: [opening],
    );

    final analysis = await _safeAnalyze(story, opening);
    if (analysis != null) {
      await applyAnalysisToWorld(story, analysis);
      msg = _withSuggestions(msg, analysis);
      await _db.updateMessageField(msg.id, suggest: msg.suggestions);
    }
    return msg;
  }

  // ------------------------------------------------------------------- //
  // Turn pipeline
  // ------------------------------------------------------------------- //
  Future<TurnResult> runTurn(
    int storyId,
    String actionText, {
    bool isContinue = false,
    void Function(String delta)? onChunk,
  }) async {
    final story = await _db.getStory(storyId);
    if (story == null) throw StateError('Story $storyId not found');
    final scenario = await _db.getScenario(story.scenarioId);
    if (scenario == null) throw StateError('Scenario missing for story ${story.scenarioId}');

    // Persist the player's action.
    StoryMessage? userMsg;
    if (!isContinue) {
      final seq = story.lastMessageSeq + 1;
      userMsg = StoryMessage(
        storyId: storyId,
        seq: seq,
        role: 'user',
        kind: 'action',
        content: actionText.trim(),
      );
      await _db.updateStory(story.copyWith(lastMessageSeq: seq));
      await _db.insertMessage(userMsg);
    }

    final bundle =
        await _buildBundle(scenario, story, actionText: actionText, isContinue: isContinue);

    final buffer = StringBuffer();
    await for (final part in gemini.generateNarrative(bundle)) {
      buffer.write(part);
      onChunk?.call(part);
    }
    final narrative = buffer.toString().trim();

    // Persist the assistant narrative.
    final nextSeq = story.lastMessageSeq + 1;
    final assistantId = await _db.insertMessage(StoryMessage(
      storyId: storyId,
      seq: nextSeq,
      role: 'assistant',
      kind: 'narration',
      content: narrative,
      variants: [narrative],
    ));
    final refreshed = await _db.getStory(storyId);
    await _db.updateStory(refreshed!.copyWith(
      lastMessageSeq: nextSeq,
      turnCount: refreshed.turnCount + 1,
      status: 'active',
    ));

    // Analysis (soft-fail) + apply + summarize.
    List<StoryMessage> systemMsgs = const [];
    var analysisOk = false;
    var finalMsg = StoryMessage(
      id: assistantId,
      storyId: storyId,
      seq: nextSeq,
      role: 'assistant',
      kind: 'narration',
      content: narrative,
      variants: [narrative],
    );
    if (settings.autoMemory) {
      final analysis = await _safeAnalyze(refreshed, narrative);
      if (analysis != null) {
        analysisOk = true;
        finalMsg = _withSuggestions(finalMsg, analysis);
        await _db.updateMessageField(finalMsg.id, suggest: finalMsg.suggestions);
        systemMsgs = await applyAnalysisToWorld(refreshed, analysis);
        await _maybeSummarize(refreshed);
      }
    }
    await _db.touchPlayed(storyId);

    return TurnResult(
      userMessage: userMsg,
      assistantMessage: finalMsg,
      systemMessages: systemMsgs,
      analysisOk: analysisOk,
    );
  }

  Future<TurnResult> regenerate(
    int storyId, {
    void Function(String delta)? onChunk,
  }) async {
    final story = await _db.getStory(storyId);
    if (story == null) throw StateError('Story $storyId not found');
    final scenario = await _db.getScenario(story.scenarioId);
    if (scenario == null) throw StateError('Scenario missing for story $storyId');

    final msgs = await _db.messagesForStory(storyId);
    StoryMessage? target;
    for (final m in msgs.reversed) {
      if (!m.isUser && m.kind == 'narration') {
        target = m;
        break;
      }
    }
    if (target == null) {
      throw const AiException('There is nothing to regenerate yet.', retryable: false);
    }

    await _db.deleteMessageById(target.id);
    final rewound = story.copyWith(lastMessageSeq: target.seq - 1, status: 'active');
    await _db.updateStory(rewound);

    final bundle = await _buildBundle(scenario, rewound, isContinue: false);
    final buffer = StringBuffer();
    await for (final part in gemini.generateNarrative(bundle)) {
      buffer.write(part);
      onChunk?.call(part);
    }
    final narrative = buffer.toString().trim();

    final nextSeq = rewound.lastMessageSeq + 1;
    final assistantId = await _db.insertMessage(StoryMessage(
      storyId: storyId,
      seq: nextSeq,
      role: 'assistant',
      kind: 'narration',
      content: narrative,
      variants: [narrative],
    ));
    final updated = await _db.getStory(storyId);
    await _db.updateStory(updated!.copyWith(
      lastMessageSeq: nextSeq,
      status: 'active',
    ));

    var finalMsg = StoryMessage(
      id: assistantId,
      storyId: storyId,
      seq: nextSeq,
      role: 'assistant',
      kind: 'narration',
      content: narrative,
      variants: [narrative],
    );
    var analysisOk = false;
    List<StoryMessage> systemMsgs = const [];
    if (settings.autoMemory) {
      final analysis = await _safeAnalyze(updated, narrative);
      if (analysis != null) {
        analysisOk = true;
        finalMsg = _withSuggestions(finalMsg, analysis);
        await _db.updateMessageField(finalMsg.id, suggest: finalMsg.suggestions);
        systemMsgs = await applyAnalysisToWorld(updated, analysis);
        await _maybeSummarize(updated);
      }
    }
    await _db.touchPlayed(storyId);
    return TurnResult(
      userMessage: null,
      assistantMessage: finalMsg,
      systemMessages: systemMsgs,
      analysisOk: analysisOk,
    );
  }

  Future<PromptBundle> _buildBundle(Scenario scenario, Story story,
      {String? actionText, bool isContinue = false}) async {
    final npcs = await _db.npcsForStory(story.id);
    final memories = await _db.memoriesForStory(story.id);
    final recent = await _db.messagesForStory(story.id, limit: settings.contextMessages);
    return PromptBundle(
      system: buildSystemPrompt(scenario),
      scenario: scenario,
      character: story.character,
      state: story.currentState,
      npcs: npcs,
      memories: memories,
      recent: recent,
      actionText: actionText,
      isContinue: isContinue,
    );
  }

  // ------------------------------------------------------------------- //
  // Analysis application
  // ------------------------------------------------------------------- //
  Future<TurnAnalysis?> _safeAnalyze(Story story, String narrative) async {
    try {
      final recent =
          await _db.messagesForStory(story.id, limit: settings.contextMessages);
      final scene = buildScene(recent);
      return await gemini.analyzeTurn(scene, narrative);
    } catch (e) {
      debugPrint('Analysis skipped for story ${story.id}: $e');
      return null;
    }
  }

  Future<List<StoryMessage>> applyAnalysisToWorld(
      Story story, TurnAnalysis analysis) async {
    final notes = <(String, String)>[];
    final state = Map<String, dynamic>.from(story.currentState);
    final derived = applyAnalysis(state, analysis);
    story = story.copyWith(currentState: state);
    await _db.updateStory(story);

    notes.addAll(
        derived.map((n) => (n.startsWith('Entered:') ? 'location' : 'event', n)).toList());

    final npcs = await _db.npcsForStory(story.id);
    for (final u in analysis.npcUpdates) {
      var npc = _db.findNpc(npcs, u.name);
      if (u.name.trim().isEmpty) continue;
      if (npc == null) {
        npc = StoryNPC(storyId: story.id,
            name: u.name.length > 120 ? u.name.substring(0, 120) : u.name);
        npcs.add(npc);
      }
      npc = StoryNPC(
        id: npc.id,
        storyId: npc.storyId,
        name: npc.name,
        details: npc.details,
        relationshipValue: u.relationshipDelta != 0
            ? ((npc.relationshipValue + u.relationshipDelta).clamp(-100.0, 100.0))
            : npc.relationshipValue,
        emotionalState: u.emotionalState != null
            ? (u.emotionalState!.length > 120 ? u.emotionalState!.substring(0, 120) : u.emotionalState!)
            : npc.emotionalState,
        status: u.status != null
            ? (u.status!.length > 40 ? u.status!.substring(0, 40) : u.status!)
            : npc.status,
        location: u.location != null
            ? (u.location!.length > 200 ? u.location!.substring(0, 200) : u.location!)
            : npc.location,
      );
      await _db.upsertNpc(npc);
      if (u.relationshipDelta != 0) {
        notes.add((
          'relationship',
          "${npc.name}'s trust ${u.relationshipDelta > 0 ? 'increased' : 'decreased'}."
        ));
      }
    }

    final quests = await _db.questsForStory(story.id);
    for (final q in analysis.questUpdates) {
      if (q.title.trim().isEmpty) continue;
      var quest = _db.findQuest(quests, q.title);
      if (quest == null) {
        if (q.status == 'active') {
          quest = Quest(
            storyId: story.id,
            title: q.title.length > 200 ? q.title.substring(0, 200) : q.title,
            description: q.description ?? '',
            status: q.status,
            createdSeq: story.lastMessageSeq,
          );
          quests.add(quest);
          notes.add(('quest', 'New quest: ${q.title}'));
        }
      } else {
        final verb = q.status == 'completed'
            ? 'completed'
            : q.status == 'failed'
                ? 'failed'
                : 'updated';
        if (quest.status != q.status) {
          notes.add(('quest', 'Quest $verb: ${q.title}'));
        }
        quest = Quest(
          id: quest.id,
          storyId: quest.storyId,
          title: quest.title,
          description: q.description != null &&
                  q.description!.isNotEmpty &&
                  q.status == 'active'
              ? q.description!
              : quest.description,
          status: q.status,
          createdSeq: quest.createdSeq,
        );
      }
      if (quest != null) await _db.upsertQuest(quest);
    }

    final inventory = await _db.inventoryForStory(story.id);
    for (final item in analysis.inventoryUpdates) {
      if (item.name.trim().isEmpty) continue;
      var row = _db.findItem(inventory, item.name);
      if (row == null) {
        if (item.quantityDelta > 0) {
          row = InventoryItem(
            storyId: story.id,
            name: item.name.length > 200 ? item.name.substring(0, 200) : item.name,
            description: item.description ?? '',
            quantity: item.quantityDelta,
          );
          inventory.add(row);
          final suffix = item.quantityDelta > 1 ? ' ×${item.quantityDelta}' : '';
          notes.add(('loot', '+ ${item.name}$suffix'));
        }
      } else {
        row = InventoryItem(
          id: row.id,
          storyId: row.storyId,
          name: row.name,
          description: row.description,
          quantity: (row.quantity + item.quantityDelta).clamp(0, 9999),
        );
      }
      if (row != null) await _db.upsertItem(row);
    }

    for (final ev in analysis.events) {
      if (ev.text.trim().isEmpty) continue;
      notes.add((ev.kind, ev.text));
    }

    final created = <StoryMessage>[];
    final seen = <String>{};
    var cap = 6;
    var seq = story.lastMessageSeq;
    for (final (kind, text) in notes) {
      final key = text.toLowerCase().trim().replaceAll(RegExp(r'[.\s]+$'), '');
      if (seen.any((s) => key.contains(s) || s.contains(key))) continue;
      seen.add(key);
      seq += 1;
      await _db.updateStory(story.copyWith(lastMessageSeq: seq));
      final id = await _db.insertMessage(StoryMessage(
        storyId: story.id,
        seq: seq,
        role: 'system',
        kind: kind,
        content: text,
      ));
      created.add(StoryMessage(
        id: id,
        storyId: story.id,
        seq: seq,
        role: 'system',
        kind: kind,
        content: text,
      ));
      cap -= 1;
      if (cap <= 0) break;
    }

    await mem.pinCandidates(story.id, story.lastMessageSeq, analysis.memoryCandidates);
    return created;
  }

  StoryMessage _withSuggestions(StoryMessage msg, TurnAnalysis analysis) {
    final suggestions = analysis.suggestedActions
        .take(settings.maxSuggestions)
        .toList();
    return StoryMessage(
      id: msg.id,
      storyId: msg.storyId,
      seq: msg.seq,
      role: msg.role,
      kind: msg.kind,
      content: msg.content,
      variants: msg.variants,
      suggestions: suggestions,
    );
  }

  Future<void> _maybeSummarize(Story story) async {
    final every = settings.summarizeEveryTurns < 4 ? 4 : settings.summarizeEveryTurns;
    final since = await mem.turnsSinceLastSummary(story.id, story.lastMessageSeq);
    if (since < every * 2) return;

    final lastSeq = await _db.lastSummarySeq(story.id) ?? 0;
    final rows = await _db.messagesAfterSeq(story.id, lastSeq);
    final recent = mem.transcriptForSummary(rows);
    if (recent.trim().isEmpty) return;
    final oldSummary = mem.currentSummary(await _db.memoriesForStory(story.id));
    final clipped = recent.length > 6000 ? recent.substring(recent.length - 6000) : recent;
    try {
      final summary = await gemini.summarizeStory(oldSummary, clipped);
      await mem.saveSummary(story.id, story.lastMessageSeq, summary);
    } catch (e) {
      debugPrint('Summary skipped for story ${story.id} this cycle: $e');
    }
  }
}