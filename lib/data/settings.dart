import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device settings (no backend, single user). Persisted via SharedPreferences.
class AppSettings {
  AppSettings({
    this.apiKey = '',
    this.model = 'gemini-3.6-flash',
    this.providerType = 'gemini',
    this.apiBaseUrl = '',
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
  String providerType; // 'gemini' | 'openrouter' | 'custom'
  String apiBaseUrl;
  double temperature;
  int maxOutputTokens;
  int contextMessages;
  bool autoMemory;
  int summarizeEveryTurns;
  int maxSuggestions;
  bool darkMode;

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        apiKey: (j['api_key'] as String?) ?? '',
        model: (j['model'] as String?) ?? 'gemini-3.6-flash',
        providerType: (j['provider_type'] as String?) ?? 'gemini',
        apiBaseUrl: (j['api_base_url'] as String?) ?? '',
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
      settings =
          AppSettings.fromJson(jsonDecode(raw ?? '') as Map<String, dynamic>);
    } catch (_) {
      settings = AppSettings();
    }
    final secureKey = await _readSecureKey();
    if (secureKey.isNotEmpty) settings.apiKey = secureKey;

    // Migrate old settings if needed
    if (settings.providerType == 'gemini' &&
        settings.model.startsWith('openrouter/')) {
      settings.providerType = 'openrouter';
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
    await prefs.setString(
        _key,
        jsonEncode({
          'model': s.model,
          'provider_type': s.providerType,
          'api_base_url': s.apiBaseUrl,
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
      // Secure storage unavailable
    }
  }
}

const supportedGeminiModels = [
  'gemini-3.8-flash',
  'gemini-3.8-flash-lite',
  'gemini-3.7-flash',
  'gemini-3.6-flash',
  'gemini-3.5-flash',
  'gemini-3.5-flash-lite',
  'gemini-3.1-flash',
  'gemini-3.1-flash-lite',
  'gemini-2.5-flash',
  'gemini-2.5-flash-lite',
  'gemini-2.0-flash',
  'gemini-2.0-flash-lite',
];

const supportedOpenRouterModels = [
  'openrouter/free',
  'google/gemma-4-31b-it:free',
  'google/gemma-4-26b-a4b-it:free',
  'nvidia/nemotron-3-ultra-550b-a55b:free',
  'nvidia/nemotron-3.5-lightning:free',
  'nvidia/nemotron-3-super-120b-a12b:free',
  'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free',
  'liquid/lfm-2.5-2.6b:free',
  'cohere/north-mini-code:free',
  'poolside/laguna-s-2.1:free',
  'thinkingmachines/inkling:free',
  'apodex/apodex-1.1-mini:free',
];

/// Returns true if the model string refers to an OpenRouter model.
bool isOpenRouterModel(String model) =>
    model.startsWith('openrouter/') ||
    model.contains('/') ||
    model.contains(':free');

/// Strips the `openrouter/` prefix to get the actual model ID for the API.
String openRouterModelId(String model) =>
    model.startsWith('openrouter/') ? model.substring('openrouter/'.length) : model;