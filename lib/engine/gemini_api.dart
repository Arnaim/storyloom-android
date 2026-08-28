import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

import '../data/settings.dart';
import '../models/analysis.dart';
import 'prompt_builder.dart';

/// The only class that talks to Gemini.
///
/// Maps SDK/network failures to [AiException]. Transient failures are retried
/// with backoff until the first token of a stream; quota errors are never
/// retried. Once narration is flowing we never replay already-emitted text.
class GeminiService {
  GeminiService({required this._settings}) {
    _modelName = _settings.model;
  }

  final AppSettings _settings;
  late String _modelName;

  static const _maxAttempts = 3;

  GenerativeModel _model({GenerationConfig? config, Content? system}) =>
      GenerativeModel(
        model: _modelName,
        apiKey: _settings.apiKey.trim(),
        generationConfig: config,
        systemInstruction: system,
      );

  bool get configured => _settings.apiKey.trim().isNotEmpty;

  // ------------------------------------------------------------------ //
  // Narrative generation (streamed)
  // ------------------------------------------------------------------ //
  Stream<String> generateNarrative(PromptBundle bundle) async* {
    final system = Content.system(bundle.system);
    final config = GenerationConfig(
      temperature: _settings.temperature,
      maxOutputTokens: _settings.maxOutputTokens,
    );

    // Phase 1: start the stream and wait for the first token, retrying only
    // transient failures. Once narration flows we never replay emitted text.
    late StreamIterator<GenerateContentResponse> iterator;
    String? firstToken;
    var attempt = 0;
    var delay = 2.0;
    while (true) {
      attempt++;
      try {
        final model = _model(config: config, system: system);
        iterator = StreamIterator(
            model.generateContentStream([Content.text(bundle.userMessage())]));
        while (await iterator.moveNext()) {
          final t = iterator.current.text;
          if (t != null && t.trim().isNotEmpty) {
            firstToken = t;
            break;
          }
        }
        break;
      } on GenerativeAIException catch (e) {
        final mapped = _mapError(e);
        if (!mapped.retryable || attempt >= _maxAttempts) throw mapped;
        await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
        delay *= 2;
      } on SocketException catch (e) {
        final mapped = _mapError(e);
        if (!mapped.retryable || attempt >= _maxAttempts) throw mapped;
        await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
        delay *= 2;
      } on http.ClientException catch (e) {
        final mapped = _mapError(e);
        if (!mapped.retryable || attempt >= _maxAttempts) throw mapped;
        await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
        delay *= 2;
      } on TimeoutException catch (e) {
        final mapped = _mapError(e);
        if (!mapped.retryable || attempt >= _maxAttempts) throw mapped;
        await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
        delay *= 2;
      } catch (e) {
        final mapped = _mapError(e);
        if (!mapped.retryable || attempt >= _maxAttempts) throw mapped;
        await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
        delay *= 2;
      }
    }
    if (firstToken == null) {
      throw const AiException('Model returned empty output.', retryable: false);
    }
    yield firstToken;

    // Phase 2: consume the rest without retrying.
    while (await iterator.moveNext()) {
      final t = iterator.current.text;
      if (t != null && t.trim().isNotEmpty) yield t;
    }
  }

  Future<String> generateNarrativeFull(PromptBundle bundle) async {
    final buffer = StringBuffer();
    await for (final part in generateNarrative(bundle)) {
      buffer.write(part);
    }
    return buffer.toString().trim();
  }

  // ------------------------------------------------------------------ //
  // Structured analysis
  // ------------------------------------------------------------------ //
  Future<TurnAnalysis> analyzeTurn(String scene, String narrative) async {
    final model = _model(
      config: GenerationConfig(
        temperature: 0.2,
        maxOutputTokens: 2048,
        responseMimeType: 'application/json',
        responseSchema: TurnAnalysis.responseSchema(),
      ),
    );
    final response = await _withRetry(
      () => model.generateContent([Content.text(analysisUserMessage(scene, narrative))]),
      'Gemini analysis',
    );
    final raw = response.text?.trim();
    if (raw == null || raw.isEmpty) {
      throw const AiException('Analysis returned empty output.', retryable: false);
    }
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) {
        throw const AiException('Analysis JSON was malformed.', retryable: false);
      }
      return TurnAnalysis.fromJson(data);
    } on AiException {
      rethrow;
    } on FormatException catch (e) {
      throw AiException('Analysis JSON was malformed: ${e.message}', retryable: false);
    } catch (e) {
      throw AiException('Analysis failed validation: $e', retryable: false);
    }
  }

  // ------------------------------------------------------------------ //
  // Summarization / opening / health
  // ------------------------------------------------------------------ //
  Future<String> summarizeStory(String oldSummary, String recentText) async {
    final model = _model(
      config: GenerationConfig(
        temperature: 0.5,
        maxOutputTokens: _settings.maxOutputTokens,
      ),
    );
    final response = await _withRetry(
      () => model
          .generateContent([Content.text(summarizeUserMessage(oldSummary, recentText))]),
      'Gemini summarization',
    );
    final text = response.text?.trim() ?? '';
    if (text.isEmpty) {
      throw const AiException('Summarization returned empty output.', retryable: false);
    }
    return text.length > 4000 ? text.substring(0, 4000) : text;
  }

  Future<String> generateOpening(String userMessage) async {
    final model = _model(
      config: GenerationConfig(
        temperature: _settings.temperature,
        maxOutputTokens: _settings.maxOutputTokens,
      ),
    );
    final response = await _withRetry(
      () => model.generateContent([Content.text(userMessage)]),
      'Gemini opening scene',
    );
    final text = response.text?.trim() ?? '';
    if (text.isEmpty) {
      throw const AiException('Opening scene came back empty.', retryable: false);
    }
    return text;
  }

  Future<String> testConnection() async {
    final model = _model(
      config: GenerationConfig(maxOutputTokens: 32),
    );
    final response = await _withRetry(
      () => model.generateContent([Content.text('Reply with just: OK')]),
      'Gemini connection',
    );
    final t = response.text?.trim() ?? '';
    return t.isEmpty ? 'Connected.' : 'Connected — model says "$t"';
  }

  // ------------------------------------------------------------------ //
  // Retry / error mapping
  // ------------------------------------------------------------------ //
  Future<T> _withRetry<T>(Future<T> Function() fn, String what) async {
    var attempt = 0;
    var delay = 2.0;
    while (true) {
      attempt++;
      try {
        return await fn();
      } catch (e) {
        final mapped = _mapError(e);
        if (!mapped.retryable || attempt >= _maxAttempts) throw mapped;
        await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
        delay *= 2;
      }
    }
  }

  /// Normalizes any SDK/network failure into an [AiException]
  /// (retryable = transient, safe to retry with backoff).
  AiException _mapError(Object e) {
    if (e is AiException) return e;
    if (e is InvalidApiKey) {
      return const AiException('Invalid API key. Check it in Settings.', retryable: false);
    }
    if (e is UnsupportedUserLocation) {
      return const AiException(
          'Your location is not supported by the Gemini API.', retryable: false);
    }
    final message = _messageOf(e);
    final low = message.toLowerCase();
    if (low.contains('quota') ||
        low.contains('resource_exhausted') ||
        low.contains('per day') ||
        low.contains('per minute')) {
      return AiException(
        'Gemini quota exceeded for this key. Try again later or check Google AI Studio.',
        retryable: false,
      );
    }
    if (low.contains('429') || low.contains('rate limit') || low.contains('too many')) {
      return AiException('Too many requests. Slow down and try again.', retryable: true);
    }
    if (low.contains('api key') || low.contains('api_key_invalid')) {
      return AiException('Invalid API key. Check it in Settings.', retryable: false);
    }
    if (low.contains('model') && (low.contains('not found') || low.contains('not available'))) {
      return AiException(
          'The configured Gemini model is not available for this key.', retryable: false);
    }
    if (low.contains('timeout') || low.contains('timed out') || low.contains('sdk exception')) {
      return AiException(message, retryable: true);
    }
    if (e is SocketException ||
        e is http.ClientException ||
        e is TimeoutException) {
      return AiException('Network problem reaching Gemini. Retrying.', retryable: true);
    }
    final clipped = message.length > 240 ? message.substring(0, 240) : message;
    return AiException(clipped, retryable: false);
  }

  static String _messageOf(Object e) {
    if (e is GenerativeAIException) return e.message;
    return e.toString();
  }
}

class AiException implements Exception {
  const AiException(this.message, {this.retryable = false});
  final String message;
  final bool retryable;

  const AiException.retryable(this.message) : retryable = true;

  @override
  String toString() => message;
}