import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device settings (no backend, single user). Persisted via SharedPreferences.
class AppSettings {
  AppSettings({
    this.apiKey = '',
    this.model = 'gemini-flash-latest',
    this.temperature = 0.9,
    this.maxOutputTokens = 1024,
    this.contextMessages = 16,
    this.autoMemory = true,
    this.summarizeEveryTurns = 8,
    this.maxSuggestions = 4,
    this.darkMode = true,
  });

  String apiKey;
  String model;
  double temperature;
  int maxOutputTokens;
  int contextMessages;
  bool autoMemory;
  int summarizeEveryTurns;
  int maxSuggestions;
  bool darkMode;

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        apiKey: (j['api_key'] as String?) ?? '',
        model: (j['model'] as String?) ?? 'gemini-2.5-flash',
        temperature: (j['temperature'] as num?)?.toDouble() ?? 0.9,
        maxOutputTokens: (j['max_output_tokens'] as num?)?.toInt() ?? 1024,
        contextMessages: (j['context_messages'] as num?)?.toInt() ?? 16,
        autoMemory: j['auto_memory'] as bool? ?? true,
        summarizeEveryTurns: (j['summarize_every_turns'] as num?)?.toInt() ?? 8,
        maxSuggestions: (j['max_suggestions'] as num?)?.toInt() ?? 4,
        darkMode: j['dark_mode'] as bool? ?? true,
      );
}

class SettingsStore {
  static const _key = 'storyloom_settings';
  static const _secureKey = 'gemini_api_key';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    AppSettings settings;
    try {
      settings = AppSettings.fromJson(jsonDecode(raw ?? '') as Map<String, dynamic>);
    } catch (_) {
      settings = AppSettings();
    }
    final secureKey = await _readSecureKey();
    if (secureKey.isNotEmpty) settings.apiKey = secureKey;
    if (!supportedModels.contains(settings.model)) {
      settings.model = supportedModels.first;
    }
    return settings;
  }

  Future<String> _readSecureKey() async {
    try {
      return await _storage.read(key: _secureKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({
      'model': s.model,
      'temperature': s.temperature,
      'max_output_tokens': s.maxOutputTokens,
      'context_messages': s.contextMessages,
      'auto_memory': s.autoMemory,
      'summarize_every_turns': s.summarizeEveryTurns,
      'max_suggestions': s.maxSuggestions,
      'dark_mode': s.darkMode,
    }));
    try {
      if (s.apiKey.trim().isNotEmpty) {
        await _storage.write(key: _secureKey, value: s.apiKey);
      } else {
        await _storage.delete(key: _secureKey);
      }
    } catch (_) {
      // Secure storage unavailable (e.g. some test/CI environments) — the key
      // simply won't persist; it is never logged or toasted.
    }
  }
}

const supportedModels = [
  'gemini-flash-latest',
  'gemini-2.5-flash',
  'gemini-2.5-pro',
  'gemini-2.0-flash',

  // OpenRouter (free models)
  'openrouter/meta-llama/llama-3.1-8b-instruct:free',
  'openrouter/meta-llama/llama-3.1-70b-instruct:free',
  'openrouter/mistralai/mistral-7b-instruct:free',
  'openrouter/google/gemma-2-9b-it:free',
  'openrouter/qwen/qwen-2-7b-instruct:free',
  'openrouter/deepseek/deepseek-r1-0528:free',
];

/// Returns true if the model string refers to an OpenRouter model.
bool isOpenRouterModel(String model) => model.startsWith('openrouter/');

/// Strips the `openrouter/` prefix to get the actual model ID for the API.
String openRouterModelId(String model) =>
    model.startsWith('openrouter/') ? model.substring('openrouter/'.length) : model;