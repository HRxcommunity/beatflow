// ╔══════════════════════════════════════════════════════════════════════╗
// ║  Study AI Service — PDF + Image → Unlimited Batched Questions       ║
// ║  No fixed limit: 10 questions/batch, infinite batches               ║
// ╚══════════════════════════════════════════════════════════════════════╝

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

// ─── API Config ──────────────────────────────────────────────────────
const String _kGroqApiKey   = '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';
const String _kGroqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
const String _kVisionModel  = 'meta-llama/llama-4-scout-17b-16e-instruct';
const String _kTextModel    = 'llama-3.3-70b-versatile';

// ─── Batch config ─────────────────────────────────────────────────────
const int _kBatchSize    = 10;   // questions per API call
const int _kPdfPageBatch = 5;    // PDF pages per batch
const int _kMaxPdfChars  = 5000; // chars extracted per batch

// ─── Image round focus areas (for variety across rounds) ────────────
const List<String> _kRoundFocus = [
  'main concepts, key terms aur definitions',
  'specific facts, dates, numbers aur statistics',
  'comparisons, causes, effects aur relationships',
  'real-world applications aur practical examples',
  'advanced, analytical aur tricky concepts',
];

// ─── Model ────────────────────────────────────────────────────────────

class StudyQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const StudyQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}

// ─── Service ──────────────────────────────────────────────────────────

class StudyAiService {
  StudyAiService._();
  static final instance = StudyAiService._();

  // ── Get total PDF page count (cheap — no text extraction) ─────────
  Future<int> getPdfPageCount(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    return compute(_countPages, bytes);
  }

  static int _countPages(Uint8List bytes) {
    try {
      final doc   = PdfDocument(inputBytes: bytes);
      final count = doc.pages.count;
      doc.dispose();
      return count;
    } catch (_) {
      return 0;
    }
  }

  // ── Batch from Image (round = 1,2,3... for variety) ──────────────
  Future<List<StudyQuestion>> generateBatchFromImage(
    File imageFile, {
    int round = 1,
  }) async {
    _checkApiKey();
    final bytes = await imageFile.readAsBytes();
    final b64   = base64Encode(bytes);
    final ext   = imageFile.path.split('.').last.toLowerCase();
    final mime  = ext == 'png' ? 'image/png' : 'image/jpeg';
    final focus = _kRoundFocus[(round - 1).clamp(0, _kRoundFocus.length - 1)];
    return _callVisionApi(b64, mime, focus: focus);
  }

  // ── Batch from PDF (startPage = 0, 5, 10 ...) ────────────────────
  Future<List<StudyQuestion>> generateBatchFromPdf(
    File pdfFile, {
    required int startPage,
  }) async {
    _checkApiKey();
    final bytes = await pdfFile.readAsBytes();
    final text  = await compute(_extractBatch, {
      'bytes':     bytes,
      'startPage': startPage,
      'pageCount': _kPdfPageBatch,
      'maxChars':  _kMaxPdfChars,
    });
    if (text.trim().isEmpty) {
      throw Exception(
        'Is section mein text nahi mila.\n'
        'Scanned PDF hai toh Camera option use karo.',
      );
    }
    return _callTextApi(text, startPage: startPage);
  }

  // ── PDF text extraction isolate ───────────────────────────────────
  static String _extractBatch(Map<String, dynamic> args) {
    final bytes     = args['bytes']     as Uint8List;
    final startPage = args['startPage'] as int;
    final pageCount = args['pageCount'] as int;
    final maxChars  = args['maxChars']  as int;
    try {
      final doc        = PdfDocument(inputBytes: bytes);
      final extractor  = PdfTextExtractor(doc);
      final totalPages = doc.pages.count;
      final endPage    = (startPage + pageCount - 1).clamp(0, totalPages - 1);
      final buf        = StringBuffer();

      for (int i = startPage; i <= endPage; i++) {
        buf.writeln(
          extractor.extractText(startPageIndex: i, endPageIndex: i),
        );
        if (buf.length > maxChars) break;
      }
      doc.dispose();
      var text = buf.toString().trim();
      if (text.length > maxChars) text = text.substring(0, maxChars);
      return text;
    } catch (_) {
      return '';
    }
  }

  // ── Vision API ────────────────────────────────────────────────────
  Future<List<StudyQuestion>> _callVisionApi(
    String base64,
    String mime, {
    String focus = 'main concepts',
  }) async {
    final prompt = '''
Is image mein jo educational content hai usse dhyan se padho.
Focus: $focus ke baare mein $_kBatchSize multiple choice questions banao.

SIRF ek valid JSON array return karo — koi extra text, backticks ya explanation nahi.

Format:
[
  {
    "question": "Question text (Hindi/English/Hinglish)",
    "options": ["Option 1", "Option 2", "Option 3", "Option 4"],
    "correct_index": 0,
    "explanation": "Brief explanation"
  }
]

Rules:
- options mein A) B) prefix bilkul mat lagao — sirf text
- correct_index must be 0, 1, 2, ya 3
- Exactly $_kBatchSize questions
- Educational aur meaningful questions
- Agar image mein text nahi: [{"question":"Image mein text nahi mila","options":["Clear photo lo","Better lighting use karo","Text wali page lo","Dobara try karo"],"correct_index":0,"explanation":"Clear photo se better results milte hain"}]
''';

    final body = jsonEncode({
      'model': _kVisionModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text',      'text': prompt},
            {'type': 'image_url', 'image_url': {'url': 'data:$mime;base64,$base64'}},
          ],
        }
      ],
      'max_tokens': 3000,
      'temperature': 0.3,
    });

    return _handleResponse(
      await http
          .post(
            Uri.parse(_kGroqEndpoint),
            headers: {
              'Content-Type':  'application/json',
              'Authorization': 'Bearer $_kGroqApiKey',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 60)),
    );
  }

  // ── Text API (PDF) ────────────────────────────────────────────────
  Future<List<StudyQuestion>> _callTextApi(
    String text, {
    int startPage = 0,
  }) async {
    final endPage = startPage + _kPdfPageBatch;
    final prompt  = '''
Neeche diye gaye educational content (Pages ${startPage + 1}–$endPage) se \
$_kBatchSize multiple choice questions banao.

Content:
---
$text
---

SIRF ek valid JSON array return karo — koi extra text nahi.

Format:
[
  {
    "question": "Question",
    "options": ["A", "B", "C", "D"],
    "correct_index": 0,
    "explanation": "Why this is correct"
  }
]

Rules: No A) B) prefix. correct_index 0-3. Exactly $_kBatchSize questions.
''';

    final body = jsonEncode({
      'model': _kTextModel,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'max_tokens': 3000,
      'temperature': 0.3,
    });

    return _handleResponse(
      await http
          .post(
            Uri.parse(_kGroqEndpoint),
            headers: {
              'Content-Type':  'application/json',
              'Authorization': 'Bearer $_kGroqApiKey',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 60)),
    );
  }

  // ── Response handling ─────────────────────────────────────────────
  List<StudyQuestion> _handleResponse(http.Response response) {
    if (response.statusCode == 200) {
      final data    = jsonDecode(response.body) as Map<String, dynamic>;
      final content = data['choices'][0]['message']['content'] as String;
      return _parseQuestions(content);
    } else if (response.statusCode == 401) {
      throw Exception('❌ Invalid API key! console.groq.com par check karo.');
    } else if (response.statusCode == 429) {
      throw Exception('⏳ Rate limit. Thodi der baad try karo.');
    } else {
      final err = jsonDecode(response.body);
      throw Exception(
        'API Error ${response.statusCode}: ${err['error']?['message'] ?? 'Unknown error'}',
      );
    }
  }

  // ── JSON parsing with repair ──────────────────────────────────────
  List<StudyQuestion> _parseQuestions(String raw) {
    var c = raw
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();

    final match = RegExp(r'\[[\s\S]*\]').firstMatch(c);
    if (match == null) {
      throw Exception('AI se valid questions nahi mile. Dobara try karo.');
    }

    List<dynamic> list;
    try {
      list = jsonDecode(match.group(0)!) as List;
    } catch (_) {
      try {
        final s  = match.group(0)!;
        final lb = s.lastIndexOf('}');
        if (lb > 0) {
          list = jsonDecode('${s.substring(0, lb + 1)}]') as List;
        } else {
          throw Exception('Parse failed');
        }
      } catch (_) {
        throw Exception('Questions parse nahi ho sake. Dobara try karo.');
      }
    }

    final questions = <StudyQuestion>[];
    for (final item in list) {
      try {
        final m    = item as Map<String, dynamic>;
        final opts = (m['options'] as List).cast<String>();
        if (opts.length != 4) continue;
        final idx  = (m['correct_index'] as num).toInt().clamp(0, 3);
        questions.add(StudyQuestion(
          question:     (m['question']    as String).trim(),
          options:      opts.map((o) => o.trim()).toList(),
          correctIndex: idx,
          explanation:  (m['explanation'] as String? ?? '').trim(),
        ));
      } catch (_) {
        continue;
      }
    }

    if (questions.isEmpty) {
      throw Exception('Koi valid question nahi bana. Content clearer karo aur retry karo.');
    }
    return questions;
  }

  void _checkApiKey() {
    if (_kGroqApiKey == 'YOUR_GROQ_API_KEY_HERE') {
      throw Exception(
        '⚠️ Groq API key set nahi ki!\n'
        'study_ai_service.dart mein _kGroqApiKey daalo.\n'
        'Free key: https://console.groq.com',
      );
    }
  }
}
