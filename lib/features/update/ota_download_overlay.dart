// lib/features/update/ota_download_overlay.dart
//
// Floating download bubble (bottom-right) + progress panel trigger.
// Visible only when an OTA download is active/paused/complete/failed.
// Integrates into main.dart's _TogetherNotificationOverlay Stack.

import 'dart:async';
import 'package:flutter/material.dart';
import 'ota_download_manager.dart';
import 'ota_progress_panel.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  OtaDownloadOverlay — wraps child, adds floating bubble above it
// ─────────────────────────────────────────────────────────────────────────────

class OtaDownloadOverlay extends StatelessWidget {
  final Widget child;
  const OtaDownloadOverlay({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        const _OtaFloatingBubble(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Floating bubble (Positioned, bottom-right)
// ─────────────────────────────────────────────────────────────────────────────

class _OtaFloatingBubble extends StatefulWidget {
  const _OtaFloatingBubble();

  @override
  State<_OtaFloatingBubble> createState() => _OtaFloatingBubbleState();
}

class _OtaFloatingBubbleState extends State<_OtaFloatingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double>   _scale;
  late StreamSubscription<OtaDownloadStatus> _sub;

  OtaDownloadStatus _status = OtaDownloadStatus.idle;

  @override
  void initState() {
    super.initState();

    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scale = CurvedAnimation(parent: _anim, curve: Curves.elasticOut);

    _sub = OtaDownloadManager.instance.stream.listen((s) {
      if (!mounted) return;
      final wasActive = _status.isActive;
      setState(() => _status = s);

      if (s.isActive && !wasActive) _anim.forward();
      if (!s.isActive && wasActive) _anim.reverse();
    });

    // Restore state if download was already running before widget mounted
    final current = OtaDownloadManager.instance.currentStatus;
    if (current.isActive) {
      _status = current;
      _anim.value = 1.0;
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _openPanel() {
    // FIX: When download is completed, "Tap to Install" should install directly.
    // Old behaviour = open bottom-sheet FIRST, then user must tap "Install Update"
    // again inside the sheet — extremely confusing, user thinks nothing happened.
    if (_status.isCompleted) {
      OtaDownloadManager.instance.installApk();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const OtaProgressPanel(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_status.isActive) return const SizedBox.shrink();

    // Position: bottom-right, above mini-player (~70dp) + safe area
    // 80dp gives ~10dp clearance above the mini-player bar.
    final bottom = 80.0 + MediaQuery.of(context).padding.bottom;

    return Positioned(
      bottom: bottom,
      right: 12,
      child: ScaleTransition(
        scale: _scale,
        child: GestureDetector(
          onTap: _openPanel,
          child: _BubbleContent(status: _status),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bubble visual (pure UI, no state)
// ─────────────────────────────────────────────────────────────────────────────

class _BubbleContent extends StatelessWidget {
  final OtaDownloadStatus status;
  const _BubbleContent({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: status.isCompleted
              ? [const Color(0xFF059669), const Color(0xFF10B981)]  // green
              : status.isFailed
                  ? [const Color(0xFFDC2626), const Color(0xFFEF4444)]  // red
                  : status.isPaused
                      ? [const Color(0xFFF59E0B), const Color(0xFFFBBF24)]  // amber
                      : [const Color(0xFF7C3AED), const Color(0xFF06B6D4)], // purple→cyan
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: (status.isCompleted
                    ? const Color(0xFF059669)
                    : status.isFailed
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF7C3AED))
                .withOpacity(0.45),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _bubbleIcon(),
          const SizedBox(width: 8),
          _bubbleLabel(),
        ],
      ),
    );
  }

  Widget _bubbleIcon() {
    if (status.isCompleted) {
      return const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20);
    }
    if (status.isFailed) {
      return const Icon(Icons.error_rounded, color: Colors.white, size: 20);
    }
    if (status.isPaused) {
      return const Icon(Icons.pause_circle_rounded, color: Colors.white, size: 20);
    }
    // Downloading — circular progress
    return SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
        value: status.progress > 0 ? status.progress : null,
        strokeWidth: 2.5,
        backgroundColor: Colors.white30,
        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }

  Widget _bubbleLabel() {
    if (status.isCompleted) {
      return const Text(
        'Tap to Install',
        style: TextStyle(
          color: Colors.white,
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      );
    }
    if (status.isFailed) {
      return const Text(
        'Update Failed',
        style: TextStyle(
          color: Colors.white,
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      );
    }
    if (status.isPaused) {
      return Text(
        'Paused • ${(status.progress * 100).round()}%',
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      );
    }
    // Downloading
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${(status.progress * 100).round()}%',
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        if (status.speedBps > 0)
          Text(
            OtaDownloadManager.fmtSpeed(status.speedBps),
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'Poppins',
              fontSize: 10,
            ),
          ),
      ],
    );
  }
}
