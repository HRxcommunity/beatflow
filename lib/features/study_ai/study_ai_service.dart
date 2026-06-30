// ╔══════════════════════════════════════════════════════════════════════╗
// ║  Study AI Service — PDF + Image se Questions Generate karo          ║
// ╚══════════════════════════════════════════════════════════════════════╝
//
// 🔑  APNI GROQ API KEY YAHAN DAALO (groq_service.dart ki tarah)
//     Free key milti hai: https://console.groq.com
// ─────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

// ─── API Config ───────────────────────────────────────────────────────
const String _kGroqApiKey    = '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';
const String _kGroqEndpoint  = 'https://api.groq.com/openai/v1/chat/completions';
const String _kVisionModel   = 'llama-3.2-11b-vision-preview';  // Image ke liye
const String _kTextModel     = 'llama-3.3-70b-versatile';       // PDF text ke liye
const int    _kMaxPdfChars   = 6000;   // Token limit avoid karne ke liye
const int    _kQuestionCount = 5;      // Kitne questions generate hone chahiye

// ─── Model ────────────────────────────────────────────────────────────

/// Ek MCQ question represent karta hai
class StudyQuestion {
  final String question;
  final List<String> options;   // Exactly 4 options
  final int correctIndex;        // 0–3
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

  // ── Public: Image file se questions ──────────────────────────────────
  Future<List<StudyQuestion>> generateFromImage(File imageFile) async {
    _checkApiKey();

    // Image bytes read karo
    final bytes = await imageFile.readAsBytes();

    // Resize agar image zyada badi ho (1024px max) — vision API ke liye
    // image_picker ne already maxWidth/maxHeight se resize kiya hai,
    // toh yahan sirf base64 encode karte hain
    final base64Image = base64Encode(bytes);
    final ext = imageFile.path.split('.').last.toLowerCase();
    final mime = (ext == 'png') ? 'image/png' : 'image/jpeg';

    return _callVisionApi(base64Image, mime);
  }

  // ── Public: PDF file se questions ────────────────────────────────────
  Future<List<StudyQuestion>> generateFromPdf(File pdfFile) async {
    _checkApiKey();

    // PDF bytes read karo
    final bytes = await pdfFile.readAsBytes();

    // Syncfusion se text extract karo (pure Dart, no native setup needed)
    final text = await compute(_extractPdfText, bytes);

    if (text.trim().isEmpty) {
      throw Exception(
        'PDF mein text nahi mila.\n'
        'Scanned PDF hai toh Camera option use karo.',
      );
    }

    return _callTextApi(text);
  }

  // ── Private: PDF text extraction (compute isolate mein) ──────────────
  static String _extractPdfText(Uint8List bytes) {
    try {
      final doc       = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(doc);
      final buffer    = StringBuffer();
      final maxPages  = doc.pages.count < 10 ? doc.pages.count : 10;

      for (int i = 0; i < maxPages; i++) {
        final pageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex:   i,
        );
        buffer.writeln(pageText);
        if (buffer.length > _kMaxPdfChars) break;
      }

      doc.dispose();

      var text = buffer.toString().trim();
      if (text.length > _kMaxPdfChars) {
        text = text.substring(0, _kMaxPdfChars);
      }
      return text;
    } catch (e) {
      return '';
    }
  }

  // ── Private: Groq Vision API call (image ke liye) ────────────────────
  Future<List<StudyQuestion>> _callVisionApi(String base64, String mime) async {
    const prompt = '''
Is image mein jo educational content hai, usse carefully padho.
Phir $_kQuestionCount multiple choice questions banao jo student ki samajh test kare.

SIRF ek valid JSON array return karo — koi extra text, markdown ya explanation nahi.

Format (EXACTLY):
[
  {
    "question": "Question text (same language as image content — Hindi/English/Hinglish)",
    "options": ["Option 1 text", "Option 2 text", "Option 3 text", "Option 4 text"],
    "correct_index": 0,
    "explanation": "Brief explanation why this is correct (Hinglish mein chal sakta hai)"
  }
]

Rules:
- options mein "A)", "B)" prefix bilkul mat lagao — sirf text
- correct_index MUST be 0, 1, 2, ya 3
- Exactly $_kQuestionCount questions banao
- Questions educational aur meaningful hon — rote questions nahi
- Agar image mein koi text nahi hai, toh likho: [{"question":"Image mein koi readable text nahi mila","options":["Camera aur focus theek karo","Photo clear lo","Text wali page choose karo","Dobara try karo"],"correct_index":0,"explanation":"Clear photo se better results milte hain"}]
''';

    final body = jsonEncode({
      'model': _kVisionModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$mime;base64,$base64'},
            },
          ],
        }
      ],
      'max_tokens': 2048,
      'temperature': 0.2,
    });

    final response = await http
        .post(
          Uri.parse(_kGroqEndpoint),
          headers: {
            'Content-Type':  'application/json',
            'Authorization': 'Bearer $_kGroqApiKey',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 60));

    return _handleResponse(response);
  }

  // ── Private: Groq Text API call (PDF ke liye) ────────────────────────
  Future<List<StudyQuestion>> _callTextApi(String text) async {
    final prompt = '''
Neeche diye gaye educational content se $_kQuestionCount multiple choice questions banao jo student ki samajh test kare.

Content:
---
$text
---

SIRF ek valid JSON array return karo — koi extra text, markdown ya explanation nahi.

Format (EXACTLY):
[
  {
    "question": "Question text (same language as content — Hindi/English/Hinglish)",
    "options": ["Option 1 text", "Option 2 text", "Option 3 text", "Option 4 text"],
    "correct_index": 0,
    "explanation": "Brief explanation why this is correct"
  }
]

Rules:
- options mein "A)", "B)" prefix bilkul mat lagao — sirf text
- correct_index MUST be 0, 1, 2, ya 3
- Exactly $_kQuestionCount questions banao
- Questions meaningful aur educational hon
''';

    final body = jsonEncode({
      'model': _kTextModel,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'max_tokens': 2048,
      'temperature': 0.2,
    });

    final response = await http
        .post(
          Uri.parse(_kGroqEndpoint),
          headers: {
            'Content-Type':  'application/json',
            'Authorization': 'Bearer $_kGroqApiKey',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 45));

    return _handleResponse(response);
  }

  // ── Private: Response handle + parse ─────────────────────────────────
  List<StudyQuestion> _handleResponse(http.Response response) {
    if (response.statusCode == 200) {
      final data    = jsonDecode(response.body) as Map<String, dynamic>;
      final content = data['choices'][0]['message']['content'] as String;
      return _parseQuestions(content);
    } else if (response.statusCode == 401) {
      throw Exception('❌ Invalid API key! console.groq.com par check karo.');
    } else if (response.statusCode == 429) {
      throw Exception('⏳ Rate limit ho gaya. Thodi der baad try karo.');
    } else {
      final err = jsonDecode(response.body);
      throw Exception(
        'API Error ${response.statusCode}: ${err['error']?['message'] ?? 'Unknown error'}',
      );
    }
  }

  // ── Private: JSON parse ───────────────────────────────────────────────
  List<StudyQuestion> _parseQuestions(String raw) {
    // JSON array extract karo (AI kabhi kabhi extra text add kar deta hai)
    final match = RegExp(r'\[[\s\S]*\]').firstMatch(raw);
    if (match == null) {
      throw Exception('AI se valid questions nahi mile. Dobara try karo.');
    }

    final List<dynamic> list;
    try {
      list = jsonDecode(match.group(0)!) as List;
    } catch (_) {
      throw Exception('Questions parse nahi ho sake. Dobara try karo.');
    }

    final questions = <StudyQuestion>[];
    for (final item in list) {
      try {
        final map     = item as Map<String, dynamic>;
        final options = (map['options'] as List).cast<String>();
        if (options.length != 4) continue;

        var idx = (map['correct_index'] as num).toInt();
        if (idx < 0 || idx > 3) idx = 0;

        questions.add(StudyQuestion(
          question:     (map['question']    as String).trim(),
          options:      options.map((o) => o.trim()).toList(),
          correctIndex: idx,
          explanation:  (map['explanation'] as String? ?? '').trim(),
        ));
      } catch (_) {
        continue; // Malformed question skip karo
      }
    }

    if (questions.isEmpty) {
      throw Exception('Koi valid question nahi bana. Content clearer karo aur retry karo.');
    }

    return questions;
  }

  // ── Private: API key check ────────────────────────────────────────────
  void _checkApiKey() {
    if (_kGroqApiKey == 'YOUR_GROQ_API_KEY_HERE') {
      throw Exception(
        '⚠️ Groq API key set nahi ki!\n\n'
        'study_ai_service.dart mein _kGroqApiKey mein apni key daalo.\n'
        'Free key: https://console.groq.com',
      );
    }
  }
}
