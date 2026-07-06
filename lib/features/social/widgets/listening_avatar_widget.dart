import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Animated avatar that pulses/dances to music.
/// Uses Timer.periodic for bars (NOT addListener) to avoid 60fps setState drain.
class ListeningAvatar extends StatefulWidget {
  final String name;
  final Color  color;
  final double size;
  final bool   isPlaying;
  final bool   showBars;
  final VoidCallback? onTap;

  const ListeningAvatar({
    super.key,
    required this.name,
    required this.color,
    this.size      = 52.0,
    this.isPlaying = false,
    this.showBars  = true,
    this.onTap,
  });

  @override
  State<ListeningAvatar> createState() => _ListeningAvatarState();
}

class _ListeningAvatarState extends State<ListeningAvatar>
    with TickerProviderStateMixin {

  // Pulse + bounce use AnimationBuilder (no setState per frame)
  late AnimationController _pulseCtrl;
  late Animation<double>   _scaleAnim;
  late AnimationController _bounceCtrl;
  late Animation<double>   _translateAnim;

  // Bars use Timer.periodic @ 400ms → 2.5 setState/sec instead of 60/sec
  Timer?        _barTimer;
  final _rng  = Random();
  List<double>  _barH = const [0.4, 0.6, 0.5, 0.7];

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleAnim = Tween<double>(begin: 0.95, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _bounceCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 650),
    );
    _translateAnim = Tween<double>(begin: 0, end: -5).animate(
      CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeInOut),
    );

    if (widget.isPlaying) _startAnimations();
  }

  @override
  void didUpdateWidget(ListeningAvatar old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !old.isPlaying)      _startAnimations();
    else if (!widget.isPlaying && old.isPlaying) _stopAnimations();
  }

  void _startAnimations() {
    _pulseCtrl.repeat(reverse: true);
    _bounceCtrl.repeat(reverse: true);
    _barTimer?.cancel();
    _barTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) {
        setState(() {
          _barH = List.generate(4, (_) => 0.2 + _rng.nextDouble() * 0.8);
        });
      }
    });
  }

  void _stopAnimations() {
    _pulseCtrl.stop();
    _bounceCtrl.stop();
    _barTimer?.cancel();
    _barTimer = null;
    _pulseCtrl.animateTo(0);
    _bounceCtrl.animateTo(0);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _bounceCtrl.dispose();
    _barTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.name.isNotEmpty
        ? widget.name.trim()[0].toUpperCase()
        : '?';

    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_scaleAnim, _translateAnim]),
            builder: (_, __) => Transform.translate(
              offset: Offset(0, widget.isPlaying ? _translateAnim.value : 0),
              child: Transform.scale(
                scale: widget.isPlaying ? _scaleAnim.value : 1.0,
                child: _AvatarCircle(
                  initial:   initial,
                  color:     widget.color,
                  size:      widget.size,
                  isPlaying: widget.isPlaying,
                ),
              ),
            ),
          ),
          if (widget.showBars && widget.isPlaying) ...[
            const SizedBox(height: 6),
            _MiniWaveBars(bars: _barH, color: widget.color),
          ],
        ],
      ),
    );
  }
}

// ── Internal widgets ──────────────────────────────────────────

class _AvatarCircle extends StatelessWidget {
  final String initial;
  final Color  color;
  final double size;
  final bool   isPlaying;
  const _AvatarCircle({
    required this.initial, required this.color,
    required this.size,    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [color, color.withOpacity(0.55)],
        ),
        boxShadow: isPlaying
            ? [BoxShadow(color: color.withOpacity(0.45), blurRadius: 18, spreadRadius: 2)]
            : [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6)],
        border: Border.all(
          color: isPlaying ? color.withOpacity(0.7) : Colors.white12,
          width: isPlaying ? 2 : 1,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            initial,
            style: TextStyle(
              color: Colors.white, fontSize: size * 0.38,
              fontWeight: FontWeight.w800, fontFamily: 'Poppins',
            ),
          ),
          if (isPlaying)
            Positioned(
              right: 0, bottom: 0,
              child: Container(
                width: size * 0.30, height: size * 0.30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: AppTheme.bgCard,
                  border: Border.all(color: color.withOpacity(0.5), width: 1),
                ),
                child: Icon(Icons.music_note_rounded,
                    size: size * 0.16, color: color),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniWaveBars extends StatelessWidget {
  final List<double> bars;
  final Color        color;
  const _MiniWaveBars({required this.bars, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 10,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: bars.map((h) => AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve:    Curves.easeInOut,
          width:    3,
          height:   (h * 10).clamp(2.0, 10.0),
          margin:   const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color:        color.withOpacity(0.85),
          ),
        )).toList(),
      ),
    );
  }
}

// ── Color helper ──────────────────────────────────────────────

Color avatarColorFor(String text) {
  const colors = [
    Color(0xFF7C3AED), Color(0xFF06B6D4), Color(0xFFEC4899),
    Color(0xFF22C55E), Color(0xFFF59E0B), Color(0xFF3B82F6),
    Color(0xFFEF4444), Color(0xFF8B5CF6), Color(0xFF10B981),
    Color(0xFFF97316),
  ];
  final hash = text.codeUnits.fold(0, (a, b) => a + b);
  return colors[hash % colors.length];
}
