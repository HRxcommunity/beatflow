// ╔══════════════════════════════════════════════════════════════════════╗
// ║  Study AI Service — God Level Upgrade                               ║
// ║  PDF + Image → Unlimited Batched Questions                          ║
// ║  + Difficulty Levels + PYQ Detection + Subject Tags                 ║
// ╚══════════════════════════════════════════════════════════════════════╝

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../core/config/groq_config.dart';

// ─── API Config ──────────────────────────────────────────────────────
const String _kGroqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
const String _kVisionModel  = 'meta-llama/llama-4-scout-17b-16e-instruct';
const String _kTextModel    = 'llama-3.3-70b-versatile';

// ─── Batch config ─────────────────────────────────────────────────────
const int _kBatchSize    = 10;
const int _kPdfPageBatch = 5;
const int _kMaxPdfChars  = 5000;

// ─── Image round focus areas ──────────────────────────────────────────
const List<String> _kRoundFocus = [
  'main concepts, key terms aur definitions',
  'specific facts, dates, numbers aur statistics',
  'comparisons, causes, effects aur relationships',
  'real-world applications aur practical examples',
  'advanced, analytical aur tricky concepts',
];

// ─── Difficulty ───────────────────────────────────────────────────────
enum QuestionDifficulty { easy, medium, hard }

extension QuestionDifficultyExt on QuestionDifficulty {
  String get difficultyPrompt {
    switch (this) {
      case QuestionDifficulty.easy:
        return 'Simple aur seedhe facts-based questions. Beginner level. '
            'Direct answer. No tricky options.';
      case QuestionDifficulty.medium:
        return 'Moderate level. Mix of factual aur conceptual questions. '
            'Options mein 2 plausible distractors.';
      case QuestionDifficulty.hard:
        return 'Advanced, analytical, tricky questions. Apply-and-think level. '
            'All 4 options plausible. Conceptual depth required.';
    }
  }

  String get label {
    switch (this) {
      case QuestionDifficulty.easy:   return 'Easy';
      case QuestionDifficulty.medium: return 'Medium';
      case QuestionDifficulty.hard:   return 'Hard';
    }
  }

  String get emoji {
    switch (this) {
      case QuestionDifficulty.easy:   return '🟢';
      case QuestionDifficulty.medium: return '🟡';
      case QuestionDifficulty.hard:   return '🔴';
    }
  }
}

// ─── Model ────────────────────────────────────────────────────────────
class StudyQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  // PYQ & subject metadata
  final String? pyqInfo;    // e.g. "SSC CGL 2023, SSC CHSL 2022"
  final String? pyqCount;   // e.g. "3 baar poocha gaya"
  final String? subject;    // e.g. "History", "Polity", "Maths"
  final String? topicTag;   // e.g. "Mughal Empire", "Percentage"

  const StudyQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    this.pyqInfo,
    this.pyqCount,
    this.subject,
    this.topicTag,
  });

  Map<String, dynamic> toJson() => {
    'question':      question,
    'options':       options,
    'correct_index': correctIndex,
    'explanation':   explanation,
    'pyq_info':      pyqInfo,
    'pyq_count':     pyqCount,
    'subject':       subject,
    'topic_tag':     topicTag,
  };

  factory StudyQuestion.fromJson(Map<String, dynamic> m) => StudyQuestion(
    question:     (m['question'] as String? ?? '').trim(),
    options:      (m['options'] as List).cast<String>(),
    correctIndex: ((m['correct_index'] as num?)?.toInt() ?? 0).clamp(0, 3),
    explanation:  (m['explanation'] as String? ?? '').trim(),
    pyqInfo:      m['pyq_info']  as String?,
    pyqCount:     m['pyq_count'] as String?,
    subject:      m['subject']   as String?,
    topicTag:     m['topic_tag'] as String?,
  );
}

// ─── Service ──────────────────────────────────────────────────────────
class StudyAiService {
  StudyAiService._();
  static final instance = StudyAiService._();

  // ── Get total PDF page count ──────────────────────────────────────
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

  // ── Batch from Image ──────────────────────────────────────────────
  Future<List<StudyQuestion>> generateBatchFromImage(
    File imageFile, {
    int round = 1,
    QuestionDifficulty difficulty = QuestionDifficulty.medium,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final b64   = base64Encode(bytes);
    final ext   = imageFile.path.split('.').last.toLowerCase();
    final mime  = ext == 'png' ? 'image/png' : 'image/jpeg';
    final focus = _kRoundFocus[(round - 1).clamp(0, _kRoundFocus.length - 1)];
    final result = await _callVisionApi(b64, mime, focus: focus, difficulty: difficulty);
    return result;
  }

  // ── Batch from PDF ────────────────────────────────────────────────
  Future<List<StudyQuestion>> generateBatchFromPdf(
    File pdfFile, {
    required int startPage,
    QuestionDifficulty difficulty = QuestionDifficulty.medium,
  }) async {
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
    return _callTextApi(text, startPage: startPage, difficulty: difficulty);
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
        buf.writeln(extractor.extractText(startPageIndex: i, endPageIndex: i));
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
    String base64Data,
    String mime, {
    String focus = 'main concepts',
    QuestionDifficulty difficulty = QuestionDifficulty.medium,
  }) async {
    final prompt = '''
Is image mein jo educational content hai usse dhyan se padho.
Focus: $focus ke baare mein $_kBatchSize multiple choice questions banao.

DIFFICULTY LEVEL: ${difficulty.difficultyPrompt}

SIRF ek valid JSON array return karo — koi extra text, backticks ya explanation nahi.

Format:
[
  {
    "question": "Question text (Hindi/English/Hinglish)",
    "options": ["Option 1", "Option 2", "Option 3", "Option 4"],
    "correct_index": 0,
    "explanation": "Brief explanation",
    "pyq_info": "SSC CGL 2022, RRB NTPC 2023 mein poocha gaya",
    "pyq_count": "2-3 baar",
    "subject": "History",
    "topic_tag": "Mughal Empire"
  }
]

Rules:
- options mein A) B) prefix bilkul mat lagao — sirf text
- correct_index must be 0, 1, 2, ya 3
- Exactly $_kBatchSize questions
- IMPORTANT — Har question ke liye:
  * "pyq_info": Agar yeh topic SSC CGL, SSC CHSL, SSC MTS, SSC CPO, UPSC, RRB NTPC, RRB Group D, UP Police, IBPS, SBI PO, Delhi Police ya kisi bhi government exam mein aaya ho toh fill karo. Nahi pata toh null rakho.
  * "pyq_count": Kitni baar approximately government exams mein aaya (e.g. "3-4 baar"). Null if unknown.
  * "subject": ONE of: History / Geography / Polity / Economics / Science / Maths / English / Reasoning / Computer / General Awareness / Other
  * "topic_tag": Specific topic (e.g. "Mughal Empire", "Simple Interest", "Photosynthesis")
- Agar image mein text nahi: [{"question":"Image mein text nahi mila","options":["Clear photo lo","Better lighting use karo","Text wali page lo","Dobara try karo"],"correct_index":0,"explanation":"Clear photo se better results milte hain","pyq_info":null,"pyq_count":null,"subject":"Other","topic_tag":"Image Quality"}]
''';

    final body = jsonEncode({
      'model': _kVisionModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {'type': 'image_url', 'image_url': {'url': 'data:$mime;base64,$base64Data'}},
          ],
        }
      ],
      'max_tokens': 3500,
      'temperature': 0.3,
    });

    return _handleResponse(
      await http.post(
        Uri.parse(_kGroqEndpoint),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer ${GroqConfig.instance.effectiveKey}',
        },
        body: body,
      ).timeout(const Duration(seconds: 60)),
    );
  }

  // ── Text API (PDF) ────────────────────────────────────────────────
  Future<List<StudyQuestion>> _callTextApi(
    String text, {
    int startPage = 0,
    QuestionDifficulty difficulty = QuestionDifficulty.medium,
  }) async {
    final endPage = startPage + _kPdfPageBatch;
    final prompt  = '''
Neeche diye gaye educational content (Pages ${startPage + 1}–$endPage) se $_kBatchSize multiple choice questions banao.

DIFFICULTY LEVEL: ${difficulty.difficultyPrompt}

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
    "explanation": "Why this is correct",
    "pyq_info": "SSC CGL 2022, RRB NTPC 2023 mein poocha gaya",
    "pyq_count": "2-3 baar",
    "subject": "History",
    "topic_tag": "Mughal Empire"
  }
]

Rules: No A) B) prefix. correct_index 0-3. Exactly $_kBatchSize questions.
IMPORTANT — Har question ke liye:
- "pyq_info": Agar yeh topic SSC CGL, SSC CHSL, UPSC, RRB NTPC, IBPS, SBI PO ya kisi bhi government exam mein aaya ho toh fill karo. Nahi pata toh null.
- "pyq_count": Kitni baar approximately aaya (e.g. "3-4 baar"). Null if unknown.
- "subject": ONE of: History / Geography / Polity / Economics / Science / Maths / English / Reasoning / Computer / General Awareness / Other
- "topic_tag": Specific topic tag
''';

    final body = jsonEncode({
      'model': _kTextModel,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'max_tokens': 3500,
      'temperature': 0.3,
    });

    return _handleResponse(
      await http.post(
        Uri.parse(_kGroqEndpoint),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer ${GroqConfig.instance.effectiveKey}',
        },
        body: body,
      ).timeout(const Duration(seconds: 60)),
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
    final c = raw
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
          pyqInfo:      _nullOrString(m['pyq_info']),
          pyqCount:     _nullOrString(m['pyq_count']),
          subject:      _nullOrString(m['subject']),
          topicTag:     _nullOrString(m['topic_tag']),
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

  String? _nullOrString(dynamic v) {
    if (v == null || v == 'null' || (v is String && v.trim().isEmpty)) return null;
    return v as String?;
  }

}
