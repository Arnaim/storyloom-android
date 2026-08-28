import 'package:flutter/foundation.dart';

import 'data/database.dart';
import 'data/settings.dart';
import 'engine/story_engine.dart';

/// Root application state: settings + engine, wired once at startup.
class AppState extends ChangeNotifier {
  AppState({required this._store});

  final SettingsStore _store;
  AppSettings settings = AppSettings();
  late StoryEngine engine;

  bool initialized = false;
  String? initError;

  Future<void> init() async {
    try {
      settings = await _store.load();
      engine = StoryEngine(settings: settings);
      await AppDatabase.instance.seedIfEmpty();
      initialized = true;
      notifyListeners();
    } catch (e, st) {
      initError = 'Failed to initialize: $e';
      debugPrint('$initError\n$st');
      notifyListeners();
    }
  }

  Future<void> saveSettings(AppSettings s) async {
    settings = s;
    engine = StoryEngine(settings: s);
    await _store.save(s);
    notifyListeners();
  }
}