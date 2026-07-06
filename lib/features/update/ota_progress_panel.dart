// lib/features/update/ota_progress_panel.dart
//
// Full-screen OTA progress bottom sheet.
// Shows: progress bar, %, speed, size, remaining time.
// Actions: Pause / Resume / Cancel / Install.

import 'dart:async';
import 'package:flutter/material.dart';
import 'ota_download_manager.dart';

class OtaProgressPanel extends StatefulWidget {
  const OtaProgressPanel({super.key});

  @override
  State<OtaProgressPanel> createState() => _OtaProgressPanelState();
}

class _OtaProgressPanelState extends State<OtaProgressPanel> {
  late StreamSubscription<OtaDownloadStatus> _sub;
  OtaDownloadStatus _status = OtaDownloadManager.instance.currentStatus;

  @override
  void initState() {
    super.initState();
    _sub = OtaDownloadManager.instance.stream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF0F0A2A)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildHeader(cs),
          ),

          const SizedBox(height: 24),

          // Progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildProgressBar(cs),
          ),

          const SizedBox(height: 16),

          // Stats row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildStatsRow(),
          ),

          const SizedBox(height: 28),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildActions(cs),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(ColorScheme cs) {
    IconData icon;
    String title;
    String subtitle;

    if (_status.isCompleted) {
      icon     = Icons.check_circle_rounded;
      title    = 'Update Ready!';
      subtitle = 'BeatFlow v${_status.version} downloaded successfully';
    } else if (_status.isFailed) {
      icon     = Icons.error_rounded;
      title    = 'Download Failed';
      subtitle = _status.error ?? 'Something went wrong. Retry karo.';
    } else if (_status.isPaused) {
      icon     = Icons.pause_circle_filled_rounded;
      title    = 'Download Paused';
      // FIX (Note E): was incorrectly using `status` instead of `_status`
      subtitle = 'BeatFlow v${_status.version} • ${(_status.progress * 100).round()}% complete';
    } else {
      icon     = Icons.system_update_alt_rounded;
      title    = 'Downloading Update';
      subtitle = 'BeatFlow v${_status.version}';
    }

    final iconColor = _status.isCompleted
        ? const Color(0xFF10B981)
        : _status.isFailed
            ? const Color(0xFFEF4444)
            : _status.isPaused
                ? const Color(0xFFFBBF24)
                : cs.primary;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: iconColor.withOpacity(0.3)),
          ),
          child: Icon(icon, color: iconColor, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white60,
                  fontFamily: 'Poppins',
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Progress bar ─────────────────────────────────────────────────────────

  Widget _buildProgressBar(ColorScheme cs) {
    final pct = _status.progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Track
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct > 0 ? pct : null,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(
              _status.isCompleted
                  ? const Color(0xFF10B981)
                  : _status.isFailed
                      ? const Color(0xFFEF4444)
                      : cs.primary,
            ),
            minHeight: 10,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(pct * 100).round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (_status.totalBytes > 0)
              Text(
                '${OtaDownloadManager.fmtSize(_status.downloadedBytes)} / '
                '${OtaDownloadManager.fmtSize(_status.totalBytes)}',
                style: const TextStyle(
                  color: Colors.white60,
                  fontFamily: 'Poppins',
                  fontSize: 11.5,
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── Stats row ────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    if (!_status.isDownloading && !_status.isPaused) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (_status.speedBps > 0 && _status.isDownloading)
          _StatChip(
            icon: Icons.speed_rounded,
            label: OtaDownloadManager.fmtSpeed(_status.speedBps),
          ),
        if (_status.remaining != null && _status.isDownloading) ...[
          const SizedBox(width: 8),
          _StatChip(
            icon: Icons.timer_rounded,
            label: OtaDownloadManager.fmtRemaining(_status.remaining!),
          ),
        ],
        if (_status.isPaused)
          const _StatChip(
            icon: Icons.pause_rounded,
            label: 'Paused — tap Resume',
          ),
      ],
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────────

  Widget _buildActions(ColorScheme cs) {
    // Completed state: Install button
    if (_status.isCompleted) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await OtaDownloadManager.instance.installApk();
            },
            icon: const Icon(Icons.install_mobile_rounded, size: 20),
            label: const Text(
              'Install Update',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      );
    }

    // Failed state: Retry + Dismiss
    if (_status.isFailed) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              // Note A: use public activeUrl getter instead of private _activeUrl
              onPressed: () {
                final url = OtaDownloadManager.instance.activeUrl;
                if (url != null && url.isNotEmpty && _status.version.isNotEmpty) {
                  OtaDownloadManager.instance.startDownload(
                    url:     url,
                    version: _status.version,
                  );
                }
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'Retry',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: () {
              OtaDownloadManager.instance.cancel();
              Navigator.of(context).pop();
            },
            child: const Text(
              'Dismiss',
              style: TextStyle(
                color: Colors.white38,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ],
      );
    }

    // Downloading / Paused state: Pause or Resume + Cancel
    return Row(
      children: [
        // Pause / Resume
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              if (_status.isDownloading) {
                OtaDownloadManager.instance.pause();
              } else if (_status.isPaused) {
                OtaDownloadManager.instance.resume();
              }
            },
            icon: Icon(
              _status.isDownloading
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 20,
            ),
            label: Text(
              _status.isDownloading ? 'Pause' : 'Resume',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _status.isDownloading
                  ? const Color(0xFFF59E0B)
                  : cs.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Cancel
        OutlinedButton.icon(
          onPressed: () {
            OtaDownloadManager.instance.cancel();
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white54),
          label: const Text(
            'Cancel',
            style: TextStyle(color: Colors.white54, fontFamily: 'Poppins'),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stat chip widget
// ─────────────────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white54),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
