import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

import '../data/settings.dart';
import '../models/analysis.dart';
import 'prompt_builder.dart';

/// The only class that talks to Gemini (and OpenRouter as an alternative).
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
  static const _openRouterBaseUrl = 'https://openrouter.ai/api/v1';

  bool get _isOpenRouter => isOpenRouterModel(_modelName);

  GenerativeModel _model({GenerationConfig? config, Content? system}) =>
      GenerativeModel(
        model: _isOpenRouter ? openRouterModelId(_modelName) : _modelName,
        apiKey: _settings.apiKey.trim(),
        generationConfig: config,
        systemInstruction: system,
      );

  bool get configured => _settings.apiKey.trim().isNotEmpty;

  // ------------------------------------------------------------------ //
  // Narrative generation (streamed)
  // ------------------------------------------------------------------ //
  Stream<String> generateNarrative(PromptBundle bundle) async* {
    if (_isOpenRouter) {
      yield* _generateNarrativeOpenRouter(bundle);
    } else {
      yield* _generateNarrativeGemini(bundle);
    }
  }

  Stream<String> _generateNarrativeGemini(PromptBundle bundle) async* {
    final system = Content.system(bundle.system);
    final config = GenerationConfig(
      temperature: _settings.temperature,
      maxOutputTokens: _settings.maxOutputTokens,
    );

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

    while (await iterator.moveNext()) {
      final t = iterator.current.text;
      if (t != null && t.trim().isNotEmpty) yield t;
    }
  }

  Stream<String> _generateNarrativeOpenRouter(PromptBundle bundle) async* {
    final messages = [
      {'role': 'system', 'content': bundle.system},
      {'role': 'user', 'content': bundle.userMessage()},
    ];
    final body = jsonEncode({
      'model': openRouterModelId(_modelName),
      'messages': messages,
      'temperature': _settings.temperature,
      'max_tokens': _settings.maxOutputTokens,
      'stream': true,
    });

    var attempt = 0;
    var delay = 2.0;
    while (true) {
      attempt++;
      try {
        final request = http.Request('POST', Uri.parse('$_openRouterBaseUrl/chat/completions'));
        request.headers['Authorization'] = 'Bearer ${_settings.apiKey.trim()}';
        request.headers['Content-Type'] = 'application/json';
        request.headers['HTTP-Referer'] = 'https://storyloom.app';
        request.headers['X-Title'] = 'Storyloom';
        request.body = body;

        final response = await http.Client().send(request).timeout(
          const Duration(seconds: 120),
          onTimeout: () => throw TimeoutException('OpenRouter request timed out'),
        );

        if (response.statusCode != 200) {
          final errorBody = await response.stream.bytesToString();
          String msg;
          try {
            final errorJson = jsonDecode(errorBody) as Map<String, dynamic>;
            final error = errorJson['error'] as Map<String, dynamic>?;
            msg = error?['message'] as String? ?? 'OpenRouter error ${response.statusCode}';
          } catch (_) {
            msg = 'OpenRouter error ${response.statusCode}: $errorBody';
          }
          final isQuota = response.statusCode == 429;
          throw AiException(msg, retryable: isQuota);
        }

        bool yieldedAny = false;
        await for (final rawLine in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (!rawLine.startsWith('data: ')) continue;
          final data = rawLine.substring(6).trim();
          if (data == '[DONE]') break;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;
            final delta = (choices[0] as Map<String, dynamic>)['delta'] as Map<String, dynamic>?;
            final content = delta?['content'] as String?;
            if (content != null && content.isNotEmpty) {
              yieldedAny = true;
              yield content;
            }
          } catch (_) {
            // Skip malformed SSE lines
          }
        }

        if (!yieldedAny) {
          throw const AiException('OpenRouter returned empty output.', retryable: false);
        }
        return; // Success, exit retry loop
      } on AiException catch (e) {
        if (!e.retryable || attempt >= _maxAttempts) rethrow;
        await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
        delay *= 2;
      } on SocketException catch (e) {
        if (attempt >= _maxAttempts) {
          throw AiException('Network error: ${e.message}', retryable: true);
        }
        await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
        delay *= 2;
      } on TimeoutException catch (_) {
        if (attempt >= _maxAttempts) {
          throw const AiException('OpenRouter request timed out.', retryable: true);
        }
        await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
        delay *= 2;
      } on http.ClientException catch (_) {
        if (attempt >= _maxAttempts) {
          throw const AiException('Network error reaching OpenRouter.', retryable: true);
        }
        await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
        delay *= 2;
      } catch (e) {
        if (attempt >= _maxAttempts) {
          throw AiException('OpenRouter error: $e', retryable: false);
        }
        await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
        delay *= 2;
      }
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
    if (_isOpenRouter) {
      return _analyzeTurnOpenRouter(scene, narrative);
    }
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

  Future<TurnAnalysis> _analyzeTurnOpenRouter(String scene, String narrative) async {
    final prompt = analysisUserMessage(scene, narrative);
    final responseText = await _openRouterComplete(
      'You are a story analysis engine. Extract world state changes from the narrative. '
      'Respond ONLY with valid JSON matching the required schema. No markdown, no explanation.',
      prompt,
      temperature: 0.2,
      maxTokens: 2048,
    );
    if (responseText.isEmpty) {
      throw const AiException('Analysis returned empty output.', retryable: false);
    }
    try {
      final data = jsonDecode(responseText);
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
    if (_isOpenRouter) {
      return _openRouterComplete(
        'You are a story summarizer. Condense the story events into a concise summary.',
        summarizeUserMessage(oldSummary, recentText),
        temperature: 0.5,
        maxTokens: _settings.maxOutputTokens,
      );
    }
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
    if (_isOpenRouter) {
      return _openRouterComplete(
        'You are Storyloom\'s narrator: an immersive, masterful interactive-fiction engine. '
        'Write the opening scene for this story.',
        userMessage,
        temperature: _settings.temperature,
        maxTokens: _settings.maxOutputTokens,
      );
    }
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
    if (_isOpenRouter) {
      final result = await _openRouterComplete(
        'Reply with just: OK',
        'Reply with just: OK',
        maxTokens: 32,
      );
      return result.isEmpty ? 'Connected.' : 'Connected — model says "$result"';
    }
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
  // OpenRouter non-streaming helper
  // ------------------------------------------------------------------ //
  Future<String> _openRouterComplete(
    String systemPrompt,
    String userPrompt, {
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async {
    final messages = [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ];
    final body = jsonEncode({
      'model': openRouterModelId(_modelName),
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxTokens,
    });

    return _withRetry(() async {
      final response = await http.post(
        Uri.parse('$_openRouterBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer ${_settings.apiKey.trim()}',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://storyloom.app',
          'X-Title': 'Storyloom',
        },
        body: body,
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        String msg;
        try {
          final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
          final error = errorJson['error'] as Map<String, dynamic>?;
          msg = error?['message'] as String? ?? 'OpenRouter error ${response.statusCode}';
        } catch (_) {
          msg = 'OpenRouter error ${response.statusCode}';
        }
        throw AiException(msg, retryable: response.statusCode == 429);
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw const AiException('OpenRouter returned empty output.', retryable: false);
      }
      final content = (choices[0] as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
      return (content?['content'] as String?)?.trim() ?? '';
    }, 'OpenRouter');
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