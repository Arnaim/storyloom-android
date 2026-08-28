import '../models/character.dart';
import '../models/scenario.dart';
import '../models/story.dart';

/// Port of the backend's `prompt_builder.py`: every section is built
/// independently, and the assembler joins them into the final user prompt.
const String storytellingRules = '''STORYTELLING RULES (follow exactly):
1. You are the narrator and game master. You simulate the entire world: NPCs,
   environments, events, enemies, weather, consequences. You NEVER control the
   player character: never decide their thoughts, feelings, words or actions,
   and never write "you decide to..." unless the player explicitly did so.
2. Continue the scene directly from the player's action by narrating its
   consequences in second person ("You ..."). Never comment on the action's
   quality, never praise the player, never break immersion, never address the
   player as a player, never ask meta questions like "What do you do next?".
3. End the response naturally at a moment that invites action - but WITHOUT a
   closing question. The interface provides the input.
4. Maintain absolute continuity with the provided state, memories and recent
   scene. Priority when sources conflict:
   structured state > pinned memories > recent scene > world rules > scenario text.
5. Respect established world rules and NPC personalities. NPCs act on their own
   motivations; they are not automatically friendly and can lie, resist,
   remember slights, and pursue goals off-screen.
6. Consequences are real. Dangerous choices can fail or cause harm. Do not
   instantly resolve every conflict; maintain tension and pacing.
7. Vary sentence rhythm and sensory detail; avoid repeating earlier phrasing.
8. Keep responses focused: roughly 2-5 short paragraphs unless the scene truly
   demands more.''';

const String outputContract = '''FORMAT:
Write narrative prose only. No lists, no headings, no markdown formatting,
no out-of-character remarks.
For spoken dialogue use exactly this convention on its own line:
Name: "What is said." optionally followed by a short beat of action on the same line.
Internal thoughts of NPCs must be rendered through observable behaviour instead.''';

String ratingNote(String rating) {
  if (rating == 'mature') {
    return "Content level: MATURE (18+). This is adult-rated interactive fiction for, and "
        "featuring, adults. Adult subject matter is permitted and should be handled with the "
        "seriousness it deserves: graphic violence, gore, blood, horror, injury, strong "
        "language, war, loss, psychological and moral darkness, sexuality between consenting "
        "adults at a literary (fade-to-black or tasteful) level. Never depict sexual "
        "content involving minors or non-consent. Follow provider safety policy.";
  }
  return "Content level: GENERAL. Keep the story suitable for general audiences: "
      "no graphic violence, no sexual content.";
}

String buildSystemPrompt(Scenario s) {
  final parts = <String>[
    "You are Storyloom's narrator: an immersive, masterful interactive-fiction engine.",
    'SCENARIO: ${s.title}',
  ];
  if (s.narratorStyle.trim().isNotEmpty) parts.add('NARRATOR STYLE: ${s.narratorStyle}');
  if (s.tone.trim().isNotEmpty) parts.add('TONE: ${s.tone}');
  if (s.rules.trim().isNotEmpty) parts.add('WORLD RULES (obey strictly):\n${s.rules}');
  parts.add(ratingNote(s.contentRating));
  parts.add(storytellingRules);
  parts.add(outputContract);
  return parts.join('\n\n');
}

String buildWorld(Scenario s) {
  final lines = <String>[];
  if (s.worldDescription.trim().isNotEmpty) {
    lines.add('### WORLD\n${s.worldDescription}');
  }
  if (s.premise.trim().isNotEmpty) {
    lines.add('### PREMISE\n${s.premise}');
  }
  if (s.locations.isNotEmpty) {
    final locs = s.locations
        .take(10)
        .map((loc) => '${loc['name'] ?? '?'}: ${loc['description'] ?? ''}')
        .join('; ');
    if (locs.length > 300) {
      lines.add('### KEY LOCATIONS\n${locs.substring(0, 300)}');
    } else {
      lines.add('### KEY LOCATIONS\n$locs');
    }
  }
  if (s.lore.isNotEmpty) {
    final lore = s.lore
        .take(10)
        .map((entry) => '${entry['name'] ?? '?'} (${entry['type'] ?? 'lore'}): ${entry['description'] ?? ''}')
        .join('; ');
    if (lore.length > 200) {
      lines.add('### LORE\n${lore.substring(0, 200)}');
    } else {
      lines.add('### LORE\n$lore');
    }
  }
  return lines.join('\n\n');
}

String buildPlayer(Scenario s, Character? c, Map<String, dynamic> state) {
  if (c == null || c.name.trim().isEmpty) {
    return '### PLAYER CHARACTER\nAn unnamed traveler described only by their actions so far.';
  }
  final fields = <String>[
    'Name: ${c.name}',
    if (c.age.trim().isNotEmpty) 'Age: ${c.age}',
    if (c.gender.trim().isNotEmpty) 'Gender: ${c.gender}',
    if (c.pronouns.trim().isNotEmpty) 'Pronouns: ${c.pronouns}',
    if (c.occupation.trim().isNotEmpty) 'Occupation: ${c.occupation}',
    if (c.origin.trim().isNotEmpty) 'Origin: ${c.origin}',
    if (c.appearance.trim().isNotEmpty) 'Appearance: ${c.appearance}',
    if (c.personality.trim().isNotEmpty) 'Personality: ${c.personality}',
    if (c.background.trim().isNotEmpty) 'Background: ${c.background}',
  ];
  final lines = <String>[
    '### PLAYER CHARACTER (the user controls this character - you never control them)',
    ...fields,
  ];
  final pstate = state['player'] as Map<String, dynamic>? ?? {};
  if (s.rpgEnabled) {
    final stats = pstate.entries
        .where((e) => e.key != 'name' && (e.value?.toString() ?? '') != '')
        .map((e) => '${e.key}=${e.value}')
        .join(', ');
    if (stats.isNotEmpty) lines.add('Current condition: $stats');
  }
  if (c.attributes.isNotEmpty) {
    lines.add(
        'Attributes: ${c.attributes.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
  }
  return lines.join('\n');
}

String buildStateSection(Map<String, dynamic> state) {
  final world = state['world'] as Map<String, dynamic>? ?? {};
  final flags = state['flags'] as Map<String, dynamic>? ?? {};
  final lines = <String>[
    '### CURRENT WORLD STATE',
    "Location: ${world['current_location'] ?? 'unknown'}",
  ];
  final time = world['time_of_day'] as String? ?? '';
  if (time.isNotEmpty) lines.add('Time: $time');
  final weather = world['weather'] as String? ?? '';
  if (weather.isNotEmpty) lines.add('Weather: $weather');
  final facts = state['facts'] as List? ?? [];
  final recentFacts = facts.length > 8 ? facts.sublist(facts.length - 8) : facts;
  if (recentFacts.isNotEmpty) {
    lines.add('Established facts: ${recentFacts.join(' | ')}');
  }
  if (flags.isNotEmpty) {
    final flagList = flags.entries.take(12).map((e) => '${e.key}=${e.value}').join(', ');
    lines.add('Flags: $flagList');
  }
  return lines.join('\n');
}

String buildNpcs(List<StoryNPC> npcs, {int limit = 8}) {
  if (npcs.isEmpty) return '';
  final cards = <String>[];
  for (final n in npcs.take(limit)) {
    final d = n.details;
    final bits = <String>[
      '${n.name} [${n.status.isEmpty ? 'alive' : n.status}]',
    ];
    final description = d['description'] as String? ?? '';
    if (description.isNotEmpty) {
      bits.add('- ${description.length > 220 ? description.substring(0, 220) : description}');
    }
    final personality = d['personality'] as String? ?? '';
    if (personality.isNotEmpty) {
      bits.add('- Personality: ${personality.length > 160 ? personality.substring(0, 160) : personality}');
    }
    final goals = d['goals'] as String? ?? '';
    if (goals.isNotEmpty) {
      bits.add('- Goals: ${goals.length > 140 ? goals.substring(0, 140) : goals}');
    }
    final knowledge = d['knowledge'] as String? ?? '';
    if (knowledge.isNotEmpty) {
      bits.add('- Knows: ${knowledge.length > 140 ? knowledge.substring(0, 140) : knowledge}');
    }
    final secrets = d['secrets'] as String? ?? '';
    if (secrets.isNotEmpty) {
      bits.add('- Secrets (NPC may conceal): ${secrets.length > 140 ? secrets.substring(0, 140) : secrets}');
    }
    final fears = d['fears'] as String? ?? '';
    if (fears.isNotEmpty) {
      bits.add('- Fears: ${fears.length > 140 ? fears.substring(0, 140) : fears}');
    }
    if (n.emotionalState.trim().isNotEmpty) {
      bits.add('- Current emotional state: ${n.emotionalState}');
    }
    if (n.location.trim().isNotEmpty) {
      bits.add('- Location: ${n.location}');
    }
    bits.add('- Relationship toward player: ${n.relationshipLabel} (${n.relationshipValue >= 0 ? '+' : ''}${n.relationshipValue.round()})');
    cards.add(bits.join('\n'));
  }
  return '### NPCs (simulate faithfully)\n\n${cards.join('\n\n')}';
}

String buildMemories(List<Memory> memories) {
  final summary = memories.where((m) => m.kind == 'summary').toList().lastOrNull()?.text ?? '';
  final facts = memories.where((m) => m.kind == 'fact' && m.active).map((m) => m.text).toList();
  final lines = <String>[];
  if (summary.isNotEmpty) {
    lines.add('### STORY SO FAR (summary of older events)\n$summary');
  }
  if (facts.isNotEmpty) {
    lines.add(
        '### PINNED MEMORIES (must remain true)\n${facts.take(15).map((f) => '- $f').join('\n')}');
  }
  return lines.join('\n\n');
}

String buildScene(List<StoryMessage> recent) {
  if (recent.isEmpty) return '';
  final lines = <String>['### RECENT SCENE'];
  for (final m in recent) {
    if (m.isUser) {
      lines.add('[PLAYER ACTION] ${m.content}');
    } else if (m.isSystem) {
      lines.add('[SYSTEM] ${m.content}');
    } else {
      lines.add(m.activeContent);
    }
  }
  return lines.join('\n\n');
}

String buildAction(String? actionText, {required bool isContinue}) {
  if (isContinue) {
    return '### INSTRUCTION\n'
        'Continue the story naturally from exactly where the last message ended. '
        'Do not skip time unless the scene clearly calls for it.';
  }
  if (actionText != null && actionText.trim().isNotEmpty) {
    return '### PLAYER ACTION\n$actionText';
  }
  return '### INSTRUCTION\n'
      "The player's most recent action appears at the end of RECENT SCENE. "
      'Write a fresh, complete narration responding to it - do not repeat your '
      'previous attempt verbatim.';
}

/// The full user-prompt sections for a turn. [systemPrompt] goes to the model
/// as the system instruction; the rest are joined for the user turn.
class PromptBundle {
  PromptBundle({
    required this.system,
    required this.scenario,
    this.character,
    required this.state,
    required this.npcs,
    required this.memories,
    required this.recent,
    this.actionText,
    this.isContinue = false,
  });

  final String system;
  final Scenario scenario;
  final Character? character;
  final Map<String, dynamic> state;
  final List<StoryNPC> npcs;
  final List<Memory> memories;
  final List<StoryMessage> recent;
  final String? actionText;
  final bool isContinue;

  String userMessage() {
    final parts = <String>[
      buildWorld(scenario),
      buildPlayer(scenario, character, state),
      buildStateSection(state),
      buildNpcs(npcs),
      buildMemories(memories),
      buildScene(recent),
      buildAction(actionText, isContinue: isContinue),
    ].where((p) => p.trim().isNotEmpty);
    return parts.join('\n\n');
  }
}

String analysisUserMessage(String scene, String narrative) => '''
Given the turn below, extract what objectively changed.

RECENT CONTEXT:
$scene

NARRATIVE JUST WRITTEN:
$narrative

Rules:
- Only report changes actually established by the narrative or the player action.
- relationship_delta: -40..40, proportional to how the interaction went.
- suggested_actions: 2-4 SHORT imperative options (max ~6 words each), diverse (at least one cautious/observational, at most one risky). They are suggestions, not commands.
- memory_candidates: only durable, plot-significant facts worth remembering forever. Empty if none.
- Never invent changes; empty lists are valid.''';

String summarizeUserMessage(String oldSummary, String recentText) => '''
Update the rolling story summary.

CURRENT SUMMARY:
${oldSummary.isEmpty ? '(none yet)' : oldSummary}

NEW EVENTS TO FOLD IN:
$recentText

Produce an updated summary (max 250 words): present tense, covering who the player is, key relationships and promises, unresolved conflicts, current goal. Drop resolved minutiae. Output the summary text only.''';

String openingUserMessage(Scenario s, String characterContext) {
  final parts = <String>[
    '### WORLD\n${s.worldDescription.isEmpty ? s.description : s.worldDescription}',
    if (s.premise.trim().isNotEmpty) '### PREMISE\n${s.premise}',
    characterContext,
    if (s.openingScene.trim().isNotEmpty)
      '### REQUIRED OPENING DIRECTION\nBegin the story here: ${s.openingScene}',
    '### INSTRUCTION\n'
        'Write the opening scene (3-6 paragraphs): establish place, mood and situation, '
        'then hand focus to the player at a natural decision point (no closing questions). '
        'Introduce at most one or two NPCs.',
    outputContract,
  ];
  return parts.where((p) => p.trim().isNotEmpty).join('\n\n');
}

extension _LastOrNull on List {
  T? lastOrNull<T>() => isEmpty ? null : last as T;
}