import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/scenario.dart';
import 'gemini_api.dart';

/// Cover-art generation via the Gemini image model, called directly over REST
/// (the google_generative_ai SDK does not expose image responses).
///
/// Requires a Gemini API key; OpenRouter-only setups fall back gracefully.
class CoverArtService {
  CoverArtService({required this.apiKey});

  final String apiKey;

  static const _imageModel = 'gemini-2.5-flash-image';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Builds the image prompt for a scenario: cinematic book-cover art,
  /// explicitly text-free (image models tend to render garbled letters).
  static String promptFor(Scenario s) {
    final genre = s.genre.isNotEmpty ? s.genre : s.title;
    return 'Dramatic book-cover style illustration for an interactive fiction '
        'story. Genre: $genre. Premise: ${s.premise.isEmpty ? s.description : s.premise} '
        'Cinematic composition, rich atmosphere, dramatic lighting, painterly '
        'digital art. No text, no words, no letters, no logos in the image.';
  }

  /// Generates cover art and returns PNG bytes, or throws [AiException].
  Future<Uint8List> generate(String prompt) async {
    if (apiKey.trim().isEmpty) {
      throw const AiException('Add a Gemini API key in Settings first.',
          retryable: false);
    }
    final uri = Uri.parse('$_baseUrl/$_imageModel:generateContent');
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'responseModalities': ['TEXT', 'IMAGE'],
      },
    });

    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey.trim(),
            },
            body: body,
          )
          .timeout(const Duration(seconds: 90));
    } on SocketException {
      throw const AiException('Network problem reaching the image model.',
          retryable: true);
    } on TimeoutException {
      throw const AiException('Image generation timed out. Try again.',
          retryable: true);
    } on HttpException catch (e) {
      throw AiException('Image generation failed: ${e.message}',
          retryable: false);
    }

    if (response.statusCode != 200) {
      String msg = 'Image model error ${response.statusCode}';
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final err = json['error'] as Map<String, dynamic>?;
        if (err?['message'] is String) msg = err!['message'] as String;
      } catch (_) {}
      throw AiException(msg, retryable: response.statusCode == 429);
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List? ?? const [];
      for (final c in candidates) {
        final content = (c as Map<String, dynamic>)['content']
            as Map<String, dynamic>?;
        final parts = content?['parts'] as List? ?? const [];
        for (final part in parts) {
          final inline = (part as Map<String, dynamic>)['inlineData']
              as Map<String, dynamic>?;
          final data = inline?['data'] as String?;
          if (data != null && data.isNotEmpty) {
            return base64Decode(data);
          }
        }
      }
    } on FormatException catch (e) {
      throw AiException('Image response was malformed: ${e.message}',
          retryable: false);
    }
    throw const AiException(
        'The model did not return an image (it may have refused the prompt). '
        'Try again or rephrase the premise.',
        retryable: false);
  }

  /// Persists cover bytes under the app documents dir and returns the path
  /// stored on the scenario row.
  Future<String> saveCover(int scenarioId, Uint8List bytes) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'covers'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = p.join(dir.path, 'scenario_$scenarioId.png');
    await File(file).writeAsBytes(bytes, flush: true);
    return file;
  }
}
