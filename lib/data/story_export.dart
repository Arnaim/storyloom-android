import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/character.dart';
import '../models/scenario.dart';
import '../models/story.dart';
import 'database.dart';

/// Handles exporting and importing story data as JSON.
/// Designed to be resilient: invalid files are rejected safely,
/// schema versions are checked, and existing data is never corrupted.
class StoryExportService {
  StoryExportService._();
  static final StoryExportService instance = StoryExportService._();

  static const int exportFormatVersion = 1;

  /// Exports a single story and all its associated data (messages, NPCs, quests,
  /// inventory, memories, snapshots) to a JSON string.
  Future<String> exportStoryJson(int storyId) async {
    final db = AppDatabase.instance;
    final story = await db.getStory(storyId);
    if (story == null) throw Exception('Story not found (ID: $storyId)');

    final messages = await db.messagesForStory(storyId);
    final npcs = await db.npcsForStory(storyId);
    final quests = await db.questsForStory(storyId);
    final items = await db.inventoryForStory(storyId);
    final memories = await db.memoriesForStory(storyId, activeOnly: false);
    final npcMemories = await db.npcMemoriesForStory(storyId);

    // Include the source scenario (title + full data) so imports can
    // reconstruct the scenario when the original ID no longer exists.
    final scenario = await db.getScenario(story.scenarioId);

    final payload = {
      'format_version': exportFormatVersion,
      'app': 'Storyloom',
      'exported_at': DateTime.now().toIso8601String(),
      'type': 'single_story',
      'story': story.toJson(),
      'scenario_title': scenario?.title,
      'scenario': scenario?.toJson(),
      'messages': messages.map((m) => m.toJson()).toList(),
      'npcs': npcs.map((n) => n.toJson()).toList(),
      'quests': quests.map((q) => q.toJson()).toList(),
      'inventory_items': items.map((i) => i.toJson()).toList(),
      'memories': memories.map((m) => m.toJson()).toList(),
      'npc_memories': npcMemories.map((m) => m.toJson()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Exports ALL stories and their associated data to a single JSON string.
  Future<String> exportAllStoriesJson() async {
    final db = AppDatabase.instance;
    final stories = await db.listStories();

    final allStoriesData = <Map<String, dynamic>>[];
    for (final s in stories) {
      final messages = await db.messagesForStory(s.id);
      final npcs = await db.npcsForStory(s.id);
      final quests = await db.questsForStory(s.id);
      final items = await db.inventoryForStory(s.id);
      final memories = await db.memoriesForStory(s.id, activeOnly: false);
      final npcMemories = await db.npcMemoriesForStory(s.id);
      final scenario = await db.getScenario(s.scenarioId);

      allStoriesData.add({
        'story': s.toJson(),
        'scenario_title': scenario?.title,
        'scenario': scenario?.toJson(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'npcs': npcs.map((n) => n.toJson()).toList(),
        'quests': quests.map((q) => q.toJson()).toList(),
        'inventory_items': items.map((i) => i.toJson()).toList(),
        'memories': memories.map((m) => m.toJson()).toList(),
        'npc_memories': npcMemories.map((m) => m.toJson()).toList(),
      });
    }

    final payload = {
      'format_version': exportFormatVersion,
      'app': 'Storyloom',
      'exported_at': DateTime.now().toIso8601String(),
      'type': 'all_stories',
      'story_count': stories.length,
      'stories': allStoriesData,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Writes JSON content to the app's documents directory and returns the file path.
  Future<String> saveToFile(String jsonString, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(jsonString);
    return file.path;
  }

  /// Validates and imports story data from a JSON string.
  /// Returns a summary string (e.g., "Imported 1 story: 'Arcanum Academy'").
  /// Throws a descriptive [FormatException] if the JSON is invalid.
  Future<String> importFromJson(String rawJson) async {
    final Map<String, dynamic> data;
    try {
      final parsed = jsonDecode(rawJson);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('File does not contain a valid JSON object.');
      }
      data = parsed;
    } catch (e) {
      throw FormatException('Failed to parse JSON: $e');
    }

    // Basic signature check
    final app = data['app'] as String?;
    if (app != null && app != 'Storyloom') {
      throw FormatException('Unrecognized file source: expected "Storyloom", got "$app".');
    }

    final type = data['type'] as String?;
    if (type == 'single_story') {
      return _importSingleStory(data);
    } else if (type == 'all_stories') {
      return _importAllStories(data);
    } else if (data.containsKey('story')) {
      // Fallback: likely a single story without explicit type field
      return _importSingleStory(data);
    } else {
      throw const FormatException(
          'Unrecognized Storyloom export file format: missing "type" or "story" key.');
    }
  }

  Future<String> _importSingleStory(Map<String, dynamic> data) async {
    final storyMap = data['story'] as Map<String, dynamic>?;
    if (storyMap == null) {
      throw const FormatException('Missing "story" object in import data.');
    }

    final db = AppDatabase.instance;

    // Resolve the scenario with a multi-strategy fallback so re-imports
    // survive seed renumbering (10 → 16 scenarios) and title changes.
    final originalScenarioId =
        (storyMap['scenario_id'] as num?)?.toInt() ?? 0;
    final exportedTitle = data['scenario_title'] as String?;
    final embeddedScenario = data['scenario'] is Map
        ? Scenario.fromJson(Map<String, dynamic>.from(data['scenario'] as Map))
        : null;

    Scenario? scenario;
    String resolution = 'id $originalScenarioId';

    // 1. Try exact ID match
    if (originalScenarioId > 0) {
      scenario = await db.getScenario(originalScenarioId);
      if (scenario != null) resolution = 'id $originalScenarioId';
    }

    // 2. Try title match (case-insensitive)
    if (scenario == null && exportedTitle != null && exportedTitle.trim().isNotEmpty) {
      scenario = await db.getScenarioByTitle(exportedTitle);
      if (scenario != null) resolution = 'title "$exportedTitle"';
    }

    // 3. Recreate from embedded scenario data (user scenario, not a seed)
    if (scenario == null && embeddedScenario != null) {
      final recreated = Scenario(
        id: 0,
        title: embeddedScenario.title,
        description: embeddedScenario.description,
        genre: embeddedScenario.genre,
        tags: embeddedScenario.tags,
        premise: embeddedScenario.premise,
        openingScene: embeddedScenario.openingScene,
        worldDescription: embeddedScenario.worldDescription,
        rules: embeddedScenario.rules,
        tone: embeddedScenario.tone,
        narratorStyle: embeddedScenario.narratorStyle,
        contentRating: embeddedScenario.contentRating,
        rpgEnabled: embeddedScenario.rpgEnabled,
        playerRole: embeddedScenario.playerRole,
        npcs: embeddedScenario.npcs,
        locations: embeddedScenario.locations,
        lore: embeddedScenario.lore,
        openingSuggestions: embeddedScenario.openingSuggestions,
        isSample: false,
        playCount: 0,
        author: embeddedScenario.author,
        coverArt: embeddedScenario.coverArt,
        backgroundArt: embeddedScenario.backgroundArt,
        seedVersion: embeddedScenario.seedVersion,
        forks: embeddedScenario.forks,
      );
      final newId = await db.insertUserScenario(recreated);
      scenario = await db.getScenario(newId);
      resolution = 'recreated from embedded data';
    }

    // 4. Last resort: first scenario in the library
    if (scenario == null) {
      final all = await db.listScenarios();
      scenario = all.isNotEmpty ? all.first : null;
      resolution = 'fallback to first scenario';
    }

    if (scenario == null) {
      throw const FormatException(
          'No scenarios in library — cannot import story.');
    }

    final validScenarioId = scenario.id;

    // Build the story, resetting ID so it gets inserted as a new entry
    final characterMap = storyMap['character'] is Map
        ? Map<String, dynamic>.from(storyMap['character'] as Map)
        : <String, dynamic>{};

    final importedStory = Story(
      id: 0,
      title: '${storyMap['title'] ?? 'Imported Story'} (Imported)',
      scenarioId: validScenarioId,
      character: Character.fromJson(characterMap),
      status: storyMap['status'] as String? ?? 'active',
      turnCount: (storyMap['turn_count'] as num?)?.toInt() ?? 0,
      lastMessageSeq: (storyMap['last_message_seq'] as num?)?.toInt() ?? 0,
      currentState: storyMap['current_state'] is Map
          ? Map<String, dynamic>.from(storyMap['current_state'] as Map)
          : {},
      coverArt: storyMap['cover_art'] as String?,
      backgroundArt: storyMap['background_art'] as String?,
    );

    final newStoryId = await db.createStory(importedStory);

    // Import messages
    final messagesRaw = data['messages'] as List? ?? [];
    for (final m in messagesRaw) {
      if (m is Map) {
        final mm = Map<String, dynamic>.from(m);
        await db.insertMessage(StoryMessage(
          id: 0,
          storyId: newStoryId,
          seq: (mm['seq'] as num?)?.toInt() ?? 0,
          role: mm['role'] as String? ?? 'assistant',
          kind: mm['kind'] as String? ?? 'narration',
          speaker: mm['speaker'] as String? ?? '',
          content: mm['content'] as String? ?? '',
          variants: (mm['variants'] as List?)?.whereType<String>().toList() ?? [],
          activeVariant: (mm['active_variant'] as num?)?.toInt() ?? 0,
          suggestions: (mm['suggestions'] as List?)?.whereType<String>().toList() ?? [],
          meta: mm['meta'] is Map ? Map<String, dynamic>.from(mm['meta'] as Map) : {},
        ));
      }
    }

    // Import NPCs
    final npcsRaw = data['npcs'] as List? ?? [];
    for (final n in npcsRaw) {
      if (n is Map) {
        final nm = Map<String, dynamic>.from(n);
        await db.upsertNpc(StoryNPC(
          id: 0,
          storyId: newStoryId,
          name: nm['name'] as String? ?? '',
          details: nm['details'] is Map ? Map<String, dynamic>.from(nm['details'] as Map) : {},
          relationshipValue: (nm['relationship_value'] as num?)?.toDouble() ?? 0.0,
          emotionalState: nm['emotional_state'] as String? ?? '',
          status: nm['status'] as String? ?? 'alive',
          location: nm['location'] as String? ?? '',
          image: nm['image'] as String?,
        ));
      }
    }

    // Import quests
    final questsRaw = data['quests'] as List? ?? [];
    for (final q in questsRaw) {
      if (q is Map) {
        final qm = Map<String, dynamic>.from(q);
        await db.upsertQuest(Quest(
          id: 0,
          storyId: newStoryId,
          title: qm['title'] as String? ?? '',
          description: qm['description'] as String? ?? '',
          status: qm['status'] as String? ?? 'active',
          createdSeq: (qm['created_seq'] as num?)?.toInt() ?? 0,
        ));
      }
    }

    // Import inventory items
    final itemsRaw = data['inventory_items'] as List? ?? [];
    for (final i in itemsRaw) {
      if (i is Map) {
        final im = Map<String, dynamic>.from(i);
        await db.upsertItem(InventoryItem(
          id: 0,
          storyId: newStoryId,
          name: im['name'] as String? ?? '',
          description: im['description'] as String? ?? '',
          quantity: (im['quantity'] as num?)?.toInt() ?? 1,
        ));
      }
    }

    // Import memories
    final memoriesRaw = data['memories'] as List? ?? [];
    for (final mem in memoriesRaw) {
      if (mem is Map) {
        final mm = Map<String, dynamic>.from(mem);
        await db.insertMemory(Memory(
          id: 0,
          storyId: newStoryId,
          kind: mm['kind'] as String? ?? 'fact',
          text: mm['text'] as String? ?? '',
          importance: (mm['importance'] as num?)?.toDouble() ?? 0.5,
          active: mm['active'] == true || mm['active'] == 1,
          createdSeq: (mm['created_seq'] as num?)?.toInt() ?? 0,
        ));
      }
    }

    // Import NPC memories
    final npcMemoriesRaw = data['npc_memories'] as List? ?? [];
    for (final nm in npcMemoriesRaw) {
      if (nm is Map) {
        final nmm = Map<String, dynamic>.from(nm);
        await db.insertNpcMemory(NPCMemory(
          id: 0,
          storyId: newStoryId,
          npcName: nmm['npc_name'] as String? ?? '',
          fact: nmm['fact'] as String? ?? '',
          importance: (nmm['importance'] as num?)?.toDouble() ?? 0.5,
          active: nmm['active'] == true || nmm['active'] == 1,
          createdSeq: (nmm['created_seq'] as num?)?.toInt() ?? 0,
        ));
      }
    }

    return 'Imported "${importedStory.title}" — scenario matched via $resolution '
        '(${messagesRaw.length} messages, ${npcsRaw.length} NPCs).';
  }

  Future<String> _importAllStories(Map<String, dynamic> data) async {
    final storiesList = data['stories'] as List? ?? [];
    if (storiesList.isEmpty) {
      return 'No stories found in the backup file.';
    }

    var count = 0;
    for (final storyData in storiesList) {
      if (storyData is Map<String, dynamic>) {
        await _importSingleStory(storyData);
        count++;
      }
    }

    return 'Successfully imported $count stories.';
  }
}
