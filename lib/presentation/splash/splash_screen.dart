import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/router/app_router.dart';
import '../songs/library_bloc.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // ── Controllers ──
  late AnimationController _entryCtrl;   // logo + text fade-in
  late AnimationController _waveCtrl;    // waveform bars loop
  late AnimationController _noteCtrl;    // floating music notes
  late AnimationController _progressCtrl;// loading bar fill
  late AnimationController _pulseCtrl;   // subtle image scale pulse

  // ── Entry animations ──
  late Animation<double> _logoFade;
  late Animation<Offset> _logoSlide;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;
  late Animation<double> _bottomFade;

  // ── Pulse ──
  late Animation<double> _pulseScale;

  String _statusText = 'Loading...';
  double _progressValue = 0.0;

  // ── Palette (matching image) ──
  static const Color _cyan   = Color(0xFF00D4FF);
  static const Color _blue   = Color(0xFF0A84FF);
  static const Color _purple = Color(0xFF7B5FE6);
  static const Color _white  = Color(0xFFFFFFFF);
  static const Color _grey   = Color(0xFFB0C4DE);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSequence());
  }

  void _setupAnimations() {
    // Entry — one-shot
    _entryCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000),
    );

    // Waveform — infinite loop
    _waveCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // Notes — infinite loop
    _noteCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200),
    )..repeat();

    // Progress — controlled manually
    _progressCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3000),
    );

    // Pulse — slow heartbeat on image
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    // ── Entry animations ──
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );
    _logoSlide = Tween<Offset>(begin: const Offset(0, -0.08), end: Offset.zero).animate(
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic)),
    );
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.35, 0.80, curve: Curves.easeIn)),
    );
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic)),
    );
    _bottomFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.55, 1.0, curve: Curves.easeIn)),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.025).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  Future<void> _startSequence() async {
    _entryCtrl.forward();
    _progressCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    _setStatus('Requesting permissions...');
    final granted = await _requestAllPermissions();
    if (!mounted) return;

    if (!granted) {
      _setStatus('Permission needed for music scanning');
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      context.go(AppRouter.home);
      return;
    }

    _setStatus('Loading music library...');
    if (mounted) context.read<LibraryBloc>().add(LibraryLoad());

    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    _setStatus('');
    context.go(AppRouter.home);
  }

  Future<bool> _requestAllPermissions() async {
    final statuses = await [
      Permission.audio,
      Permission.videos,   // Android 13+: READ_MEDIA_VIDEO — MP4 files ke liye
      Permission.storage,
    ].request();
    return (statuses[Permission.audio]?.isGranted  ?? false) ||
           (statuses[Permission.videos]?.isGranted ?? false) ||
           (statuses[Permission.storage]?.isGranted ?? false);
  }

  void _setStatus(String text) {
    if (mounted) setState(() => _statusText = text);
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _waveCtrl.dispose();
    _noteCtrl.dispose();
    _progressCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [

          // ── 1. BACKGROUND IMAGE — subtle scale pulse ──
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Transform.scale(
              scale: _pulseScale.value,
              child: Image.asset(
                'assets/images/splash_bg.png',
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),

          // ── 2. DARK GRADIENT OVERLAY (top + bottom) ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.22, 0.55, 0.78, 1.0],
                colors: [
                  Color(0xDD000000),  // top dark
                  Color(0x88000000),  // semi clear
                  Color(0x11000000),  // almost clear — image shows
                  Color(0x99000000),  // coming back
                  Color(0xFF000000),  // solid bottom
                ],
              ),
            ),
          ),

          // ── 3. ANIMATED WAVEFORMS (left + right sides) ──
          AnimatedBuilder(
            animation: _waveCtrl,
            builder: (_, __) => Stack(
              children: [
                // Left waveform
                Positioned(
                  left: 0,
                  top: size.height * 0.25,
                  child: _WaveformBars(
                    t: _waveCtrl.value,
                    barCount: 12,
                    barWidth: 3.0,
                    maxHeight: size.height * 0.14,
                    color: _cyan.withOpacity(0.75),
                    reversed: false,
                  ),
                ),
                // Right waveform
                Positioned(
                  right: 0,
                  top: size.height * 0.42,
                  child: _WaveformBars(
                    t: _waveCtrl.value,
                    barCount: 10,
                    barWidth: 3.0,
                    maxHeight: size.height * 0.10,
                    color: _cyan.withOpacity(0.65),
                    reversed: true,
                  ),
                ),
              ],
            ),
          ),

          // ── 4. FLOATING MUSIC NOTES ──
          AnimatedBuilder(
            animation: _noteCtrl,
            builder: (_, __) => Stack(
              children: [
                _FloatingNote(
                  t: _noteCtrl.value, phase: 0.0, amp: 18,
                  left: size.width * 0.10, top: size.height * 0.16,
                  color: _purple, size: 18,
                ),
                _FloatingNote(
                  t: _noteCtrl.value, phase: 0.28, amp: 14,
                  left: size.width * 0.76, top: size.height * 0.22,
                  color: _blue, size: 16,
                ),
                _FloatingNote(
                  t: _noteCtrl.value, phase: 0.55, amp: 20,
                  left: size.width * 0.08, top: size.height * 0.45,
                  color: _purple, size: 15,
                ),
                _FloatingNote(
                  t: _noteCtrl.value, phase: 0.72, amp: 16,
                  left: size.width * 0.82, top: size.height * 0.38,
                  color: _cyan, size: 14,
                ),
              ],
            ),
          ),

          // ── 5. TOP: LOGO + BRANDING ──
          SafeArea(
            child: FadeTransition(
              opacity: _logoFade,
              child: SlideTransition(
                position: _logoSlide,
                child: Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // "B" logo icon
                      _buildLogoIcon(),
                      const SizedBox(height: 10),
                      // BeatFlow text
                      SlideTransition(
                        position: _textSlide,
                        child: FadeTransition(
                          opacity: _textFade,
                          child: Column(
                            children: [
                              RichText(
                                text: const TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Beat',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 38,
                                        fontWeight: FontWeight.w700,
                                        color: _white,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'Flow',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 38,
                                        fontWeight: FontWeight.w700,
                                        color: _cyan,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 3),
                              RichText(
                                text: const TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'by ',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        color: _grey,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'HRx',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _cyan,
                                      ),
                                    ),
                                    TextSpan(
                                      text: ' Community',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        color: _grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── 6. MIDDLE TAGLINE (italic, cursive style) ──
          Positioned(
            left: 0, right: 0,
            bottom: size.height * 0.285,
            child: FadeTransition(
              opacity: _textFade,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: const TextSpan(
                        children: [
                          TextSpan(
                            text: 'Feel the ',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w300,
                              color: _white,
                            ),
                          ),
                          TextSpan(
                            text: 'rhythm.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w500,
                              color: _cyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    RichText(
                      text: const TextSpan(
                        children: [
                          TextSpan(
                            text: 'Live the ',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w300,
                              color: _white,
                            ),
                          ),
                          TextSpan(
                            text: 'moment.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w500,
                              color: _cyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 7. BOTTOM SECTION ──
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: FadeTransition(
              opacity: _bottomFade,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // Animated progress bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: AnimatedBuilder(
                      animation: _progressCtrl,
                      builder: (_, __) => _buildProgressBar(_progressCtrl.value),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_statusText.isNotEmpty)
                    Text(
                      _statusText,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: _grey,
                        letterSpacing: 0.3,
                      ),
                    ),
                  const SizedBox(height: 20),

                  // Feature icons row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildFeatureIcon(Icons.music_note_rounded, 'High Quality', 'Sound'),
                        _buildDivider(),
                        _buildFeatureIcon(Icons.graphic_eq_rounded, 'Ad-Free', 'Experience'),
                        _buildDivider(),
                        _buildFeatureIcon(Icons.people_alt_rounded, 'Exclusive', 'Community'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),

        ],
      ),
    );
  }

  // ── Logo icon: waveform + B ──
  Widget _buildLogoIcon() {
    return AnimatedBuilder(
      animation: _waveCtrl,
      builder: (_, __) {
        return Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Glow ring
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: _blue.withOpacity(0.4), blurRadius: 28, spreadRadius: 4),
                  ],
                ),
              ),
              // B + waveform combined icon using CustomPaint
              CustomPaint(
                size: const Size(72, 72),
                painter: _LogoIconPainter(_waveCtrl.value),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgressBar(double value) {
    return Container(
      height: 5,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: const LinearGradient(colors: [_blue, _cyan]),
            boxShadow: [BoxShadow(color: _cyan.withOpacity(0.7), blurRadius: 8)],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureIcon(IconData icon, String line1, String line2) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withOpacity(0.08),
            border: Border.all(color: _blue.withOpacity(0.35), width: 1),
          ),
          child: Icon(icon, color: _cyan, size: 24),
        ),
        const SizedBox(height: 6),
        Text(line1,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
            fontWeight: FontWeight.w600, color: _white)),
        Text(line2,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
            color: _grey.withOpacity(0.75))),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1, height: 50,
      color: Colors.white.withOpacity(0.12),
    );
  }
}

// ══════════════════════════════════════════════════
//  CUSTOM PAINTERS
// ══════════════════════════════════════════════════

/// Logo: waveform bars + B letter
class _LogoIconPainter extends CustomPainter {
  final double t;
  _LogoIconPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Background circle
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFF0D2E6E), const Color(0xFF030D1E)],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: cx));
    canvas.drawCircle(Offset(cx, cy), cx, bgPaint);

    // Border ring
    canvas.drawCircle(
      Offset(cx, cy), cx - 1,
      Paint()
        ..color = const Color(0xFF0A84FF).withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Waveform bars inside
    const barCount = 6;
    final totalW = size.width * 0.58;
    final barW = totalW / barCount * 0.55;
    final gap  = totalW / barCount * 0.45;
    final startX = cx - totalW / 2;
    final baseY  = cy + size.height * 0.18;
    final maxH   = size.height * 0.44;

    for (int i = 0; i < barCount; i++) {
      final phase = (i / barCount + t) % 1.0;
      final h = maxH * (0.3 + 0.7 * (0.5 + 0.5 * sin(phase * pi * 2)));
      final x = startX + i * (barW + gap);
      final barGrad = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFF00E5FF), const Color(0xFF0A84FF)],
      ).createShader(Rect.fromLTWH(x, baseY - h, barW, h));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, baseY - h, barW, h),
          const Radius.circular(2),
        ),
        Paint()..shader = barGrad,
      );
    }

    // "B" letter (large, semi-transparent right overlay)
    final tp = TextPainter(
      text: TextSpan(
        text: 'B',
        style: TextStyle(
          fontSize: 46,
          fontWeight: FontWeight.w900,
          foreground: Paint()
            ..shader = LinearGradient(
              colors: [
                const Color(0xFF0A84FF).withOpacity(0.55),
                const Color(0xFF00D4FF).withOpacity(0.30),
              ],
            ).createShader(Rect.fromLTWH(cx, 0, size.width, size.height)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width * 0.35, cy - tp.height * 0.48));
  }

  @override
  bool shouldRepaint(_LogoIconPainter old) => old.t != t;
}

/// Waveform side bars widget
class _WaveformBars extends StatelessWidget {
  final double t;
  final int barCount;
  final double barWidth;
  final double maxHeight;
  final Color color;
  final bool reversed;

  const _WaveformBars({
    required this.t, required this.barCount, required this.barWidth,
    required this.maxHeight, required this.color, required this.reversed,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(barCount * (barWidth + 2.5), maxHeight * 1.2),
      painter: _WaveformBarsPainter(t, barCount, barWidth, maxHeight, color, reversed),
    );
  }
}

class _WaveformBarsPainter extends CustomPainter {
  final double t;
  final int barCount;
  final double barW;
  final double maxH;
  final Color color;
  final bool reversed;

  _WaveformBarsPainter(this.t, this.barCount, this.barW, this.maxH, this.color, this.reversed);

  @override
  void paint(Canvas canvas, Size size) {
    final spacing = barW + 2.5;
    for (int i = 0; i < barCount; i++) {
      final idx = reversed ? (barCount - 1 - i) : i;
      final phase = (idx / barCount + t * 0.9) % 1.0;
      final h = maxH * (0.25 + 0.75 * (0.5 + 0.5 * sin(phase * pi * 2)));
      final x = i * spacing;
      final y = size.height - h;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, h),
          const Radius.circular(1.5),
        ),
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformBarsPainter old) => old.t != t;
}

/// Floating music note
class _FloatingNote extends StatelessWidget {
  final double t;
  final double phase;
  final double amp;
  final double left;
  final double top;
  final Color color;
  final double size;

  const _FloatingNote({
    required this.t, required this.phase, required this.amp,
    required this.left, required this.top, required this.color, required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (t + phase) % 1.0;
    final dy = -amp * sin(progress * pi * 2);
    final opacity = (0.20 + 0.55 * (0.5 + 0.5 * sin(progress * pi * 2))).clamp(0.0, 1.0);

    return Positioned(
      left: left,
      top: top + dy,
      child: Opacity(
        opacity: opacity,
        child: Icon(Icons.music_note_rounded, color: color, size: size),
      ),
    );
  }
}
