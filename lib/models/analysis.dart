import 'package:google_generative_ai/google_generative_ai.dart';

/// Typed contract returned by the AI after each narrative turn.
///
/// Mirrors backend `TurnAnalysis`. Everything the model returns is validated
/// through [fromJson] before it is ever applied to the world state.
class TurnAnalysis {
  TurnAnalysis({
    this.stateUpdates = const StateUpdates(),
    this.npcUpdates = const [],
    this.questUpdates = const [],
    this.inventoryUpdates = const [],
    this.events = const [],
    this.memoryCandidates = const [],
    this.suggestedActions = const [],
  });

  final StateUpdates stateUpdates;
  final List<NpcUpdate> npcUpdates;
  final List<QuestUpdate> questUpdates;
  final List<InventoryUpdate> inventoryUpdates;
  final List<StoryEvent> events;
  final List<String> memoryCandidates;
  final List<String> suggestedActions;

  factory TurnAnalysis.fromJson(Map<String, dynamic> json) {
    return TurnAnalysis(
      stateUpdates: _map(json['state_updates']) != null
          ? StateUpdates.fromJson(_map(json['state_updates'])!)
          : const StateUpdates(),
      npcUpdates: (json['npc_updates'] as List? ?? [])
          .map((e) => NpcUpdate.fromJson(_map(e)!))
          .toList(),
      questUpdates: (json['quest_updates'] as List? ?? [])
          .map((e) => QuestUpdate.fromJson(_map(e)!))
          .toList(),
      inventoryUpdates: (json['inventory_updates'] as List? ?? [])
          .map((e) => InventoryUpdate.fromJson(_map(e)!))
          .toList(),
      events: (json['events'] as List? ?? [])
          .map((e) => StoryEvent.fromJson(_map(e)!))
          .toList(),
      memoryCandidates: _strings(json['memory_candidates']),
      suggestedActions: _strings(json['suggested_actions'])
          .map((s) => s.trim().length > 120 ? s.trim().substring(0, 120) : s.trim())
          .where((s) => s.isNotEmpty)
          .take(4)
          .toList(),
    );
  }

  static Map<String, dynamic>? _map(dynamic v) =>
      v is Map<String, dynamic> ? v : (v is Map ? Map<String, dynamic>.from(v) : null);

  static List<String> _strings(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  /// Declarative response schema for the Gemini Developer API.
  ///
  /// The SDK's typed [Schema] builder never emits `additionalProperties`, which
  /// the Developer API rejects, so the free-form `flags` object stays open by
  /// default. Field names are snake_case to match `fromJson`.
  static Schema responseSchema() => Schema.object(
        properties: {
          'state_updates': Schema.object(
            properties: {
              'current_location': Schema.string(nullable: true),
              'time_of_day': Schema.string(nullable: true),
              'weather': Schema.string(nullable: true),
              'health_delta': Schema.integer(nullable: true),
              'mana_delta': Schema.integer(nullable: true),
              'gold_delta': Schema.integer(nullable: true),
              'xp_gain': Schema.integer(nullable: true),
              'level_up': Schema.boolean(),
              'facts': Schema.array(items: Schema.string()),
              'flags': Schema.object(properties: {}),
            },
          ),
          'npc_updates': Schema.array(
            items: Schema.object(
              properties: {
                'name': Schema.string(),
                'relationship_delta': Schema.number(),
                'emotional_state': Schema.string(nullable: true),
                'status': Schema.string(nullable: true),
                'location': Schema.string(nullable: true),
              },
              requiredProperties: ['name'],
            ),
          ),
          'quest_updates': Schema.array(
            items: Schema.object(
              properties: {
                'title': Schema.string(),
                'description': Schema.string(nullable: true),
                'status': Schema.enumString(
                  enumValues: ['active', 'completed', 'failed'],
                ),
              },
              requiredProperties: ['title'],
            ),
          ),
          'inventory_updates': Schema.array(
            items: Schema.object(
              properties: {
                'name': Schema.string(),
                'quantity_delta': Schema.integer(),
                'description': Schema.string(nullable: true),
              },
              requiredProperties: ['name'],
            ),
          ),
          'events': Schema.array(
            items: Schema.object(
              properties: {
                'kind': Schema.enumString(
                  enumValues: ['event', 'loot', 'location', 'relationship', 'quest'],
                ),
                'text': Schema.string(),
              },
              requiredProperties: ['kind', 'text'],
            ),
          ),
          'memory_candidates': Schema.array(items: Schema.string()),
          'suggested_actions': Schema.array(items: Schema.string()),
        },
      );
}

class StateUpdates {
  const StateUpdates({
    this.currentLocation,
    this.timeOfDay,
    this.weather,
    this.healthDelta,
    this.manaDelta,
    this.goldDelta,
    this.xpGain,
    this.levelUp = false,
    this.facts = const [],
    this.flags = const {},
  });

  final String? currentLocation;
  final String? timeOfDay;
  final String? weather;
  final int? healthDelta;
  final int? manaDelta;
  final int? goldDelta;
  final int? xpGain;
  final bool levelUp;
  final List<String> facts;
  final Map<String, dynamic> flags;

  factory StateUpdates.fromJson(Map<String, dynamic> json) => StateUpdates(
        currentLocation: json['current_location'] as String?,
        timeOfDay: json['time_of_day'] as String?,
        weather: json['weather'] as String?,
        healthDelta: (json['health_delta'] as num?)?.toInt(),
        manaDelta: (json['mana_delta'] as num?)?.toInt(),
        goldDelta: (json['gold_delta'] as num?)?.toInt(),
        xpGain: (json['xp_gain'] as num?)?.toInt(),
        levelUp: json['level_up'] as bool? ?? false,
        facts: (json['facts'] as List?)
                ?.whereType<String>()
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList() ??
            const [],
        flags: Map<String, dynamic>.from(json['flags'] as Map? ?? const {}),
      );
}

class NpcUpdate {
  const NpcUpdate({
    required this.name,
    this.relationshipDelta = 0,
    this.emotionalState,
    this.status,
    this.location,
  });

  final String name;
  final double relationshipDelta;
  final String? emotionalState;
  final String? status;
  final String? location;

  factory NpcUpdate.fromJson(Map<String, dynamic> json) => NpcUpdate(
        name: (json['name'] as String?) ?? '',
        relationshipDelta: (json['relationship_delta'] as num?)?.toDouble() ?? 0,
        emotionalState: json['emotional_state'] as String?,
        status: json['status'] as String?,
        location: json['location'] as String?,
      );
}

class QuestUpdate {
  const QuestUpdate({
    required this.title,
    this.description,
    this.status = 'active',
  });

  final String title;
  final String? description;
  final String status;

  factory QuestUpdate.fromJson(Map<String, dynamic> json) => QuestUpdate(
        title: (json['title'] as String?) ?? '',
        description: json['description'] as String?,
        status: (json['status'] as String?) ?? 'active',
      );
}

class InventoryUpdate {
  const InventoryUpdate({
    required this.name,
    this.quantityDelta = 1,
    this.description,
  });

  final String name;
  final int quantityDelta;
  final String? description;

  factory InventoryUpdate.fromJson(Map<String, dynamic> json) => InventoryUpdate(
        name: (json['name'] as String?) ?? '',
        quantityDelta: (json['quantity_delta'] as num?)?.toInt() ?? 1,
        description: json['description'] as String?,
      );
}

class StoryEvent {
  const StoryEvent({required this.kind, required this.text});

  final String kind;
  final String text;

  factory StoryEvent.fromJson(Map<String, dynamic> json) => StoryEvent(
        kind: (json['kind'] as String?) ?? 'event',
        text: (json['text'] as String?) ?? '',
      );
}