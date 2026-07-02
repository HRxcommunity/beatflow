// ╔══════════════════════════════════════════════════════════════════════╗
// ║  Study AI Screen — Unlimited Questions + Preview + Delete + Retest  ║
// ║                                                                      ║
// ║  Flow: idle → processing → PREVIEW → quiz → result                  ║
// ║        Preview: expand/delete questions, load more, start test       ║
// ║        Quiz:    Submit Test + End Test (exit dialog)                 ║
// ║        Result:  Retest + Edit Preview + New Topic                    ║
// ╚══════════════════════════════════════════════════════════════════════╝

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme/app_theme.dart';
import 'study_ai_service.dart';

enum _StudyState { idle, processing, preview, quiz, result }

// PDF page batch size — must match service constant
const int _kPdfPageBatch = 5;

class StudyAiScreen extends StatefulWidget {
  const StudyAiScreen({super.key});

  @override
  State<StudyAiScreen> createState() => _StudyAiScreenState();
}

class _StudyAiScreenState extends State<StudyAiScreen>
    with TickerProviderStateMixin {

  // ── Screen state ──────────────────────────────────────────────────
  _StudyState _screenState  = _StudyState.idle;
  String      _processingMsg = 'Analyze kiya ja raha hai...';
  String?     _errorMsg;

  // ── Preview pool (all generated questions) ─────────────────────────
  List<StudyQuestion> _allQuestions  = [];
  Set<int>            _expandedQ     = {};  // expanded card indices
  bool                _isLoadingMore = false;

  // ── Source tracking (for Load More) ──────────────────────────────
  File? _sourceFile;
  bool  _sourceIsImage  = true;
  int   _pdfPageOffset  = 0;   // next startPage for PDF batch
  int   _pdfTotalPages  = 0;
  int   _imageRound     = 1;   // increments for image variety

  // ── Active quiz state ─────────────────────────────────────────────
  List<StudyQuestion> _questions    = [];
  int   _currentIndex   = 0;
  int   _score          = 0;
  int?  _selectedOption;
  bool  _showExplanation = false;

  // ── Animations ────────────────────────────────────────────────────
  late final AnimationController _bounceCtrl;
  late final Animation<double>   _bounceAnim;
  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  // ── Getters ───────────────────────────────────────────────────────
  bool get _canLoadMore {
    if (_sourceFile == null) return false;
    if (_sourceIsImage) return true;       // unlimited image rounds
    return _pdfPageOffset < _pdfTotalPages;
  }

  bool get _pdfAllLoaded =>
      !_sourceIsImage && _pdfTotalPages > 0 && _pdfPageOffset >= _pdfTotalPages;

  // ─────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _bounceAnim =
        CurvedAnimation(parent: _bounceCtrl, curve: Curves.elasticOut);
    _fadeCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
        value: 1.0);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _animateIn() {
    _bounceCtrl.forward(from: 0);
    _fadeCtrl.forward(from: 0);
  }

  // ══════════════════════════════════════════
  //  SOURCE PICKING
  // ══════════════════════════════════════════

  Future<void> _pickCamera() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85);
    if (picked == null || !mounted) return;
    _processImage(File(picked.path));
  }

  Future<void> _pickGallery() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85);
    if (picked == null || !mounted) return;
    _processImage(File(picked.path));
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.isEmpty || !mounted) return;
    final path = result.files.first.path;
    if (path == null) return;
    _processPdf(File(path));
  }

  // ══════════════════════════════════════════
  //  PROCESSING — first batch generation
  // ══════════════════════════════════════════

  Future<void> _processImage(File file) async {
    setState(() {
      _screenState   = _StudyState.processing;
      _processingMsg = 'Photo analyze ho rahi hai... 📷\nAI questions bana raha hai';
      _errorMsg      = null;
      _sourceFile    = file;
      _sourceIsImage = true;
      _imageRound    = 1;
      _allQuestions  = [];
      _expandedQ     = {};
    });
    try {
      final qs =
          await StudyAiService.instance.generateBatchFromImage(file, round: 1);
      if (!mounted) return;
      setState(() {
        _allQuestions = qs;
        _imageRound   = 2;
        _screenState  = _StudyState.preview;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _screenState = _StudyState.idle;
        _errorMsg    = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _processPdf(File file) async {
    setState(() {
      _screenState   = _StudyState.processing;
      _processingMsg = 'PDF padha ja raha hai... 📄\nPages count ho rahi hai';
      _errorMsg      = null;
      _sourceFile    = file;
      _sourceIsImage = false;
      _pdfPageOffset = 0;
      _pdfTotalPages = 0;
      _allQuestions  = [];
      _expandedQ     = {};
    });
    try {
      final totalPages = await StudyAiService.instance.getPdfPageCount(file);
      if (!mounted) return;
      setState(() {
        _pdfTotalPages = totalPages;
        _processingMsg = 'Pages 1–5 se questions ban rahe hain... ✨';
      });
      final qs =
          await StudyAiService.instance.generateBatchFromPdf(file, startPage: 0);
      if (!mounted) return;
      setState(() {
        _allQuestions  = qs;
        _pdfPageOffset = _kPdfPageBatch;
        _screenState   = _StudyState.preview;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _screenState = _StudyState.idle;
        _errorMsg    = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  // ══════════════════════════════════════════
  //  LOAD MORE
  // ══════════════════════════════════════════

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_canLoadMore) return;
    setState(() => _isLoadingMore = true);
    try {
      List<StudyQuestion> qs;
      if (_sourceIsImage) {
        qs = await StudyAiService.instance
            .generateBatchFromImage(_sourceFile!, round: _imageRound);
        if (mounted) setState(() => _imageRound++);
      } else {
        qs = await StudyAiService.instance
            .generateBatchFromPdf(_sourceFile!, startPage: _pdfPageOffset);
        if (mounted) setState(() => _pdfPageOffset += _kPdfPageBatch);
      }
      if (!mounted) return;
      setState(() {
        _allQuestions.addAll(qs);
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ══════════════════════════════════════════
  //  PREVIEW ACTIONS
  // ══════════════════════════════════════════

  void _confirmDelete(int idx) {
    final q = _allQuestions[idx];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Question?',
            style: TextStyle(
                color: Colors.white, fontFamily: 'Poppins', fontSize: 15)),
        content: Text(
          q.question,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style:
              const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Raho', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteAt(idx);
            },
            child: const Text('Delete 🗑',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _deleteAt(int idx) {
    setState(() {
      _allQuestions.removeAt(idx);
      // Shift expanded set indices
      final newExp = <int>{};
      for (final e in _expandedQ) {
        if (e < idx) newExp.add(e);
        else if (e > idx) newExp.add(e - 1);
        // e == idx → deleted, skip
      }
      _expandedQ = newExp;
    });
  }

  void _startTest() {
    if (_allQuestions.isEmpty) return;
    _startQuiz(List.from(_allQuestions));
  }

  // ══════════════════════════════════════════
  //  QUIZ ACTIONS
  // ══════════════════════════════════════════

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

  void _selectOption(int idx) {
    if (_selectedOption != null) return;
    setState(() {
      _selectedOption  = idx;
      _showExplanation = true;
      if (idx == _questions[_currentIndex].correctIndex) _score++;
    });
  }

  void _next() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOption  = null;
        _showExplanation = false;
      });
      _animateIn();
    }
  }

  void _submitTest() {
    setState(() => _screenState = _StudyState.result);
    _animateIn();
  }

  void _replay() => _startQuiz(List.from(_questions));

  void _backToPreview() => setState(() => _screenState = _StudyState.preview);

  void _reset() {
    setState(() {
      _screenState   = _StudyState.idle;
      _questions     = [];
      _allQuestions  = [];
      _expandedQ     = {};
      _currentIndex  = 0;
      _score         = 0;
      _selectedOption  = null;
      _showExplanation = false;
      _errorMsg      = null;
      _sourceFile    = null;
      _sourceIsImage = true;
      _pdfPageOffset = 0;
      _pdfTotalPages = 0;
      _imageRound    = 1;
      _isLoadingMore = false;
    });
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Test Chhodna Hai?',
            style: TextStyle(
                color: Colors.white, fontFamily: 'Poppins', fontSize: 16)),
        content: Text(
          'Abhi tak $_score / ${_currentIndex + 1} correct.\n'
          'Kya karna chahte ho?',
          style:
              const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Ruko ↩',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitTest();
            },
            child: const Text('Score Dekho 🏆',
                style: TextStyle(color: Colors.amber)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _backToPreview();
            },
            child: const Text('Preview Par Jao 📋',
                style: TextStyle(color: Colors.blueAccent)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _reset();
            },
            child:
                const Text('Quit ✕', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: _buildAppBar(accent),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: switch (_screenState) {
          _StudyState.idle       => _buildIdle(),
          _StudyState.processing => _buildProcessing(),
          _StudyState.preview    => _buildPreview(),
          _StudyState.quiz       => _buildQuiz(),
          _StudyState.result     => _buildResult(),
        },
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────────
  AppBar _buildAppBar(Color accent) {
    return AppBar(
      backgroundColor: AppTheme.bgDeep,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded,
            color: Colors.white70, size: 20),
        onPressed: () {
          switch (_screenState) {
            case _StudyState.quiz:
              _showExitDialog();
            case _StudyState.result:
              _backToPreview();
            case _StudyState.preview:
              _reset();
            default:
              context.pop();
          }
        },
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
          const Text('Study AI',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ],
      ),
      actions: [
        // PREVIEW: Start Test button
        if (_screenState == _StudyState.preview && _allQuestions.isNotEmpty)
          TextButton.icon(
            onPressed: _startTest,
            icon: const Icon(Icons.play_arrow_rounded,
                color: Color(0xFF10B981), size: 18),
            label: Text(
              'Start (${_allQuestions.length}) →',
              style: const TextStyle(
                  color: Color(0xFF10B981),
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
          ),

        // QUIZ: Score + Submit + End
        if (_screenState == _StudyState.quiz) ...[
          // Live score chip
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded,
                    color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text(
                  '$_score/${_currentIndex + 1}',
                  style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Submit Test
          TextButton.icon(
            onPressed: _submitTest,
            icon: const Icon(Icons.check_circle_rounded,
                color: Colors.greenAccent, size: 18),
            label: const Text('Submit',
                style: TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            style:
                TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
          ),
          // End Test (exit dialog)
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined,
                color: Colors.white38, size: 22),
            tooltip: 'Test Khatam Karo',
            onPressed: _showExitDialog,
          ),
        ],
      ],
    );
  }

  // ══════════════════════════════════════════
  //  IDLE
  // ══════════════════════════════════════════
  Widget _buildIdle() {
    return SingleChildScrollView(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFF10B981).withOpacity(0.18),
                AppTheme.bgDeep,
              ]),
            ),
            child: const Text('📚', style: TextStyle(fontSize: 72)),
          ),
          const Text('Padhai Smart Karo! 🎯',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontFamily: 'Poppins')),
          const SizedBox(height: 8),
          const Text(
            'Book ki photo lo ya PDF upload karo —\nAI unlimited questions banayega!',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.6),
          ),
          const SizedBox(height: 32),

          _UploadCard(
            emoji: '📷',
            title: 'Camera se Photo lo',
            subtitle: 'Book ya notes ki photo kheecho',
            gradient: [
              const Color(0xFF7C3AED),
              const Color(0xFF9D4EDD)
            ],
            onTap: _pickCamera,
          ),
          const SizedBox(height: 4),
          _SmallOptionBtn(
            icon: Icons.photo_library_rounded,
            label: 'Ya Gallery se choose karo',
            onTap: _pickGallery,
            color: const Color(0xFF7C3AED),
          ),
          const SizedBox(height: 16),

          _UploadCard(
            emoji: '📄',
            title: 'PDF Upload karo',
            subtitle: 'Notes ya textbook ka PDF choose karo',
            gradient: [
              const Color(0xFF0EA5E9),
              const Color(0xFF0284C7)
            ],
            onTap: _pickPdf,
          ),
          const SizedBox(height: 24),

          // Error
          if (_errorMsg != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: Colors.red.withOpacity(0.30)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.error_outline_rounded,
                        color: Colors.redAccent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(_errorMsg!,
                          style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                              height: 1.4))),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Tips
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white.withOpacity(0.06)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('💡 Tips for Best Results',
                    style: TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                SizedBox(height: 10),
                _TipRow(
                    icon: '✅',
                    text: 'Clear aur achhi roshni mein photo lo'),
                _TipRow(
                    icon: '✅',
                    text:
                        'Pehle 10 questions generate honge — koi limit nahi!'),
                _TipRow(
                    icon: '🔄',
                    text:
                        '"Load More" se unlimited questions add karo'),
                _TipRow(
                    icon: '🗑',
                    text:
                        'Preview mein unwanted questions delete karo'),
                _TipRow(
                    icon: '▶',
                    text:
                        'Jab ready ho, Start Test → Submit/End karo'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  PROCESSING
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
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: accent),
            ),
            const SizedBox(height: 32),
            Text(_processingMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.5)),
            const SizedBox(height: 12),
            const Text(
              'AI questions bana raha hai — thoda wait karo...',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  PREVIEW
  // ══════════════════════════════════════════
  Widget _buildPreview() {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      key: const ValueKey('preview'),
      children: [
        // ── Header bar ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              // Count chip
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color:
                          const Color(0xFF10B981).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('📋',
                        style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 5),
                    Text(
                      '${_allQuestions.length} Questions',
                      style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Source label
              Text(
                _sourceIsImage
                    ? '📷 Round $_imageRound'
                    : '📄 ${_pdfPageOffset.clamp(0, _pdfTotalPages)}/$_pdfTotalPages pages',
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11),
              ),
            ],
          ),
        ),

        // ── Questions list ───────────────────────────────────────────
        Expanded(
          child: _allQuestions.isEmpty
              ? _buildEmptyPreview()
              : ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  itemCount: _allQuestions.length,
                  itemBuilder: (_, i) =>
                      _buildPreviewCard(i, accent),
                ),
        ),

        // ── Footer: Load More + Start ────────────────────────────────
        _buildPreviewFooter(accent),
      ],
    );
  }

  Widget _buildEmptyPreview() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('😶', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          const Text('Koi question nahi bacha!',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
              '"Load More" ya naya topic choose karo',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.upload_file_rounded, size: 16),
            label: const Text('Naya Topic'),
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(int i, Color accent) {
    final q        = _allQuestions[i];
    final expanded = _expandedQ.contains(i);

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded
              ? accent.withOpacity(0.32)
              : Colors.white.withOpacity(0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Question header row ──────────────────────────────────
          InkWell(
            onTap: () => setState(() {
              if (expanded) _expandedQ.remove(i);
              else _expandedQ.add(i);
            }),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Number badge
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text('${i + 1}',
                          style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Question text
                  Expanded(
                    child: Text(
                      q.question,
                      maxLines: expanded ? null : 2,
                      overflow: expanded
                          ? null
                          : TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xDEFFFFFF), // white87 equivalent
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Expand icon
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: Colors.white38,
                    size: 20,
                  ),
                  // Delete icon
                  GestureDetector(
                    onTap: () => _confirmDelete(i),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red.withOpacity(0.5),
                        size: 19,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded: options + explanation ──────────────────────
          if (expanded) ...[
            Container(
              height: 1,
              margin:
                  const EdgeInsets.symmetric(horizontal: 12),
              color: Colors.white.withOpacity(0.06),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
              child: Column(
                children: [
                  // Options
                  ...List.generate(4, (j) {
                    final isCorrect = j == q.correctIndex;
                    const labels   = ['A', 'B', 'C', 'D'];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isCorrect
                            ? const Color(0xFF10B981)
                                .withOpacity(0.10)
                            : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCorrect
                              ? const Color(0xFF10B981)
                                  .withOpacity(0.35)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(labels[j],
                              style: TextStyle(
                                  color: isCorrect
                                      ? const Color(0xFF10B981)
                                      : Colors.white38,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(q.options[j],
                                  style: TextStyle(
                                      color: isCorrect
                                          ? const Color(
                                              0xFF6EE7B7)
                                          : Colors.white54,
                                      fontSize: 12,
                                      height: 1.3))),
                          if (isCorrect)
                            const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF10B981),
                                size: 14),
                        ],
                      ),
                    );
                  }),
                  // Explanation
                  if (q.explanation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.amber.withOpacity(0.18)),
                      ),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text('💡',
                              style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(q.explanation,
                                  style: const TextStyle(
                                      color: Colors.amber,
                                      fontSize: 11,
                                      height: 1.4))),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewFooter(Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: BoxDecoration(
        color: AppTheme.bgDeep,
        border: Border(
            top: BorderSide(
                color: Colors.white.withOpacity(0.07))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Load More / All Loaded
          if (_canLoadMore || _isLoadingMore)
            GestureDetector(
              onTap: _isLoadingMore ? null : _loadMore,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 11),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.10)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isLoadingMore)
                      const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white54))
                    else
                      const Icon(
                          Icons.add_circle_outline_rounded,
                          color: Colors.white54,
                          size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _isLoadingMore
                          ? 'Questions load ho rahe hain...'
                          : _sourceIsImage
                              ? 'Aur Questions Generate Karo 🔄'
                              : 'Agle Pages Se Load Karo 📄',
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            )
          else if (_pdfAllLoaded)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Color(0xFF10B981), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Saari PDF load ho gayi! ($_pdfTotalPages pages)',
                    style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 12),
                  ),
                ],
              ),
            ),

          // Start Test button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _allQuestions.isEmpty ? null : _startTest,
              icon: const Icon(
                  Icons.play_circle_filled_rounded,
                  size: 20),
              label: Text(
                _allQuestions.isEmpty
                    ? 'Koi Question Nahi'
                    : 'Start Test  (${_allQuestions.length} Questions) →',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _allQuestions.isEmpty
                    ? Colors.grey.shade800
                    : const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: _allQuestions.isEmpty ? 0 : 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  QUIZ
  // ══════════════════════════════════════════
  Widget _buildQuiz() {
    final question = _questions[_currentIndex];
    final total    = _questions.length;
    final accent   = Theme.of(context).colorScheme.primary;
    final answered = _selectedOption != null;
    final isLastQ  = _currentIndex >= total - 1;

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
              // Progress bar
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: accent.withOpacity(0.3)),
                    ),
                    child: Text('Q ${_currentIndex + 1} / $total',
                        style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_currentIndex + 1) / total,
                        backgroundColor:
                            Colors.white.withOpacity(0.08),
                        color: accent,
                        minHeight: 6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Question card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withOpacity(0.14),
                      AppTheme.bgCard,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: accent.withOpacity(0.22)),
                  boxShadow: [
                    BoxShadow(
                        color: accent.withOpacity(0.08),
                        blurRadius: 20,
                        spreadRadius: 2)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('❓',
                          style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text('Sawaal',
                          style: TextStyle(
                              color: accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 10),
                    Text(question.question,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Options
              ...List.generate(
                  4, (i) => _buildOption(i, question, answered)),
              const SizedBox(height: 12),

              // Explanation
              if (_showExplanation && question.explanation.isNotEmpty)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.amber.withOpacity(0.22)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💡',
                          style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(question.explanation,
                              style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 13,
                                  height: 1.45))),
                    ],
                  ),
                ),

              // Navigation
              if (answered) ...[
                if (!isLastQ)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(16)),
                        elevation: 4,
                      ),
                      child: const Text('Agla Sawaal  →',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _submitTest,
                      icon: const Icon(
                          Icons.check_circle_rounded,
                          size: 20),
                      label: const Text('Submit Test  🏆',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(16)),
                        elevation: 6,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption(int i, StudyQuestion q, bool answered) {
    final accent     = Theme.of(context).colorScheme.primary;
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

    const labels = ['A', 'B', 'C', 'D'];
    IconData? trailingIcon;
    Color?    trailingColor;
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
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
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
                  child: Text(labels[i],
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: answered && isCorrect
                              ? const Color(0xFF10B981)
                              : answered && isSelected && !isCorrect
                                  ? Colors.redAccent
                                  : accent))),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(q.options[i],
                    style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight:
                            (isSelected || (answered && isCorrect))
                                ? FontWeight.w600
                                : FontWeight.w400,
                        height: 1.35))),
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
  //  RESULT
  // ══════════════════════════════════════════
  Widget _buildResult() {
    final accent   = Theme.of(context).colorScheme.primary;
    final answered = _currentIndex + 1;
    final pct      = answered == 0 ? 0 : (_score / answered * 100).round();
    final stars    = (pct / 20).ceil().clamp(0, 5);

    final (emoji, title, sub) = switch (pct) {
      >= 80 => ('🏆', 'Zabardast!',    'Tu toh champion hai bhai!'),
      >= 60 => ('⭐', 'Bahut Achha!',  'Aur thodi mehnat aur perfect hoga'),
      >= 40 => ('💪', 'Theek Hai!',    'Dobara padh ke retry karo'),
      _     => ('📖', 'Mehnat Karo!',  'Content phir se padho aur try karo'),
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
              Text(emoji, style: const TextStyle(fontSize: 80)),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontFamily: 'Poppins')),
              const SizedBox(height: 6),
              Text(sub,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 15)),
              const SizedBox(height: 36),

              // Score circle
              Container(
                width: 180, height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    scoreColor.withOpacity(0.20),
                    AppTheme.bgCard
                  ]),
                  border: Border.all(
                      color: scoreColor.withOpacity(0.45), width: 3),
                  boxShadow: [
                    BoxShadow(
                        color: scoreColor.withOpacity(0.20),
                        blurRadius: 30)
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$_score',
                        style: TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.w900,
                            color: scoreColor,
                            fontFamily: 'Poppins',
                            height: 1.1)),
                    Text('of $answered correct',
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Stars
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Icon(
                      i < stars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: i < stars
                          ? Colors.amber
                          : Colors.white.withOpacity(0.18),
                      size: 38,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('$pct% Score',
                  style: TextStyle(
                      color: scoreColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
              const SizedBox(height: 36),

              _ReviewSummary(
                  questions:
                      _questions.sublist(0, _currentIndex + 1)),
              const SizedBox(height: 28),

              // ── Action buttons ──────────────────────────────────
              // Row 1: Retest + Edit Preview
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _replay,
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      label: const Text('Retest 🔁'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _backToPreview,
                      icon: const Icon(Icons.list_alt_rounded, size: 18),
                      label: const Text('Edit Preview'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(
                            color: Colors.white.withOpacity(0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Row 2: New Topic
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _reset,
                  icon:
                      const Icon(Icons.upload_file_rounded, size: 18),
                  label:
                      const Text('Naya Topic Upload Karo 📤'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: BorderSide(
                        color: Colors.white.withOpacity(0.10)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
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
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [gradient.first.withOpacity(0.18), AppTheme.bgCard],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: gradient.first.withOpacity(0.40)),
          boxShadow: [
            BoxShadow(
                color: gradient.first.withOpacity(0.10),
                blurRadius: 20,
                spreadRadius: 1)
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    colors: gradient
                        .map((c) => c.withOpacity(0.5))
                        .toList()),
              ),
              child: Center(
                  child: Text(emoji,
                      style: const TextStyle(fontSize: 28))),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins')),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: gradient.first.withOpacity(0.7), size: 24),
          ],
        ),
      ),
    );
  }
}

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
        label: Text(label,
            style:
                TextStyle(color: color.withOpacity(0.7), fontSize: 12)),
        style: TextButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
      ),
    );
  }
}

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
              child: Text(text,
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.4))),
        ],
      ),
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  final List<StudyQuestion> questions;
  const _ReviewSummary({required this.questions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📋 Quick Review',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const SizedBox(height: 12),
          ...List.generate(questions.length, (i) {
            final q = questions[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Q${i + 1}: ${q.question}',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                height: 1.3)),
                        const SizedBox(height: 2),
                        Text('✓ ${q.options[q.correctIndex]}',
                            style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
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
