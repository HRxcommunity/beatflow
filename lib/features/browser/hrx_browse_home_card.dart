// ╔══════════════════════════════════════════════════════════════╗
// ║  HRxBrowse Home Card — Quick access from BeatFlow Home      ║
// ╚══════════════════════════════════════════════════════════════╝

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

class HRxBrowseHomeCard extends StatelessWidget {
  const HRxBrowseHomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Main card ─────────────────────────────────────────────
          GestureDetector(
            onTap: () => context.push(AppRouter.browser),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.accentCyan.withValues(alpha: 0.15),
                    const Color(0xFF1D4ED8).withValues(alpha: 0.07),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppTheme.accentCyan.withValues(alpha: 0.22), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentCyan.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // ── Icon with shield badge ──
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.accentCyan.withValues(alpha: 0.35),
                              const Color(0xFF1D4ED8).withValues(alpha: 0.25),
                            ],
                          ),
                        ),
                        child: const Icon(Icons.public_rounded,
                            color: Colors.white, size: 26),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: Color(0xFF130820),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shield_rounded,
                              size: 11, color: AppTheme.accentViolet),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),

                  // ── Text ──
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: const TextSpan(
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.w800),
                            children: [
                              TextSpan(
                                  text: 'HRx',
                                  style: TextStyle(color: Colors.white)),
                              TextSpan(
                                  text: 'Browse',
                                  style: TextStyle(
                                      color: AppTheme.accentCyan)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Privacy-first browser',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),

                  // ── Quick action buttons ──
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _QuickBtn(
                        icon: Icons.public_rounded,
                        label: 'Open',
                        color: AppTheme.accentCyan,
                        onTap: () => context.push(AppRouter.browser),
                      ),
                      const SizedBox(height: 6),
                      _QuickBtn(
                        icon: Icons.visibility_off_rounded,
                        label: 'Private',
                        color: AppTheme.accentViolet,
                        onTap: () => context.push(
                          AppRouter.browser,
                          extra: <String, dynamic>{'private': true},
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Feature pills ──────────────────────────────────────────
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: const [
                _Pill(icon: Icons.block_rounded,
                    label: 'Ad Block', color: Colors.redAccent),
                SizedBox(width: 8),
                _Pill(icon: Icons.visibility_off_rounded,
                    label: 'Incognito', color: AppTheme.accentViolet),
                SizedBox(width: 8),
                _Pill(icon: Icons.lock_rounded,
                    label: 'HTTPS check', color: Colors.greenAccent),
                SizedBox(width: 8),
                _Pill(icon: Icons.history_rounded,
                    label: 'History', color: AppTheme.accentCyan),
                SizedBox(width: 8),
                _Pill(icon: Icons.bookmarks_rounded,
                    label: 'Bookmarks', color: Colors.amber),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick action button ───────────────────────────────────────────
class _QuickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickBtn(
      {required this.icon, required this.label,
       required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Feature pill ─────────────────────────────────────────────────
class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Pill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: color.withValues(alpha: 0.85))),
        ],
      ),
    );
  }
}
