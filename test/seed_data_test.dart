// Verifies the scenario pack seeds correctly and cover art survives the
// database round-trip.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storyloom/data/database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  test('seed pack inserts 20 scenarios and keeps cover art', () async {
    final db = await AppDatabase.instance.db;
    await db.delete('scenarios');
    await AppDatabase.instance.seedIfEmpty();

    final scenarios = await AppDatabase.instance.listScenarios();
    final samples = scenarios.where((s) => s.isSample).toList();

    expect(samples.length, 20);

    final mob = samples.firstWhere(
      (s) => s.title == 'The Mob Who Was Never Meant to Matter',
    );
    expect(mob.coverArt, 'assets/covers/scenario1.jpg');

    final lite = samples.where((s) => s.coverArt != null).toList();
    expect(lite.length, 1);
  });
}