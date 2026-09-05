// Verifies the scenario pack seeds correctly and cover art survives the
// database round-trip.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storyloom/data/database.dart';
import 'package:storyloom/data/seed_scenarios.dart';
import 'package:storyloom/models/scenario.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  test('seed pack inserts every built-in scenario as a sample', () async {
    final db = await AppDatabase.instance.db;
    await db.delete('scenarios');
    await AppDatabase.instance.seedIfEmpty();

    final scenarios = await AppDatabase.instance.listScenarios();
    final samples = scenarios.where((s) => s.isSample).toList();

    expect(samples.length, SeedScenarios.all.length);
    expect(scenarios.length, samples.length);

    // Titles from the seed file must all be present.
    final titles = samples.map((s) => s.title).toSet();
    for (final seed in SeedScenarios.all) {
      expect(titles.contains(seed['title'] as String), isTrue,
          reason: 'missing scenario: ${seed['title']}');
    }
  });

  test('cover art survives the database round-trip', () async {
    final db = await AppDatabase.instance.db;
    await db.delete('scenarios');
    await AppDatabase.instance.seedIfEmpty();

    const coverPath = 'assets/covers/scenario1.jpg';
    final scenario = Scenario(
      id: 0,
      title: 'Cover Test Story',
      description: 'd',
      genre: 'Test',
      tags: const [],
      premise: 'p',
      openingScene: 'o',
      worldDescription: 'w',
      rules: 'r',
      tone: 't',
      narratorStyle: 'n',
      contentRating: 'general',
      rpgEnabled: false,
      playerRole: 'pr',
      npcs: const [],
      locations: const [],
      lore: const [],
      openingSuggestions: const [],
      isSample: false,
      playCount: 0,
      coverArt: coverPath,
    );
    final id = await AppDatabase.instance.insertScenario(scenario);
    final loaded = await AppDatabase.instance.getScenario(id);

    expect(loaded, isNotNull);
    expect(loaded!.coverArt, coverPath);
  });
}
