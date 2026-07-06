import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_theme.dart';

/// Bottom sheet that shows the QR code of a session code.
/// Host uses this to share — guest scans and enters code manually.
class QrJoinSheet extends StatelessWidget {
  final String sessionCode;
  final String songTitle;
  final String ownerName;

  const QrJoinSheet({
    super.key,
    required this.sessionCode,
    required this.songTitle,
    required this.ownerName,
  });

  static Future<void> show(
    BuildContext context, {
    required String sessionCode,
    required String songTitle,
    required String ownerName,
  }) {
    return showModalBottomSheet(
      context:          context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QrJoinSheet(
        sessionCode: sessionCode,
        songTitle:   songTitle,
        ownerName:   ownerName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        AppTheme.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color:        Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          const Text(
            '📱 Scan to Join',
            style: TextStyle(
              color:      Colors.white,
              fontSize:   20,
              fontWeight: FontWeight.w700,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$ownerName • $songTitle',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),

          // QR Code
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color:       AppTheme.accentViolet.withOpacity(0.25),
                  blurRadius:  24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: QrImageView(
              data:           'beatflow://join/$sessionCode',
              version:        QrVersions.auto,
              size:           220,
              backgroundColor: Colors.white,
              eyeStyle:       QrEyeStyle(
                eyeShape:  QrEyeShape.square,
                color:     AppTheme.bgDeep,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color:           AppTheme.bgDeep,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Code display
          Text(
            'Room Code',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: sessionCode));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Code copied! 📋'),
                  backgroundColor: AppTheme.accentViolet,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    AppTheme.accentViolet.withOpacity(0.2),
                    AppTheme.accentCyan.withOpacity(0.2),
                  ],
                ),
                border: Border.all(
                  color: AppTheme.accentViolet.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sessionCode,
                    style: TextStyle(
                      color:         AppTheme.accentViolet,
                      fontSize:      28,
                      fontWeight:    FontWeight.w900,
                      fontFamily:    'Poppins',
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.copy_rounded,
                      size: 18, color: AppTheme.accentViolet),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Hint
          Text(
            'Share this QR or code with friends.\nThey can scan it or enter the code in BeatFlow Together.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color:    AppTheme.textSecondary,
              fontSize: 12,
              height:   1.5,
            ),
          ),
        ],
      ),
    );
  }
}
