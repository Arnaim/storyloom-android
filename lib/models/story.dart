import 'character.dart';

/// A story message. `role`: user | assistant | system.
/// `kind`: action | narration | system_event | loot | location | relationship | quest.
class StoryMessage {
  StoryMessage({
    this.id = 0,
    required this.storyId,
    required this.seq,
    required this.role,
    this.kind = 'narration',
    this.speaker = '',
    this.content = '',
    this.variants = const [],
    this.activeVariant = 0,
    this.suggestions = const [],
    this.meta = const {},
  });

  final int id;
  final int storyId;
  final int seq;
  final String role;
  final String kind;
  final String speaker;
  final String content;
  final List<String> variants;
  final int activeVariant;
  final List<String> suggestions;
  final Map<String, dynamic> meta;

  bool get isUser => role == 'user';
  bool get isSystem => role == 'system';

  String get activeContent {
    if (variants.isEmpty) return content;
    final idx = activeVariant.clamp(0, variants.length - 1);
    return variants[idx];
  }

  String get kindLabel {
    switch (kind) {
      case 'location':
        return 'LOCATION';
      case 'loot':
        return 'ITEM';
      case 'relationship':
        return 'RELATIONSHIP';
      case 'quest':
        return 'QUEST';
      case 'system_event':
        return 'EVENT';
      default:
        return kind.toUpperCase().replaceAll('_', ' ');
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'story_id': storyId,
        'seq': seq,
        'role': role,
        'kind': kind,
        'speaker': speaker,
        'content': content,
        'variants': variants,
        'active_variant': activeVariant,
        'suggestions': suggestions,
        'meta': meta,
      };

  factory StoryMessage.fromJson(Map<String, dynamic> j) => StoryMessage(
        id: (j['id'] as num?)?.toInt() ?? 0,
        storyId: (j['story_id'] as num?)?.toInt() ?? 0,
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        role: (j['role'] as String?) ?? 'assistant',
        kind: (j['kind'] as String?) ?? 'narration',
        speaker: (j['speaker'] as String?) ?? '',
        content: (j['content'] as String?) ?? '',
        variants: (j['variants'] as List?)?.whereType<String>().toList() ?? const [],
        activeVariant: (j['active_variant'] as num?)?.toInt() ?? 0,
        suggestions: (j['suggestions'] as List?)?.whereType<String>().toList() ?? const [],
        meta: Map<String, dynamic>.from(j['meta'] as Map? ?? const {}),
      );
}

/// Story-level metadata (world state lives in [Story.currentState]).
class Story {
  Story({
    this.id = 0,
    required this.title,
    required this.scenarioId,
    this.character,
    this.status = 'active',
    this.turnCount = 0,
    this.lastMessageSeq = 0,
    this.currentState = const {},
    this.createdAt = 0,
    this.updatedAt = 0,
    this.lastPlayedAt = 0,
  });

  final int id;
  final String title;
  final int scenarioId;
  final Character? character;
  final String status;
  final int turnCount;
  final int lastMessageSeq;
  final Map<String, dynamic> currentState;
  final int createdAt;
  final int updatedAt;
  final int lastPlayedAt;

  Story copyWith({
    String? title,
    String? status,
    int? turnCount,
    int? lastMessageSeq,
    Map<String, dynamic>? currentState,
    int? updatedAt,
    int? lastPlayedAt,
  }) =>
      Story(
        id: id,
        title: title ?? this.title,
        scenarioId: scenarioId,
        character: character,
        status: status ?? this.status,
        turnCount: turnCount ?? this.turnCount,
        lastMessageSeq: lastMessageSeq ?? this.lastMessageSeq,
        currentState: currentState ?? this.currentState,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      );
}

class StoryNPC {
  StoryNPC({
    this.id = 0,
    required this.storyId,
    required this.name,
    this.details = const {},
    this.relationshipValue = 0,
    this.emotionalState = '',
    this.status = 'alive',
    this.location = '',
  });

  final int id;
  final int storyId;
  final String name;
  final Map<String, dynamic> details;
  final double relationshipValue;
  final String emotionalState;
  final String status;
  final String location;

  String get relationshipLabel {
    final v = relationshipValue;
    if (v >= 60) return 'devoted ally';
    if (v >= 25) return 'friendly';
    if (v > -25) return 'neutral';
    if (v > -60) return 'wary / distrustful';
    return 'hostile';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'story_id': storyId,
        'name': name,
        'details': details,
        'relationship_value': relationshipValue,
        'emotional_state': emotionalState,
        'status': status,
        'location': location,
      };

  factory StoryNPC.fromJson(Map<String, dynamic> j) => StoryNPC(
        id: (j['id'] as num?)?.toInt() ?? 0,
        storyId: (j['story_id'] as num?)?.toInt() ?? 0,
        name: (j['name'] as String?) ?? '',
        details: Map<String, dynamic>.from(j['details'] as Map? ?? const {}),
        relationshipValue: (j['relationship_value'] as num?)?.toDouble() ?? 0,
        emotionalState: (j['emotional_state'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'alive',
        location: (j['location'] as String?) ?? '',
      );
}

class Quest {
  Quest({
    this.id = 0,
    required this.storyId,
    required this.title,
    this.description = '',
    this.status = 'active',
    this.createdSeq = 0,
  });

  final int id;
  final int storyId;
  final String title;
  final String description;
  final String status;
  final int createdSeq;

  Map<String, dynamic> toJson() => {
        'id': id,
        'story_id': storyId,
        'title': title,
        'description': description,
        'status': status,
        'created_seq': createdSeq,
      };

  factory Quest.fromJson(Map<String, dynamic> j) => Quest(
        id: (j['id'] as num?)?.toInt() ?? 0,
        storyId: (j['story_id'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'active',
        createdSeq: (j['created_seq'] as num?)?.toInt() ?? 0,
      );
}

class InventoryItem {
  InventoryItem({
    this.id = 0,
    required this.storyId,
    required this.name,
    this.description = '',
    this.quantity = 1,
  });

  final int id;
  final int storyId;
  final String name;
  final String description;
  final int quantity;

  Map<String, dynamic> toJson() => {
        'id': id,
        'story_id': storyId,
        'name': name,
        'description': description,
        'quantity': quantity,
      };

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
        id: (j['id'] as num?)?.toInt() ?? 0,
        storyId: (j['story_id'] as num?)?.toInt() ?? 0,
        name: (j['name'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      );
}

class Memory {
  Memory({
    this.id = 0,
    required this.storyId,
    this.kind = 'fact',
    required this.text,
    this.importance = 0.5,
    this.active = true,
    this.createdSeq = 0,
  });

  final int id;
  final int storyId;
  final String kind; // summary | fact
  final String text;
  final double importance;
  final bool active;
  final int createdSeq;

  Map<String, dynamic> toJson() => {
        'id': id,
        'story_id': storyId,
        'kind': kind,
        'text': text,
        'importance': importance,
        'active': active ? 1 : 0,
        'created_seq': createdSeq,
      };

  factory Memory.fromJson(Map<String, dynamic> j) => Memory(
        id: (j['id'] as num?)?.toInt() ?? 0,
        storyId: (j['story_id'] as num?)?.toInt() ?? 0,
        kind: (j['kind'] as String?) ?? 'fact',
        text: (j['text'] as String?) ?? '',
        importance: (j['importance'] as num?)?.toDouble() ?? 0.5,
        active: (j['active'] == 1 || j['active'] == true),
        createdSeq: (j['created_seq'] as num?)?.toInt() ?? 0,
      );
}