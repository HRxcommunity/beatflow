// ╔══════════════════════════════════════════════════════════════════════╗
// ║  Study AI Screen — Padhai ka AI Partner 📚                          ║
// ╚══════════════════════════════════════════════════════════════════════╝

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme/app_theme.dart';
import 'study_ai_service.dart';

// ─── Screen States ────────────────────────────────────────────────────
enum _StudyState { idle, processing, quiz, result }

// ─── Main Screen ──────────────────────────────────────────────────────
class StudyAiScreen extends StatefulWidget {
  const StudyAiScreen({super.key});

  @override
  State<StudyAiScreen> createState() => _StudyAiScreenState();
}

class _StudyAiScreenState extends State<StudyAiScreen>
    with TickerProviderStateMixin {
  // ── State ─────────────────────────────────────────────────────────
  _StudyState _screenState = _StudyState.idle;
  List<StudyQuestion> _questions = [];
  int   _currentIndex    = 0;
  int   _score           = 0;
  int?  _selectedOption;
  bool  _showExplanation = false;
  String _processingMsg  = 'Analyze kiya ja raha hai...';
  String? _errorMsg;

  // ── Animation ─────────────────────────────────────────────────────
  late final AnimationController _bounceCtrl;
  late final Animation<double>   _bounceAnim;
  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 450),
    );
    _bounceAnim = CurvedAnimation(
      parent: _bounceCtrl,
      curve:  Curves.elasticOut,
    );
    _fadeCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 300),
      value:    1.0,
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ─── Animate new card in ───────────────────────────────────────────
  void _animateIn() {
    _bounceCtrl.forward(from: 0);
    _fadeCtrl.forward(from: 0);
  }

  // ─── Camera se photo ──────────────────────────────────────────────
  Future<void> _pickCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source:       ImageSource.camera,
      maxWidth:     1280,
      maxHeight:    1280,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    _processImage(File(picked.path));
  }

  // ─── Gallery se photo ─────────────────────────────────────────────
  Future<void> _pickGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source:       ImageSource.gallery,
      maxWidth:     1280,
      maxHeight:    1280,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    _processImage(File(picked.path));
  }

  // ─── Image process ────────────────────────────────────────────────
  Future<void> _processImage(File file) async {
    setState(() {
      _screenState   = _StudyState.processing;
      _processingMsg = 'Photo analyze kiya ja raha hai... 📷\nAI content padh raha hai';
      _errorMsg      = null;
    });
    try {
      final qs = await StudyAiService.instance.generateFromImage(file);
      _startQuiz(qs);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _screenState = _StudyState.idle;
        _errorMsg    = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  // ─── PDF pick + process ───────────────────────────────────────────
  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type:              FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final path = result.files.first.path;
    if (path == null) return;

    setState(() {
      _screenState   = _StudyState.processing;
      _processingMsg = 'PDF padha ja raha hai... 📄\nText extract ho raha hai';
      _errorMsg      = null;
    });
    try {
      final qs = await StudyAiService.instance.generateFromPdf(File(path));
      _startQuiz(qs);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _screenState = _StudyState.idle;
        _errorMsg    = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  // ─── Quiz start ───────────────────────────────────────────────────
  void _startQuiz(List<StudyQuestion> questions) {
    setState(() {
      _questions       = questions;
      _currentIndex    = 0;
      _score           = 0;
      _selectedOption  = null;
      _showExplanation = false;
      _screenState     = _StudyState.quiz;
    });
    _animateIn();
  }

  // ─── Option select ────────────────────────────────────────────────
  void _selectOption(int idx) {
    if (_selectedOption != null) return;
    final correct = _questions[_currentIndex].correctIndex;
    setState(() {
      _selectedOption  = idx;
      _showExplanation = true;
      if (idx == correct) _score++;
    });
  }

  // ─── Next question / finish ───────────────────────────────────────
  void _next() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOption  = null;
        _showExplanation = false;
      });
      _animateIn();
    } else {
      setState(() => _screenState = _StudyState.result);
      _animateIn();
    }
  }

  // ─── Reset to idle ────────────────────────────────────────────────
  void _reset() {
    setState(() {
      _screenState     = _StudyState.idle;
      _questions       = [];
      _currentIndex    = 0;
      _score           = 0;
      _selectedOption  = null;
      _showExplanation = false;
      _errorMsg        = null;
    });
  }

  // ─── Replay same questions ─────────────────────────────────────────
  void _replay() => _startQuiz(_questions);

  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDeep,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  const Color(0xFF10B981).withOpacity(0.3),
                  accent.withOpacity(0.2),
                ]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('📚', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            const Text(
              'Study AI',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        // Show score during quiz
        actions: [
          if (_screenState == _StudyState.quiz)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '$_score / ${_questions.length}',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
        child: switch (_screenState) {
          _StudyState.idle       => _buildIdle(),
          _StudyState.processing => _buildProcessing(),
          _StudyState.quiz       => _buildQuiz(),
          _StudyState.result     => _buildResult(),
        },
      ),
    );
  }

  // ══════════════════════════════════════════
  //  IDLE — Upload Options
  // ══════════════════════════════════════════
  Widget _buildIdle() {
    final accent = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        children: [
          // ── Hero illustration ──────────────────────
          Container(
            margin: const EdgeInsets.symmetric(vertical: 24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF10B981).withOpacity(0.18),
                  AppTheme.bgDeep,
                ],
              ),
            ),
            child: const Text('📚', style: TextStyle(fontSize: 72)),
          ),

          // ── Title ─────────────────────────────────
          const Text(
            'Padhai Smart Karo! 🎯',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Book ki photo lo ya PDF upload karo —\nAI tumse questions poochega!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),

          // ── Upload options ─────────────────────────
          _UploadCard(
            emoji:    '📷',
            title:    'Camera se Photo lo',
            subtitle: 'Book ya notes ki photo kheecho',
            gradient: [const Color(0xFF7C3AED), const Color(0xFF9D4EDD)],
            onTap:    _pickCamera,
          ),
          const SizedBox(height: 4),
          // Gallery option (smaller)
          _SmallOptionBtn(
            icon:  Icons.photo_library_rounded,
            label: 'Ya Gallery se choose karo',
            onTap: _pickGallery,
            color: const Color(0xFF7C3AED),
          ),
          const SizedBox(height: 16),

          _UploadCard(
            emoji:    '📄',
            title:    'PDF Upload karo',
            subtitle: 'Notes ya textbook ka PDF choose karo',
            gradient: [const Color(0xFF0EA5E9), const Color(0xFF0284C7)],
            onTap:    _pickPdf,
          ),
          const SizedBox(height: 24),

          // ── Error ──────────────────────────────────
          if (_errorMsg != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:        Colors.red.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
                border:       Border.all(color: Colors.red.withOpacity(0.30)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMsg!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Tips ───────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:        AppTheme.bgCard,
              borderRadius: BorderRadius.circular(16),
              border:       Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💡 Tips for Best Results',
                  style: TextStyle(
                    color:      const Color(0xFF10B981),
                    fontWeight: FontWeight.w700,
                    fontSize:   13,
                  ),
                ),
                const SizedBox(height: 10),
                const _TipRow(icon: '✅', text: 'Clear aur achhi roshni mein photo lo'),
                const _TipRow(icon: '✅', text: 'PDF ke pehle 10 pages analyze hongi'),
                const _TipRow(icon: '✅', text: 'History, Science, Math — sab subjects'),
                const _TipRow(icon: '✅', text: 'Hindi aur English — dono languages'),
                const _TipRow(icon: '✅', text: 'Scanned PDF? Camera option use karo'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  PROCESSING — Loading
  // ══════════════════════════════════════════
  Widget _buildProcessing() {
    final accent = Theme.of(context).colorScheme.primary;
    return Center(
      key: const ValueKey('processing'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width:  80,
              height: 80,
              child: CircularProgressIndicator(strokeWidth: 3, color: accent),
            ),
            const SizedBox(height: 32),
            Text(
              _processingMsg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize:   18,
                fontWeight: FontWeight.w600,
                color:      Colors.white,
                height:     1.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Thoda wait karo — AI questions bana raha hai...',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  QUIZ — Questions
  // ══════════════════════════════════════════
  Widget _buildQuiz() {
    final question = _questions[_currentIndex];
    final total    = _questions.length;
    final accent   = Theme.of(context).colorScheme.primary;
    final answered = _selectedOption != null;

    return ScaleTransition(
      key:   const ValueKey('quiz'),
      scale: _bounceAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Progress bar ─────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color:        accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border:       Border.all(color: accent.withOpacity(0.3)),
                    ),
                    child: Text(
                      'Q ${_currentIndex + 1} / $total',
                      style: TextStyle(
                        color:      accent,
                        fontWeight: FontWeight.w700,
                        fontSize:   12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value:           (_currentIndex + 1) / total,
                        backgroundColor: Colors.white.withOpacity(0.08),
                        color:           accent,
                        minHeight:       6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Question card ────────────────────────────────
              Container(
                width:   double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin:  Alignment.topLeft,
                    end:    Alignment.bottomRight,
                    colors: [
                      accent.withOpacity(0.14),
                      AppTheme.bgCard,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accent.withOpacity(0.22)),
                  boxShadow: [
                    BoxShadow(
                      color:      accent.withOpacity(0.08),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('❓', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text(
                          'Sawaal',
                          style: TextStyle(
                            color:      accent,
                            fontSize:   12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      question.question,
                      style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   16,
                        fontWeight: FontWeight.w600,
                        height:     1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Options ──────────────────────────────────────
              ...List.generate(4, (i) => _buildOption(i, question, answered)),
              const SizedBox(height: 12),

              // ── Explanation ──────────────────────────────────
              if (_showExplanation && question.explanation.isNotEmpty)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  margin:   const EdgeInsets.only(bottom: 16),
                  padding:  const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color:        Colors.amber.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border:       Border.all(color: Colors.amber.withOpacity(0.22)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💡', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          question.explanation,
                          style: const TextStyle(
                            color:  Colors.amber,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Next button ──────────────────────────────────
              if (answered)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    child: Text(
                      _currentIndex < _questions.length - 1
                          ? 'Agla Sawaal  →'
                          : 'Score Dekho  🏆',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize:   16,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption(int i, StudyQuestion q, bool answered) {
    final accent    = Theme.of(context).colorScheme.primary;
    final isSelected = _selectedOption == i;
    final isCorrect  = i == q.correctIndex;

    Color bgColor, borderColor, textColor;
    if (!answered) {
      bgColor     = AppTheme.bgCard;
      borderColor = Colors.white.withOpacity(0.10);
      textColor   = Colors.white;
    } else if (isCorrect) {
      bgColor     = const Color(0xFF10B981).withOpacity(0.14);
      borderColor = const Color(0xFF10B981).withOpacity(0.55);
      textColor   = const Color(0xFF6EE7B7);
    } else if (isSelected) {
      bgColor     = Colors.red.withOpacity(0.12);
      borderColor = Colors.red.withOpacity(0.45);
      textColor   = const Color(0xFFFCA5A5);
    } else {
      bgColor     = AppTheme.bgCard.withOpacity(0.45);
      borderColor = Colors.white.withOpacity(0.04);
      textColor   = AppTheme.textSecondary;
    }

    final labels = ['A', 'B', 'C', 'D'];
    IconData? trailingIcon;
    Color? trailingColor;
    if (answered && isCorrect) {
      trailingIcon  = Icons.check_circle_rounded;
      trailingColor = const Color(0xFF10B981);
    } else if (answered && isSelected && !isCorrect) {
      trailingIcon  = Icons.cancel_rounded;
      trailingColor = Colors.redAccent;
    }

    return GestureDetector(
      onTap: answered ? null : () => _selectOption(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        margin:   const EdgeInsets.only(bottom: 12),
        padding:  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color:        bgColor,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: borderColor, width: 1.2),
        ),
        child: Row(
          children: [
            // Label bubble
            Container(
              width:  30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: answered && isCorrect
                    ? const Color(0xFF10B981).withOpacity(0.25)
                    : answered && isSelected && !isCorrect
                        ? Colors.red.withOpacity(0.25)
                        : accent.withOpacity(0.13),
              ),
              child: Center(
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize:   13,
                    color: answered && isCorrect
                        ? const Color(0xFF10B981)
                        : answered && isSelected && !isCorrect
                            ? Colors.redAccent
                            : accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Option text
            Expanded(
              child: Text(
                q.options[i],
                style: TextStyle(
                  color:      textColor,
                  fontSize:   14,
                  fontWeight: (isSelected || (answered && isCorrect))
                      ? FontWeight.w600
                      : FontWeight.w400,
                  height: 1.35,
                ),
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 8),
              Icon(trailingIcon, color: trailingColor, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  RESULT — Score Card
  // ══════════════════════════════════════════
  Widget _buildResult() {
    final accent      = Theme.of(context).colorScheme.primary;
    final total       = _questions.length;
    final pct         = (_score / total * 100).round();
    final stars       = (pct / 20).ceil().clamp(0, 5);

    final (emoji, title, sub) = switch (pct) {
      >= 80 => ('🏆', 'Zabardast!',     'Tu toh champion hai bhai!'),
      >= 60 => ('⭐', 'Bahut Achha!',   'Aur thodi mehnat aur perfect hoga'),
      >= 40 => ('💪', 'Theek Hai!',     'Dobara padh ke retry karo'),
      _     => ('📖', 'Mehnat Karo!',   'Content phir se padho aur try karo'),
    };

    final scoreColor = pct >= 80
        ? const Color(0xFF10B981)
        : pct >= 60
            ? Colors.amber
            : pct >= 40
                ? Colors.orange
                : Colors.redAccent;

    return ScaleTransition(
      key:   const ValueKey('result'),
      scale: _bounceAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          child: Column(
            children: [
              // Emoji
              Text(emoji, style: const TextStyle(fontSize: 80)),
              const SizedBox(height: 12),

              Text(
                title,
                style: const TextStyle(
                  fontSize:   32,
                  fontWeight: FontWeight.w800,
                  color:      Colors.white,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                sub,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15),
              ),
              const SizedBox(height: 36),

              // ── Score circle ─────────────────────────────────
              Container(
                width:  180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    scoreColor.withOpacity(0.20),
                    AppTheme.bgCard,
                  ]),
                  border: Border.all(color: scoreColor.withOpacity(0.45), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color:      scoreColor.withOpacity(0.20),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$_score',
                      style: TextStyle(
                        fontSize:   56,
                        fontWeight: FontWeight.w900,
                        color:      scoreColor,
                        fontFamily: 'Poppins',
                        height:     1.1,
                      ),
                    ),
                    Text(
                      'of $total correct',
                      style: const TextStyle(
                        color:      AppTheme.textSecondary,
                        fontSize:   13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Stars ────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Icon(
                      i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: i < stars ? Colors.amber : Colors.white.withOpacity(0.18),
                      size: 38,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              Text(
                '$pct% Score',
                style: TextStyle(
                  color:      scoreColor,
                  fontWeight: FontWeight.w700,
                  fontSize:   16,
                ),
              ),
              const SizedBox(height: 36),

              // ── Question review summary ───────────────────────
              _ReviewSummary(questions: _questions, score: _score),
              const SizedBox(height: 28),

              // ── Action buttons ───────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('Naya Topic'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side:            BorderSide(color: accent.withOpacity(0.45)),
                        padding:         const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _replay,
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      label: const Text('Dobara Khelo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding:         const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Helper Widgets
// ──────────────────────────────────────────────────────────────────────

/// Upload option — big card
class _UploadCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _UploadCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin:  Alignment.topLeft,
            end:    Alignment.bottomRight,
            colors: [
              gradient.first.withOpacity(0.18),
              AppTheme.bgCard,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: gradient.first.withOpacity(0.40)),
          boxShadow: [
            BoxShadow(
              color:      gradient.first.withOpacity(0.10),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width:  60,
              height: 60,
              decoration: BoxDecoration(
                shape:    BoxShape.circle,
                gradient: LinearGradient(colors: gradient.map((c) => c.withOpacity(0.5)).toList()),
              ),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 28))),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color:      Colors.white,
                      fontSize:   16,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: gradient.first.withOpacity(0.7), size: 24),
          ],
        ),
      ),
    );
  }
}

/// Small secondary button (gallery option)
class _SmallOptionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _SmallOptionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: color.withOpacity(0.7)),
        label: Text(
          label,
          style: TextStyle(color: color.withOpacity(0.7), fontSize: 12),
        ),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
      ),
    );
  }
}

/// Tip row in the tips card
class _TipRow extends StatelessWidget {
  final String icon;
  final String text;

  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color:    AppTheme.textSecondary,
                fontSize: 12,
                height:   1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Result screen — quick review of all questions
class _ReviewSummary extends StatelessWidget {
  final List<StudyQuestion> questions;
  final int score;

  const _ReviewSummary({required this.questions, required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:     const EdgeInsets.all(16),
      decoration:  BoxDecoration(
        color:        AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📋 Quick Review',
            style: TextStyle(
              color:      Colors.white,
              fontWeight: FontWeight.w700,
              fontSize:   14,
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(questions.length, (i) {
            final q = questions[i];
            // Note: we can't know which option was selected here (state is reset).
            // Just show correct answer for review.
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Q${i + 1}: ${q.question}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '✓ ${q.options[q.correctIndex]}',
                          style: const TextStyle(
                            color:      Color(0xFF10B981),
                            fontSize:   12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
