import '../models/analysis.dart';
import '../models/character.dart';
import '../models/scenario.dart';

/// Port of the backend's `state_service.py`: pure, DB-free world-state transforms.
///
/// State shape (compact — re-sent to the model every turn):
///   player: {name, health?, mana?, gold?, level?, xp?, conditions[]}
///   world:  {current_location, time_of_day, weather}
///   facts:  []  (established world facts, bounded)
///   flags:  {}  (free-form)
const int maxFacts = 24;
const int conditionsMax = 8;

Map<String, dynamic> defaultState(Scenario scenario, Character? character) {
  final player = <String, dynamic>{
    'name': (character?.name.trim().isNotEmpty ?? false) ? character!.name : 'You',
    'conditions': <String>[],
  };
  if (scenario.rpgEnabled) {
    player.addAll({'health': 100, 'mana': 100, 'gold': 10, 'level': 1, 'xp': 0});
  }
  return {
    'player': player,
    'world': {
      'current_location': '',
      'time_of_day': '',
      'weather': '',
    },
    'facts': <String>[],
    'flags': <String, dynamic>{},
  };
}

/// Mutates [state] in place; returns human-readable change notes for system cards.
List<String> applyAnalysis(Map<String, dynamic> state, TurnAnalysis analysis) {
  final u = analysis.stateUpdates;
  final notes = <String>[];

  final world = state['world'] as Map<String, dynamic>? ?? {};
  if (u.currentLocation != null && u.currentLocation != world['current_location']) {
    world['current_location'] = u.currentLocation!;
    notes.add('Entered: ${u.currentLocation}');
  }
  if (u.timeOfDay != null && u.timeOfDay!.trim().isNotEmpty) {
    world['time_of_day'] = u.timeOfDay;
  }
  if (u.weather != null && u.weather!.trim().isNotEmpty) {
    world['weather'] = u.weather;
  }
  state['world'] = world;

  final player = state['player'] as Map<String, dynamic>? ?? {};
  final statKeys = const ['health', 'mana', 'gold'];
  for (final key in statKeys) {
    final delta = key == 'health'
        ? u.healthDelta
        : key == 'mana'
            ? u.manaDelta
            : u.goldDelta;
    if (delta != null && player.containsKey(key)) {
      final cur = (player[key] as num?)?.toInt() ?? 0;
      player[key] = (cur + delta).clamp(0, 9999);
      if (key == 'health' && delta < 0) {
        notes.add('Health -${delta.abs()}');
      }
    }
  }
  if (u.xpGain != null && u.xpGain != 0 && player.containsKey('xp')) {
    final cur = (player['xp'] as num?)?.toInt() ?? 0;
    player['xp'] = cur + u.xpGain!;
  }
  if (u.levelUp && player.containsKey('level')) {
    player['level'] = ((player['level'] as num?)?.toInt() ?? 1) + 1;
    notes.add('Level up! Now level ${player['level']}');
  }

  final factsRaw = state['facts'];
  final facts = factsRaw is List ? factsRaw.cast<String>().toList() : <String>[];
  for (final fact in u.facts) {
    _pushUnique(facts, fact, maxFacts);
  }
  state['facts'] = facts;

  final flags = state['flags'] as Map<String, dynamic>? ?? {};
  u.flags.forEach((k, v) {
    if (v == null) {
      flags.remove(k);
    } else {
      flags[k] = v;
    }
  });
  state['flags'] = flags;

  final conditions = player['conditions'] as List? ?? <String>[];
  if (player.containsKey('health') && (player['health'] as num).toInt() <= 20) {
    if (!conditions.contains('gravely wounded')) conditions.add('gravely wounded');
  }
  if (player.containsKey('health') && (player['health'] as num).toInt() > 60) {
    conditions.remove('gravely wounded');
  }
  if (conditions.length > conditionsMax) {
    conditions.removeRange(conditionsMax, conditions.length);
  }
  player['conditions'] = conditions;
  state['player'] = player;

  return notes;
}

void _pushUnique(List<String> lst, String item, int cap) {
  final t = item.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return;
  final low = t.toLowerCase();
  for (final existing in lst) {
    final ex = existing.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (ex == low || ex.contains(low) || low.contains(ex)) return;
  }
  lst.add(t);
  if (lst.length > cap) {
    lst.removeRange(0, lst.length - cap);
  }
}