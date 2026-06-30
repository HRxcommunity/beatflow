// lib/features/update/update_dialog.dart
//
// BeatFlow Update Dialog
// ──────────────────────
// App ke purple/cyan theme se match karta hua update dialog.
// Features:
//   • Current → New version chips
//   • Scrollable changelog
//   • Direct APK download via url_launcher
//   • isRequired = true  → "Maybe Later" button hide ho jata hai

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/update_service.dart';

// ─────────────────────────────────────────────────────────────────────────────

/// Dialog dikhata hai — kisi bhi BuildContext se call karo.
///
/// ```dart
/// final info = await UpdateService.instance.checkForUpdate();
/// if (info != null && info.hasUpdate && context.mounted) {
///   showUpdateDialog(context, info);
/// }
/// ```
void showUpdateDialog(BuildContext context, UpdateInfo info) {
  showDialog(
    context: context,
    barrierDismissible: !info.isRequired,
    builder: (_) => _UpdateDialog(info: info),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      // Back button se dismiss nahi — agar required update hai
      canPop: !widget.info.isRequired,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E1B4B), Color(0xFF0F0A2A)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: cs.primary.withOpacity(0.45),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withOpacity(0.28),
                blurRadius: 48,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(cs),
              _buildChangelog(),
              _buildButtons(cs),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary.withOpacity(0.22),
            const Color(0xFF00D4FF).withOpacity(0.08),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.primary.withOpacity(0.3)),
            ),
            child: Icon(
              Icons.system_update_alt_rounded,
              color: cs.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          // Title + version chips
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.info.isRequired
                      ? 'Update Required 🚨'
                      : 'Update Available 🎉',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _VersionChip(
                      label: 'v${widget.info.currentVersion}',
                      bg: Colors.white.withOpacity(0.12),
                      fg: Colors.white70,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: cs.primary.withOpacity(0.7),
                        size: 14,
                      ),
                    ),
                    _VersionChip(
                      label: 'v${widget.info.latestVersion}',
                      bg: cs.primary,
                      fg: Colors.white,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Changelog ────────────────────────────────────────────────────────────

  Widget _buildChangelog() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "WHAT'S NEW",
            style: TextStyle(
              color: Colors.white38,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: SingleChildScrollView(
              child: Text(
                widget.info.changelog,
                style: const TextStyle(
                  color: Colors.white70,
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  height: 1.65,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Buttons ──────────────────────────────────────────────────────────────

  Widget _buildButtons(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Download button
          FilledButton.icon(
            onPressed: _downloading ? null : _onDownload,
            icon: _downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded, size: 20),
            label: Text(
              _downloading ? 'Opening...' : 'Download Update',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              disabledBackgroundColor: cs.primary.withOpacity(0.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),

          // "Maybe Later" — only if not required update
          if (!widget.info.isRequired) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Maybe Later',
                style: TextStyle(
                  color: Colors.white38,
                  fontFamily: 'Poppins',
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _onDownload() async {
    setState(() => _downloading = true);
    try {
      final uri = Uri.tryParse(widget.info.downloadUrl);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      // Required update: dialog khuli rehti hai — user ko update karna padega
      if (mounted && !widget.info.isRequired) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[UpdateDialog] launch failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open download link')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _VersionChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _VersionChip({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
        ),
      ),
    );
  }
}
