// lib/services/groq_service.dart
// FIX: Rate-limit (429) retry + model fallback chain
// Models: llama-3.3-70b-versatile → llama-3.1-8b-instant → gemma2-9b-it
// Vocab-notif 429 issue completely resolved.

import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

// ─── Custom Exceptions ────────────────────────────────────────────────────────

class GroqRateLimitException implements Exception {
  final String message;
  final double? retryAfterSec; // parsed from "try again in X.Xs"

  const GroqRateLimitException(this.message, {this.retryAfterSec});

  @override
  String toString() => 'GroqRateLimitException: $message';
}

class GroqApiException implements Exception {
  final String message;
  final int statusCode;

  const GroqApiException(this.message, {this.statusCode = 0});

  @override
  String toString() => 'GroqApiException($statusCode): $message';
}

// ─── GroqService ─────────────────────────────────────────────────────────────

class GroqService {
  static const _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';

  // Settings Hive box
  static const _hiveBox = 'settings';
  static const _apiKeyKey = 'groq_api_key';

  // ── Model priority chain ──────────────────────────────────────────────────
  // Primary   → llama-3.3-70b-versatile   (12 000 TPM on free tier)
  // Fallback1 → llama-3.1-8b-instant      (20 000 TPM on free tier – fastest)
  // Fallback2 → gemma2-9b-it              (15 000 TPM on free tier)
  static const List<String> _models = [
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
    'gemma2-9b-it',
  ];

  // Vision model (no text-only fallback needed)
  static const _visionModel = 'llama-3.2-11b-vision-preview';

  // Fallback API key (used when user hasn't entered a custom key)
  // Replace this with your actual fallback/dev key
  static const _fallbackKey = 'YOUR_FALLBACK_GROQ_KEY_HERE';

  // ── Singleton ─────────────────────────────────────────────────────────────
  static GroqService? _instance;
  factory GroqService() => _instance ??= GroqService._internal();
  GroqService._internal();

  Box? _box;

  Future<Box> get _settingsBox async {
    if (_box == null || !_box!.isOpen) {
      _box = await Hive.openBox(_hiveBox);
    }
    return _box!;
  }

  // ── API Key Management ────────────────────────────────────────────────────

  /// Returns custom key if set, else fallback key
  Future<String> getEffectiveApiKey() async {
    final box = await _settingsBox;
    final custom = box.get(_apiKeyKey) as String?;
    return (custom != null && custom.trim().isNotEmpty)
        ? custom.trim()
        : _fallbackKey;
  }

  /// Returns the user-set custom key (null if not set)
  Future<String?> getCustomApiKey() async {
    final box = await _settingsBox;
    return box.get(_apiKeyKey) as String?;
  }

  Future<bool> hasCustomKey() async {
    final key = await getCustomApiKey();
    return key != null && key.trim().isNotEmpty;
  }

  Future<void> setApiKey(String key) async {
    final box = await _settingsBox;
    await box.put(_apiKeyKey, key.trim());
  }

  Future<void> clearCustomKey() async {
    final box = await _settingsBox;
    await box.delete(_apiKeyKey);
  }

  // ── Rate-Limit Parser ─────────────────────────────────────────────────────

  /// Parses "Please try again in 19.28s" → 19.28
  double? _parseRetryAfter(Map<String, dynamic> body) {
    try {
      final msg = body['error']?['message']?.toString() ?? '';
      final m = RegExp(r'try again in (\d+\.?\d*)s').firstMatch(msg);
      if (m != null) return double.tryParse(m.group(1)!);
    } catch (_) {}
    return null;
  }

  // ── Raw HTTP Request ──────────────────────────────────────────────────────

  Future<String> _request({
    required List<Map<String, dynamic>> messages,
    required String model,
    int maxTokens = 2048,
    double temperature = 0.7,
  }) async {
    final apiKey = await getEffectiveApiKey();

    final response = await http
        .post(
          Uri.parse(_baseUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'max_tokens': maxTokens,
            'temperature': temperature,
          }),
        )
        .timeout(const Duration(seconds: 60));

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return body['choices'][0]['message']['content'] as String;
    }

    if (response.statusCode == 429) {
      throw GroqRateLimitException(
        body['error']?['message'] ?? 'Rate limit exceeded',
        retryAfterSec: _parseRetryAfter(body),
      );
    }

    throw GroqApiException(
      body['error']?['message'] ?? 'Groq API error ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  // ── Smart Request with Retry + Fallback ───────────────────────────────────
  //
  // Algorithm:
  //   For each model in _models:
  //     Attempt 1: call API
  //       on 429 → wait retryAfter seconds (parsed from error) → Attempt 2
  //     Attempt 2: retry same model
  //       on 429 → break (try next model)
  //   If all models exhausted → throw last GroqRateLimitException
  //
  Future<String> _smartRequest({
    required List<Map<String, dynamic>> messages,
    int maxTokens = 2048,
    double temperature = 0.7,
    String? preferredModel,
  }) async {
    final chain = preferredModel != null
        ? [preferredModel, ..._models.where((m) => m != preferredModel)]
        : _models;

    GroqRateLimitException? lastRateLimit;

    for (final model in chain) {
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          return await _request(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
          );
        } on GroqRateLimitException catch (e) {
          lastRateLimit = e;
          if (attempt == 0) {
            // Wait specified retry-after (+ 2s buffer) then retry same model
            final wait = (e.retryAfterSec ?? 20) + 2;
            await Future.delayed(Duration(milliseconds: (wait * 1000).round()));
          }
          // attempt 1 exhausted → move to next model
        } on GroqApiException {
          rethrow; // Non-rate-limit errors: bubble up immediately
        }
      }
    }

    // All models rate-limited
    throw lastRateLimit ??
        const GroqApiException('All models rate limited. Try again later.');
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Vocab notification word generation
  /// Called by VocabNotifService – handles 429 gracefully with auto-retry
  Future<String> generateVocabContent({
    required String prompt,
    String? systemPrompt,
  }) {
    return _smartRequest(
      messages: [
        if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': prompt},
      ],
      maxTokens: 1200,
      temperature: 0.85,
      preferredModel: 'llama-3.3-70b-versatile',
    );
  }

  /// Vocab AI chat (ai_vocab_chat_screen)
  Future<String> chat({
    required List<Map<String, dynamic>> history,
    required String userMessage,
    String? systemPrompt,
  }) {
    return _smartRequest(
      messages: [
        if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
        ...history,
        {'role': 'user', 'content': userMessage},
      ],
      maxTokens: 1500,
    );
  }

  /// Study AI – generate MCQ from extracted text / PDF content
  Future<String> generateStudyQuestions({
    required String content,
    required String systemPrompt,
  }) {
    return _smartRequest(
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': content},
      ],
      maxTokens: 3000,
      temperature: 0.5,
    );
  }

  /// Study AI – analyze image (uses vision model, no text fallback)
  Future<String> analyzeImage({
    required String base64Image,
    required String prompt,
    String mediaType = 'image/jpeg',
  }) async {
    final apiKey = await getEffectiveApiKey();

    final response = await http
        .post(
          Uri.parse(_baseUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': _visionModel,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url': 'data:$mediaType;base64,$base64Image',
                    },
                  },
                  {'type': 'text', 'text': prompt},
                ],
              },
            ],
            'max_tokens': 2000,
          }),
        )
        .timeout(const Duration(seconds: 90));

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return body['choices'][0]['message']['content'] as String;
    }

    if (response.statusCode == 429) {
      final retryAfter = _parseRetryAfter(body);
      if (retryAfter != null) {
        await Future.delayed(Duration(milliseconds: (retryAfter * 1000).round() + 2000));
        return analyzeImage(
          base64Image: base64Image,
          prompt: prompt,
          mediaType: mediaType,
        );
      }
      throw GroqRateLimitException(
        body['error']?['message'] ?? 'Vision model rate limited',
        retryAfterSec: retryAfter,
      );
    }

    throw GroqApiException(
      body['error']?['message'] ?? 'Vision API error',
      statusCode: response.statusCode,
    );
  }
}
