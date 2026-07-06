// lib/features/study_ai/study_ai_screen.dart
// FIX: Added animated progress bar + elapsed time to processing/loading state
// The brain animation stays; LinearProgressIndicator + timer added below it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart'; // or pdfx

import '../../services/groq_service.dart';
import '../../theme/app_theme.dart';

// ─── State Enum ──────────────────────────────────────────────────────────────

enum _StudyAiState { upload, processing, quiz, results }

// ─── Model ───────────────────────────────────────────────────────────────────

class _Question {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const _Question({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class StudyAiScreen extends StatefulWidget {
  const StudyAiScreen({super.key});

  @override
  State<StudyAiScreen> createState() => _StudyAiScreenState();
}

class _StudyAiScreenState extends State<StudyAiScreen>
    with TickerProviderStateMixin {

  // ── State ─────────────────────────────────────────────────────────────────
  _StudyAiState _state = _StudyAiState.upload;
  List<_Question> _questions = [];
  int _currentQ = 0;
  int _selectedOption = -1;
  bool _showAnswer = false;
  int _correctCount = 0;
  String _errorMsg = '';

  // ── Progress (FIX: loading progress bar) ─────────────────────────────────
  late AnimationController _progressCtrl;
  late AnimationController _brainSpinCtrl;
  Timer? _elapsedTimer;
  int _elapsedSec = 0;

  // ── Quiz answer animation ─────────────────────────────────────────────────
  late AnimationController _optionAnim;

  // ── Services ──────────────────────────────────────────────────────────────
  final _groq = GroqService();
  final _imgPicker = ImagePicker();

  // ── Processing status messages (rotate while loading) ────────────────────
  final List<String> _processingMsgs = [
    'Notes padhh raha hai... 📖',
    'Questions soch raha hai... 🤔',
    'MCQs bana raha hai... ✏️',
    'Almost done... ⚡',
  ];
  int _msgIndex = 1; // start at "Questions soch raha hai"
  Timer? _msgTimer;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))
      ..addListener(() => setState(() {}));

    _brainSpinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _optionAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _brainSpinCtrl.dispose();
    _optionAnim.dispose();
    _elapsedTimer?.cancel();
    _msgTimer?.cancel();
    super.dispose();
  }

  // ── Progress Helpers ──────────────────────────────────────────────────────

  void _startProgress() {
    _elapsedSec = 0;
    _msgIndex = 0;
    _progressCtrl.value = 0;

    // Animate progress to 0.85 over 40 seconds (eases out near the end)
    _progressCtrl.animateTo(
      0.85,
      duration: const Duration(seconds: 40),
      curve: Curves.easeOut,
    );

    // Elapsed second counter
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSec++);
    });

    // Rotate processing messages every ~8 seconds
    _msgTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) {
        setState(() {
          _msgIndex = (_msgIndex + 1) % _processingMsgs.length;
        });
      }
    });
  }

  void _finishProgress() {
    _elapsedTimer?.cancel();
    _msgTimer?.cancel();
    _progressCtrl.animateTo(1.0, duration: const Duration(milliseconds: 400));
  }

  void _stopProgress() {
    _elapsedTimer?.cancel();
    _msgTimer?.cancel();
    _progressCtrl.stop();
    _progressCtrl.value = 0;
  }

  String get _elapsedLabel {
    if (_elapsedSec < 60) return '${_elapsedSec}s';
    return '${_elapsedSec ~/ 60}m ${_elapsedSec % 60}s';
  }

  // ── File Processing ───────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final src = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Photo Source', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            child: const Text('Camera', style: TextStyle(color: AppTheme.accentCyan)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const Text('Gallery', style: TextStyle(color: AppTheme.accentViolet)),
          ),
        ],
      ),
    );
    if (src == null) return;

    final xFile = await _imgPicker.pickImage(source: src, imageQuality: 85);
    if (xFile == null) return;

    await _processImage(File(xFile.path));
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    await _processPdf(file);
  }

  Future<void> _processImage(File file) async {
    setState(() {
      _state = _StudyAiState.processing;
      _errorMsg = '';
    });
    _startProgress();

    try {
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      final ext = file.path.split('.').last.toLowerCase();
      final mime = (ext == 'png') ? 'image/png' : 'image/jpeg';

      final raw = await _groq.analyzeImage(
        base64Image: b64,
        mediaType: mime,
        prompt: _imageSystemPrompt,
      );

      _finishProgress();
      await Future.delayed(const Duration(milliseconds: 400));
      _parseAndShowQuiz(raw);
    } catch (e) {
      _stopProgress();
      setState(() {
        _state = _StudyAiState.upload;
        _errorMsg = _friendlyError(e);
      });
    }
  }

  Future<void> _processPdf(File file) async {
    setState(() {
      _state = _StudyAiState.processing;
      _errorMsg = '';
    });
    _startProgress();

    try {
      final bytes = await file.readAsBytes();
      final doc = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(doc);
      final text = extractor.extractText();
      doc.dispose();

      if (text.trim().isEmpty) {
        throw Exception('PDF mein koi text nahi mila (scanned PDF ho sakta hai).');
      }

      final raw = await _groq.generateStudyQuestions(
        content: text.substring(0, math.min(text.length, 8000)),
        systemPrompt: _pdfSystemPrompt,
      );

      _finishProgress();
      await Future.delayed(const Duration(milliseconds: 400));
      _parseAndShowQuiz(raw);
    } catch (e) {
      _stopProgress();
      setState(() {
        _state = _StudyAiState.upload;
        _errorMsg = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('429') || s.contains('rate limit') || s.contains('Rate limit')) {
      return 'Rate limit hit — AI retry kar raha tha lekin nahi hua. Thodi der baad dobara try karo.';
    }
    if (s.contains('timeout') || s.contains('TimeoutException')) {
      return 'Request timeout — internet check karo aur dobara try karo.';
    }
    return 'Error: $s';
  }

  // ── Quiz Parsing ──────────────────────────────────────────────────────────

  void _parseAndShowQuiz(String raw) {
    try {
      // Expect JSON array of {question, options:[...], correct_index, explanation}
      final cleaned = raw.replaceAll(RegExp(r'```json|```'), '').trim();
      final list = jsonDecode(cleaned) as List<dynamic>;

      _questions = list.map((e) {
        final m = e as Map<String, dynamic>;
        return _Question(
          question: m['question'] as String,
          options: List<String>.from(m['options'] as List),
          correctIndex: m['correct_index'] as int,
          explanation: m['explanation'] as String? ?? '',
        );
      }).toList();

      setState(() {
        _currentQ = 0;
        _selectedOption = -1;
        _showAnswer = false;
        _correctCount = 0;
        _state = _StudyAiState.quiz;
      });
    } catch (_) {
      setState(() {
        _state = _StudyAiState.upload;
        _errorMsg = 'Questions parse nahi hue. Dobara try karo.';
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDeep,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF00D4AA)],
                ),
              ),
              child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'Study AI',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: switch (_state) {
          _StudyAiState.upload    => _buildUploadState(),
          _StudyAiState.processing => _buildProcessingState(),
          _StudyAiState.quiz      => _buildQuizState(),
          _StudyAiState.results   => _buildResultsState(),
        },
      ),
    );
  }

  // ── Upload State ──────────────────────────────────────────────────────────

  Widget _buildUploadState() {
    return SingleChildScrollView(
      key: const ValueKey('upload'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Apne notes scan karo\nya PDF upload karo',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 22,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'AI MCQ questions banayega — bilkul exam jaisa 🎯',
            style: TextStyle(color: Colors.white60, fontFamily: 'Poppins', fontSize: 14),
          ),

          if (_errorMsg.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMsg,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontFamily: 'Poppins'),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Camera / Gallery option
          _UploadOptionCard(
            icon: Icons.camera_alt_rounded,
            color: AppTheme.accentCyan,
            title: 'Notes Photo Lo',
            subtitle: 'Camera ya gallery se photo lo',
            onTap: _pickImage,
          ),

          const SizedBox(height: 16),

          // PDF option
          _UploadOptionCard(
            icon: Icons.picture_as_pdf_rounded,
            color: AppTheme.accentViolet,
            title: 'PDF Upload Karo',
            subtitle: 'Study material PDF se questions banao',
            onTap: _pickPdf,
          ),

          const SizedBox(height: 32),

          Center(
            child: Text(
              'SSC CGL, UPSC, Banking — sab ke liye',
              style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12, fontFamily: 'Poppins'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Processing State (FIX: progress bar added) ────────────────────────────

  Widget _buildProcessingState() {
    return Center(
      key: const ValueKey('processing'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            // ── Brain icon with spinning arc ──────────────────────────────
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Spinning green arc
                  AnimatedBuilder(
                    animation: _brainSpinCtrl,
                    builder: (_, __) => Transform.rotate(
                      angle: _brainSpinCtrl.value * 2 * math.pi,
                      child: CustomPaint(
                        size: const Size(120, 120),
                        painter: _ArcPainter(
                          color: AppTheme.accentCyan,
                          strokeWidth: 3,
                          sweepFraction: 0.72,
                        ),
                      ),
                    ),
                  ),
                  // Brain emoji / icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('🧠', style: TextStyle(fontSize: 36)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Rotating status message ───────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Text(
                _processingMsgs[_msgIndex],
                key: ValueKey(_msgIndex),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Dot indicator ─────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final active = i == _msgIndex % 4;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? AppTheme.accentCyan : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 24),

            // ── FIX: Linear Progress Bar ──────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progressCtrl.value,
                minHeight: 6,
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation<Color>(
                  Color.lerp(AppTheme.accentCyan, AppTheme.accentViolet,
                      _progressCtrl.value)!,
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── Elapsed time + percentage ─────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '⏱ $_elapsedLabel',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
                Text(
                  '${(_progressCtrl.value * 100).toInt()}%',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Text(
              'AI questions bana raha hai — thoda wait karo...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontFamily: 'Poppins',
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Quiz State ────────────────────────────────────────────────────────────

  Widget _buildQuizState() {
    if (_questions.isEmpty) return const SizedBox.shrink();

    final q = _questions[_currentQ];
    final optionLabels = ['A', 'B', 'C', 'D'];

    return SingleChildScrollView(
      key: const ValueKey('quiz'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress
          Row(
            children: [
              Text(
                'Q ${_currentQ + 1} / ${_questions.length}',
                style: const TextStyle(
                  color: AppTheme.accentCyan,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (_currentQ + 1) / _questions.length,
                    backgroundColor: Colors.white10,
                    color: AppTheme.accentCyan,
                    minHeight: 4,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Question
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Text(
              q.question,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                height: 1.5,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Options
          ...List.generate(q.options.length, (i) {
            Color bg = AppTheme.bgCard;
            Color border = Colors.white12;
            Color textColor = Colors.white70;

            if (_selectedOption == i) {
              if (_showAnswer) {
                if (i == q.correctIndex) {
                  bg = Colors.green.withOpacity(0.15);
                  border = Colors.green;
                  textColor = Colors.white;
                } else {
                  bg = Colors.red.withOpacity(0.15);
                  border = Colors.redAccent;
                  textColor = Colors.white;
                }
              } else {
                bg = AppTheme.accentViolet.withOpacity(0.15);
                border = AppTheme.accentViolet;
                textColor = Colors.white;
              }
            } else if (_showAnswer && i == q.correctIndex) {
              bg = Colors.green.withOpacity(0.12);
              border = Colors.green.withOpacity(0.6);
              textColor = Colors.white;
            }

            return GestureDetector(
              onTap: _showAnswer ? null : () {
                setState(() {
                  _selectedOption = i;
                  _showAnswer = true;
                  if (i == q.correctIndex) _correctCount++;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: border.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        optionLabels[i],
                        style: TextStyle(
                          color: border == Colors.white12 ? Colors.white54 : border,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        q.options[i],
                        style: TextStyle(
                          color: textColor,
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (_showAnswer && i == q.correctIndex)
                      const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                    if (_showAnswer && _selectedOption == i && i != q.correctIndex)
                      const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 20),
                  ],
                ),
              ),
            );
          }),

          // Explanation
          if (_showAnswer && q.explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accentCyan.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accentCyan.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.lightbulb_rounded, color: AppTheme.accentCyan, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Explanation',
                        style: TextStyle(
                          color: AppTheme.accentCyan,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    q.explanation,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontFamily: 'Poppins',
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_showAnswer) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_currentQ < _questions.length - 1) {
                    setState(() {
                      _currentQ++;
                      _selectedOption = -1;
                      _showAnswer = false;
                    });
                  } else {
                    setState(() => _state = _StudyAiState.results);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentViolet,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _currentQ < _questions.length - 1 ? 'Next Question →' : 'Results Dekho 🏆',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Results State ─────────────────────────────────────────────────────────

  Widget _buildResultsState() {
    final percentage = _questions.isEmpty
        ? 0
        : ((_correctCount / _questions.length) * 100).round();
    final stars = percentage >= 80
        ? 3
        : percentage >= 50
            ? 2
            : 1;

    return Center(
      key: const ValueKey('results'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '⭐' * stars,
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(height: 16),
            Text(
              '$percentage%',
              style: TextStyle(
                color: percentage >= 80 ? Colors.greenAccent : AppTheme.accentCyan,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                fontSize: 56,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_correctCount / ${_questions.length} correct',
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'Poppins',
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              percentage >= 80
                  ? 'Excellent! Ekdum ready ho! 🔥'
                  : percentage >= 50
                      ? 'Acha attempt! Thoda aur practice karo 💪'
                      : 'Keep studying! Hosla mat haaro 📚',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontFamily: 'Poppins', fontSize: 14),
            ),
            const SizedBox(height: 40),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _state = _StudyAiState.quiz;
                      _currentQ = 0;
                      _selectedOption = -1;
                      _showAnswer = false;
                      _correctCount = 0;
                    }),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.accentViolet),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Retry 🔄',
                        style: TextStyle(color: AppTheme.accentViolet, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() => _state = _StudyAiState.upload),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentViolet,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('New Quiz ✨',
                        style: TextStyle(color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── System Prompts ────────────────────────────────────────────────────────

  static const _imageSystemPrompt = '''
You are an expert exam question maker. The user has uploaded a photo of study notes.
Generate exactly 5 MCQ questions from the visible content.
Return ONLY valid JSON (no extra text, no markdown fences):
[
  {
    "question": "Question text here?",
    "options": ["Option A", "Option B", "Option C", "Option D"],
    "correct_index": 0,
    "explanation": "Brief explanation of why this is correct."
  }
]
Make questions exam-style (SSC CGL / UPSC level). Do not add any text before or after the JSON.
''';

  static const _pdfSystemPrompt = '''
You are an expert exam question maker. Based on the provided study material text,
generate exactly 8 MCQ questions.
Return ONLY valid JSON (no extra text, no markdown fences):
[
  {
    "question": "Question text here?",
    "options": ["Option A", "Option B", "Option C", "Option D"],
    "correct_index": 0,
    "explanation": "Brief explanation of why this is correct."
  }
]
Make questions exam-style (SSC CGL / UPSC level). Do not add any text before or after the JSON.
''';
}

// ─── Upload Option Card ────────────────────────────────────────────────────────

class _UploadOptionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _UploadOptionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontFamily: 'Poppins',
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Arc Painter ──────────────────────────────────────────────────────────────

class _ArcPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double sweepFraction; // 0..1

  const _ArcPainter({
    required this.color,
    required this.strokeWidth,
    required this.sweepFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2,
        size.width - strokeWidth, size.height - strokeWidth);

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * sweepFraction,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.sweepFraction != sweepFraction;
}
