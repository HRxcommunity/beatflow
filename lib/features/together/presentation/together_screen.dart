import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/together_bloc.dart';
import '../bloc/game_bloc.dart';
import '../domain/entities/session_entity.dart';
import '../../../core/theme/app_theme.dart';
import '../../../presentation/player/player_bloc.dart';
import '../../../presentation/settings/settings_bloc.dart';
import 'together_screen_chat.dart';
import 'games/games_panel.dart';

import '../../youtube/youtube_search_sheet.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../../core/router/app_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../social/widgets/qr_join_sheet.dart';
import 'watch_together_sheet.dart';

class TogetherScreen extends StatefulWidget {
  const TogetherScreen({super.key});

  @override
  State<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends State<TogetherScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _floatCtrl;
  late Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(_pulseCtrl);

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // BUG-G01 FIX: GameBloc is now provided at app root (main.dart) so
    // the notification overlay can reach it from any screen.
    return BlocConsumer<TogetherBloc, TogetherState>(
        listenWhen: (prev, curr) =>
            (curr.error != null && prev.error != curr.error) ||
            (prev.session?.pendingHostRequest?.status == 'pending' &&
                curr.session?.pendingHostRequest == null &&
                !curr.isOwner) ||
            // BUG-U03 FIX: fire on session leave so GameBloc can be reset
            (prev.isInSession != curr.isInSession),
        listener: (context, state) {
          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error!),
                backgroundColor: AppTheme.accentPink,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                action: SnackBarAction(
                  label: 'Dismiss',
                  textColor: Colors.white,
                  onPressed: () =>
                      context.read<TogetherBloc>().add(TogetherClearError()),
                ),
              ),
            );
          }
          // BUG-U03 FIX: reset GameBloc when leaving session to clear
          // stale rooms/invites from the previous session.
          if (!state.isInSession) {
            context.read<GameBloc>().add(GameReset());
          }
          // Initialize GameBloc when entering a session
          if (state.isInSession &&
              state.session != null &&
              state.uid != null) {
            context.read<GameBloc>().add(GameInitialize(
                  state.session!.sessionId,
                  state.uid!,
                  state.displayName ?? 'Player',
                ));
          }
        },
        builder: (context, state) {
          if (state.isInSession) {
            return _ActiveSessionScreen(
              state: state,
              pulseAnim: _pulseAnim,
            );
          }
          return _LandingScreen(
            state: state,
            pulseAnim: _pulseAnim,
            floatAnim: _floatAnim,
          );
        },
      );
  }
}

// ═══════════════════════════════════════════════════════════════
//  LANDING SCREEN  (unchanged, kept intact)
// ═══════════════════════════════════════════════════════════════

class _LandingScreen extends StatelessWidget {
  final TogetherState state;
  final Animation<double> pulseAnim;
  final Animation<double> floatAnim;

  const _LandingScreen({
    required this.state,
    required this.pulseAnim,
    required this.floatAnim,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDeep.withValues(alpha: 0.85),
        title: const Text('BeatFlow Together'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              AnimatedBuilder(
                animation: floatAnim,
                builder: (_, __) => Transform.translate(
                  offset: Offset(0, floatAnim.value),
                  child: AnimatedBuilder(
                    animation: pulseAnim,
                    builder: (_, __) => Transform.scale(
                      scale: pulseAnim.value,
                      child: _HeroIllustration(accent: accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Together ❤️🎬',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: 0.2,
                  shadows: [
                    Shadow(color: accent.withValues(alpha: 0.5), blurRadius: 20)
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Listen to music or watch videos together.\nReal-time sync. Anywhere.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              if (state.uid == null) ...[
                _SignInCard(accent: accent),
                const SizedBox(height: 20),
              ] else ...[
                _EditableNameChip(
                  accent: accent,
                  displayName: state.displayName ?? 'Guest',
                ),
                const SizedBox(height: 32),
                _CreateSessionButton(accent: accent, state: state),
                const SizedBox(height: 14),
                _JoinSessionButton(accent: accent),
                const SizedBox(height: 14),
                // ── Watch Together ───────────────────────────────
                _WatchTogetherButton(accent: accent),
                const SizedBox(height: 14),
                // ── Social Hub shortcut ──────────────────────────
                GestureDetector(
                  onTap: () => context.push(AppRouter.social),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppTheme.accentCyan.withValues(alpha: 0.4)),
                      color: AppTheme.accentCyan.withValues(alpha: 0.08),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('🌐', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text(
                          'Social Hub',
                          style: TextStyle(
                            color:      AppTheme.accentCyan,
                            fontSize:   15,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        const SizedBox(width: 6),
                        // FIX: wrapped in Flexible so it clips with ellipsis
                        // instead of overflowing the Row on narrow screens.
                        const Flexible(
                          child: Text(
                            '· Discover · Friends · Activity',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              color:    AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _HowItWorksCard(accent: accent),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
    return _TogetherBackground(child: scaffold);
  }
}

class _HeroIllustration extends StatelessWidget {
  final Color accent;
  const _HeroIllustration({required this.accent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                accent.withValues(alpha: 0.12),
                Colors.transparent,
              ]),
            ),
          ),
          Container(
            width: 155,
            height: 155,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: accent.withValues(alpha: 0.18),
                width: 1.5,
              ),
            ),
          ),
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.3),
                  AppTheme.accentCyan.withValues(alpha: 0.2),
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.4), width: 2),
              boxShadow: [
                BoxShadow(
                    color: accent.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 4),
              ],
            ),
            child: const Icon(Icons.favorite_rounded,
                size: 48, color: Colors.white),
          ),
          Positioned(
            left: 4,
            bottom: 40,
            child: _PersonBubble(accent: accent, isLeft: true),
          ),
          Positioned(
            right: 4,
            bottom: 40,
            child: _PersonBubble(accent: AppTheme.accentCyan, isLeft: false),
          ),
        ],
      ),
    );
  }
}

class _PersonBubble extends StatelessWidget {
  final Color accent;
  final bool isLeft;
  const _PersonBubble({required this.accent, required this.isLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: 0.5), accent.withValues(alpha: 0.2)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Icon(Icons.person_rounded, size: 20, color: accent),
    );
  }
}

// ── Editable name chip (tap pencil to change name) ────────────

class _EditableNameChip extends StatelessWidget {
  final Color accent;
  final String displayName;
  const _EditableNameChip({required this.accent, required this.displayName});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showEditDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [accent, AppTheme.accentCyan]),
              ),
              child: Center(
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              displayName,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit_rounded, color: accent.withValues(alpha: 0.7), size: 14),
            const SizedBox(width: 4),
            Container(
              width: 7, height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF22C55E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final ctrl = TextEditingController(text: displayName);
    final accent = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.person_rounded, color: accent, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Change Name',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ],
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter your name...',
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accent, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                context.read<TogetherBloc>().add(TogetherSignIn(name));
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SignInCard extends StatefulWidget {
  final Color accent;
  const _SignInCard({required this.accent});

  @override
  State<_SignInCard> createState() => _SignInCardState();
}

class _SignInCardState extends State<_SignInCard> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_rounded, color: widget.accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Choose your name',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter your name...',
              hintStyle: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1), width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1), width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: widget.accent, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final name = _ctrl.text.trim();
                if (name.isEmpty) return;
                context.read<TogetherBloc>().add(TogetherSignIn(name));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Continue',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateSessionButton extends StatelessWidget {
  final Color accent;
  final TogetherState state;
  const _CreateSessionButton({required this.accent, required this.state});

  @override
  Widget build(BuildContext context) {
    final isLoading = state.isLoading;
    return GestureDetector(
      onTap: isLoading ? null : () => _showCreateSheet(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: isLoading
                  ? [accent.withValues(alpha: 0.5), accent.withValues(alpha: 0.35)]
                  : [accent, accent.withValues(alpha: 0.75)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: isLoading
              ? []
              : [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: isLoading
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Creating Session...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Create Session',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    final playerState = context.read<PlayerBloc>().state;
    if (playerState.currentSong == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Play a song first to share your session!'),
          backgroundColor: AppTheme.bgCard,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: context.read<TogetherBloc>(),
        child: _CreateSessionSheet(
          playerBloc: context.read<PlayerBloc>(),
          accent: accent,
        ),
      ),
    );
  }
}

class _JoinSessionButton extends StatelessWidget {
  final Color accent;
  const _JoinSessionButton({required this.accent});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showJoinSheet(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_add_rounded, color: accent, size: 22),
            const SizedBox(width: 10),
            Text(
              'Join Session',
              style: TextStyle(
                color: accent,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showJoinSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: context.read<TogetherBloc>(),
        child: _JoinSessionSheet(accent: accent),
      ),
    );
  }
}

// ── Watch Together button ─────────────────────────────────────

class _WatchTogetherButton extends StatelessWidget {
  final Color accent;
  const _WatchTogetherButton({required this.accent});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => WatchTogetherSheet.show(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end:   Alignment.bottomRight,
            colors: [
              const Color(0xFFFF0000).withValues(alpha: 0.15),
              AppTheme.accentViolet.withValues(alpha: 0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFFF0000).withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🎬', style: TextStyle(fontSize: 20)),
            SizedBox(width: 10),
            Text(
              'Watch Together',
              style: TextStyle(
                color:      Colors.white,
                fontSize:   16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            SizedBox(width: 8),
            Text(
              '· YouTube · Local',
              style: TextStyle(
                color:   AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  final Color accent;
  const _HowItWorksCard({required this.accent});

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.play_circle_rounded, 'Play a song or pick a video to share'),
      (Icons.share_rounded, 'Create a session & share the code'),
      (Icons.group_rounded, 'Friends join with your 6-char code'),
      (Icons.sync_rounded, 'Listen or watch in perfect sync ✨'),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How it works',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 14),
          ...steps.asMap().entries.map((entry) {
            final i = entry.key;
            final (icon, text) = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${i + 1}. $text',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
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

// ═══════════════════════════════════════════════════════════════
//  CREATE SESSION SHEET
// ═══════════════════════════════════════════════════════════════

class _CreateSessionSheet extends StatefulWidget {
  final PlayerBloc playerBloc;
  final Color accent;

  const _CreateSessionSheet(
      {required this.playerBloc, required this.accent});

  @override
  State<_CreateSessionSheet> createState() => _CreateSessionSheetState();
}

class _CreateSessionSheetState extends State<_CreateSessionSheet> {
  bool   _isPublic     = false;
  String _roomCategory = 'general';

  static const _categories = [
    ('general', '🎵', 'General'),
    ('pop',     '🎤', 'Pop'),
    ('hiphop',  '🎤', 'Hip Hop'),
    ('lofi',    '☕', 'Lo-Fi'),
    ('rock',    '🎸', 'Rock'),
    ('edm',     '🎛️', 'EDM'),
  ];

  @override
  Widget build(BuildContext context) {
    final playerState = widget.playerBloc.state;
    final accent      = widget.accent;
    final song        = playerState.currentSong!;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Create Listening Session',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              shadows: [
                Shadow(color: accent.withValues(alpha: 0.4), blurRadius: 12)
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Share the code with friends to listen together.',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(colors: [
                      accent.withValues(alpha: 0.3),
                      AppTheme.bgSurface,
                    ]),
                  ),
                  child: Icon(Icons.music_note_rounded, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        song.artist,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.radio_button_checked_rounded,
                    color: accent, size: 16),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ── Public room toggle ─────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isPublic
                    ? accent.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                Text(
                  _isPublic ? '🌍' : '🔒',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Public Room',
                        style: TextStyle(
                          color:      AppTheme.textPrimary,
                          fontSize:   13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      Text(
                        _isPublic
                            ? 'Social Hub mein dikhega'
                            : 'Sirf code se join hoga',
                        style: TextStyle(
                          color:   AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value:          _isPublic,
                  activeColor:    accent,
                  onChanged: (v) => setState(() {
                    _isPublic = v;
                  }),
                ),
              ],
            ),
          ),
          // ── Category picker (visible when public) ─────────────
          if (_isPublic) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount:       _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final cat      = _categories[i];
                  final selected = _roomCategory == cat.$1;
                  return GestureDetector(
                    onTap: () => setState(() => _roomCategory = cat.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding:  const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color:        selected
                            ? accent.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border:       Border.all(
                          color: selected
                              ? accent.withValues(alpha: 0.6)
                              : Colors.white12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(cat.$2,
                              style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 4),
                          Text(
                            cat.$3,
                            style: TextStyle(
                              color:      selected ? accent : AppTheme.textSecondary,
                              fontSize:   12,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          BlocBuilder<TogetherBloc, TogetherState>(
            builder: (context, state) {
              return SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: state.isLoading
                      ? null
                      : () {
                          context.read<TogetherBloc>().add(
                                TogetherCreateSession(
                                  song: song,
                                  positionMs:
                                      playerState.position.inMilliseconds,
                                  isPlaying:    playerState.isPlaying,
                                  isPublic:     _isPublic,
                                  roomCategory: _roomCategory,
                                ),
                              );
                          Navigator.pop(context);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: state.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Create Session',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  JOIN SESSION SHEET
// ═══════════════════════════════════════════════════════════════

class _JoinSessionSheet extends StatefulWidget {
  final Color accent;
  const _JoinSessionSheet({required this.accent});

  @override
  State<_JoinSessionSheet> createState() => _JoinSessionSheetState();
}

class _JoinSessionSheetState extends State<_JoinSessionSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(24),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Join a Session',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                shadows: [
                  Shadow(
                      color: widget.accent.withValues(alpha: 0.4),
                      blurRadius: 12)
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter the 6-character code from your friend.',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 6,
              ),
              decoration: InputDecoration(
                hintText: 'XXXXXX',
                hintStyle: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.4),
                  fontSize: 22,
                  letterSpacing: 6,
                ),
                counterText: '',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1), width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1), width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: widget.accent, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 18),
              ),
            ),
            const SizedBox(height: 20),
            BlocBuilder<TogetherBloc, TogetherState>(
              builder: (context, state) {
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: state.isLoading
                        ? null
                        : () {
                            final code =
                                _ctrl.text.trim().toUpperCase();
                            if (code.length != 6) return;
                            context
                                .read<TogetherBloc>()
                                .add(TogetherJoinSession(code));
                            Navigator.pop(context);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: state.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'Join Session',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ACTIVE SESSION SCREEN  ← MAJOR REDESIGN
// ═══════════════════════════════════════════════════════════════

class _ActiveSessionScreen extends StatefulWidget {
  final TogetherState state;
  final Animation<double> pulseAnim;

  const _ActiveSessionScreen({required this.state, required this.pulseAnim});

  @override
  State<_ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<_ActiveSessionScreen>
    with TickerProviderStateMixin {
  late AnimationController _waveCtrl;
  late List<double> _barHeights;
  final _rng = Random(42);
  bool _showChat  = false;
  bool _showGames = false;
  int _lastSeenChatCount = 0;  // FIX: track msgs seen when chat was open
  int _totalChatCount    = 0;  // FIX: updated by StreamBuilder in chat panel

  // (Chat state moved to TogetherChatPanel widget)

  @override
  void initState() {
    super.initState();
    _barHeights =
        List.generate(20, (_) => 0.2 + _rng.nextDouble() * 0.8);
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        setState(() {
          _barHeights = List.generate(
            20,
            (_) => 0.2 + _rng.nextDouble() * 0.8,
          );
        });
      });

    if (widget.state.session?.isPlaying == true) {
      _waveCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(_ActiveSessionScreen old) {
    super.didUpdateWidget(old);
    final isPlaying = widget.state.session?.isPlaying ?? false;
    if (isPlaying && !_waveCtrl.isAnimating) {
      _waveCtrl.repeat();
    } else if (!isPlaying && _waveCtrl.isAnimating) {
      _waveCtrl.stop();
    }

    // Host change request came in → show dialog to current host
    final oldReq = old.state.session?.pendingHostRequest;
    final newReq = widget.state.session?.pendingHostRequest;
    if (widget.state.isOwner &&
        newReq != null &&
        newReq.status == 'pending' &&
        (oldReq == null || oldReq.requesterUid != newReq.requesterUid)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showHostRequestDialog(context, newReq);
      });
    }

    // Chat scroll is handled inside TogetherChatPanel widget
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    super.dispose();
  }

  void _showHostRequestDialog(
      BuildContext context, HostChangeRequest req) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.swap_horiz_rounded,
                color: Color(0xFFFBBF24), size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Host Change Request',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16),
              ),
            ),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
            children: [
              TextSpan(
                text: req.requesterName,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600),
              ),
              const TextSpan(
                text:
                    ' wants to become the new host. They will control the playback.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              context.read<TogetherBloc>().add(TogetherRejectHostChange());
              Navigator.pop(context);
            },
            child: const Text('Decline',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<TogetherBloc>().add(TogetherAcceptHostChange());
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFBBF24),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Accept',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _handleVideoCall(
      BuildContext context, SessionEntity session, bool isOwner) {
    if (session.callActive) {
      // Already live — join or navigate to call
      final channel = session.agoraChannel;
      if (channel == null) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const _VideoCallComingSoon(),
        ),
      );
    } else if (isOwner) {
      // Owner starts the call
      _showStartCallDialog(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Waiting for host to start a video call...'),
          backgroundColor: AppTheme.bgCard,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showStartCallDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.videocam_rounded, color: Color(0xFF22C55E), size: 22),
            SizedBox(width: 8),
            Flexible(
              child: Text('Start Video Call?',
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: const Text(
          'Start a live video call with all listeners in this session.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              context.read<TogetherBloc>().add(TogetherStartVideoCall());
              // Give Firestore a moment to update then navigate
              Future.delayed(const Duration(milliseconds: 800), () {
                if (!mounted) return;
                final s = context.read<TogetherBloc>().state.session;
                final ch = s?.agoraChannel;
                if (ch != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _VideoCallComingSoon(),
                    ),
                  );
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.videocam_rounded, size: 18),
            label: const Text('Start Call',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // FIX: was widget.state.session! — force unwrap caused crash during
    // leave/session-end race. Now gracefully pops if session is null.
    final session = widget.state.session;
    if (session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pop();
      });
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A1A),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final accent   = Theme.of(context).colorScheme.primary;
    final isOwner  = widget.state.isOwner;

    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      // FIX: false here because TogetherChatPanel uses AnimatedPadding +
      // MediaQuery.viewInsetsOf for WhatsApp-style keyboard lifting.
      // Setting true with a Stack causes double-resize glitches.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Background glows
          Positioned(
            top: -80, left: -80,
            child: Container(
              width: 320, height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  accent.withValues(alpha: 0.10),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: -100, right: -60,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppTheme.accentCyan.withValues(alpha: 0.08),
                  Colors.transparent,
                ]),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ── Top bar ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_back_ios_rounded,
                              color: Colors.white, size: 18),
                        ),
                        onPressed: () => context.pop(),
                      ),
                      Expanded(
                        child: Column(
                        children: [
                          const Text(
                            'LISTENING TOGETHER',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2.5,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6, height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF22C55E),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 🎮 Games toggle
                          BlocBuilder<GameBloc, GameState>(
                            builder: (ctx, gs) {
                              final hasInvites = gs.hasInvites;
                              return IconButton(
                                icon: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _showGames
                                        ? const Color(0xFF7C3AED).withValues(alpha: 0.25)
                                        : Colors.white.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Text(
                                        '🎮',
                                        style: TextStyle(fontSize: _showGames ? 17 : 15),
                                      ),
                                      if (hasInvites)
                                        Positioned(
                                          top: -4, right: -4,
                                          child: Container(
                                            width: 8, height: 8,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Color(0xFF7C3AED),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                onPressed: () => setState(() {
                                  _showGames = !_showGames;
                                  if (_showGames) _showChat = false;
                                }),
                              );
                            },
                          ),
                          // Chat toggle
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _showChat
                                    ? accent.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(Icons.chat_bubble_rounded,
                                      color: _showChat
                                          ? accent
                                          : Colors.white,
                                      size: 18),
                                  if (_totalChatCount > 0)
                                    Positioned(
                                      top: -4, right: -4,
                                      child: Container(
                                        width: 8, height: 8,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFFF43F5E),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            onPressed: () =>
                                setState(() {
                                  _showChat = !_showChat;
                                  if (_showChat) {
                                    _showGames = false;
                                    _lastSeenChatCount = _totalChatCount;
                                  }
                                }),
                          ),
                          // Video call button
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: session.callActive
                                    ? const Color(0xFF22C55E).withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                session.callActive
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_outlined,
                                color: session.callActive
                                    ? const Color(0xFF22C55E)
                                    : Colors.white,
                                size: 18,
                              ),
                            ),
                            onPressed: () => _handleVideoCall(context, session, isOwner),
                          ),
                          // Share (owner only)
                          if (isOwner)
                            IconButton(
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.share_rounded,
                                    color: Colors.white, size: 18),
                              ),
                              onPressed: () =>
                                  _shareCode(context, session),
                            )
                          else
                            const SizedBox(width: 4),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Body: games | chat | main ─────────────────
                Expanded(
                  child: _showGames
                      ? GamesPanel(
                          session: session,
                          myUid:   widget.state.uid ?? '',
                          accent:  accent.toString(),
                        )
                      : _showChat
                      ? TogetherChatPanel(
                          session:    session,
                          accent:     accent,
                          currentUid: widget.state.uid ?? '',
                          isOwner:    isOwner,
                          onMessageCountChanged: (count) {
                            if (mounted) setState(() => _totalChatCount = count);
                          },
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            children: [
                              const SizedBox(height: 20),

                              _SessionCodeCard(
                                  session: session, accent: accent),

                              if (isOwner &&
                                  widget.state.uploadProgress < 1.0 &&
                                  widget.state.uploadProgress > 0.0) ...[
                                const SizedBox(height: 12),
                                BlocBuilder<TogetherBloc, TogetherState>(
                                  builder: (ctx, ts) => _UploadProgressBar(
                                    progress: ts.uploadProgress,
                                    accent:   accent,
                                  ),
                                ),
                              ],

                              const SizedBox(height: 16),
                              _MembersCard(
                                  session:  session,
                                  accent:   accent,
                                  isOwner:  isOwner,
                                  myUid:    widget.state.uid ?? ''),
                              const SizedBox(height: 16),

                              // ── Unified Media Player (audio + video + YouTube) ──
                              _TogetherUnifiedPlayer(
                                session:    session,
                                accent:     accent,
                                isOwner:    isOwner,
                                barHeights: _barHeights,
                              ),

                              const SizedBox(height: 16),

                              // ── YouTube Search Card ──
                              _YoutubeSearchCard(
                                accent:  accent,
                                isOwner: isOwner,
                              ),
                              const SizedBox(height: 16),

                              // ── Listener actions ──
                              if (!isOwner) ...[
                                _ListenerActionsCard(
                                  session: session,
                                  accent:  accent,
                                ),
                                const SizedBox(height: 16),
                              ],

                              _LeaveButton(isOwner: isOwner, accent: accent),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return _TogetherBackground(child: scaffold);
  }

  void _shareCode(BuildContext context, SessionEntity session) {
    Clipboard.setData(ClipboardData(text: session.sessionCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Code "${session.sessionCode}" copied!'),
          ],
        ),
        backgroundColor: const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  LISTENER ACTIONS CARD (Host request + Play request)
// ═══════════════════════════════════════════════════════════════

class _ListenerActionsCard extends StatelessWidget {
  final SessionEntity session;
  final Color accent;

  const _ListenerActionsCard(
      {required this.session, required this.accent});

  @override
  Widget build(BuildContext context) {
    final hasPendingReq = session.pendingHostRequest != null;
    final myUid = context.read<TogetherBloc>().state.uid ?? '';
    final iAmRequester =
        session.pendingHostRequest?.requesterUid == myUid;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.07), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: accent.withValues(alpha: 0.7), size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'You are a listener. Only the host controls playback.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 14),

          // Request to become host
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: hasPendingReq
                  ? null
                  : () => _requestHost(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFBBF24),
                side: BorderSide(
                  color: hasPendingReq
                      ? Colors.white.withValues(alpha: 0.1)
                      : const Color(0xFFFBBF24),
                  width: 1.5,
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(
                iAmRequester
                    ? Icons.hourglass_top_rounded
                    : Icons.swap_horiz_rounded,
                size: 18,
              ),
              label: Text(
                iAmRequester
                    ? 'Request Sent — Waiting...'
                    : hasPendingReq
                        ? 'Request Pending'
                        : 'Request to Become Host',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _requestHost(BuildContext context) {
    context.read<TogetherBloc>().add(TogetherRequestHostChange());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.send_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Request sent to host!'),
          ],
        ),
        backgroundColor: const Color(0xFFFBBF24),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  SESSION CODE CARD
// ═══════════════════════════════════════════════════════════════

class _SessionCodeCard extends StatelessWidget {
  final SessionEntity session;
  final Color accent;

  const _SessionCodeCard({required this.session, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.15), AppTheme.bgCard],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        children: [
          const Text(
            'SESSION CODE',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 3,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    session.sessionCode,
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      letterSpacing: 10,
                      shadows: [
                        Shadow(color: accent.withValues(alpha: 0.6), blurRadius: 20)
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: session.sessionCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Code copied!'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.copy_rounded, color: accent, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // QR Code share button
          GestureDetector(
            onTap: () => QrJoinSheet.show(
              context,
              sessionCode: session.sessionCode,
              songTitle:   session.songTitle,
              ownerName:   session.ownerName,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color:        accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border:       Border.all(color: accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_rounded, color: accent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Show QR Code',
                    style: TextStyle(
                      color:      accent,
                      fontSize:   12,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Share this code with friends',
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Upload progress ───────────────────────────────────────────

class _UploadProgressBar extends StatefulWidget {
  final double progress;
  final Color accent;

  const _UploadProgressBar({required this.progress, required this.accent});

  @override
  State<_UploadProgressBar> createState() => _UploadProgressBarState();
}

class _UploadProgressBarState extends State<_UploadProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  String _label(double p) {
    if (p >= 1.0) return '✓ Audio ready for listeners!';
    if (p < 0.08) return 'Preparing audio for sync...';
    if (p < 0.5)  return 'Syncing preview for listeners… ${(p * 100).round()}%';
    return 'Buffering full track… ${(p * 100).round()}%';
  }

  String _subLabel(double p) {
    if (p < 0.5) return 'Friends will hear a preview in a few seconds';
    return 'Upgrading to full quality in background';
  }

  @override
  Widget build(BuildContext context) {
    final p     = widget.progress.clamp(0.0, 1.0);
    final isDone = p >= 1.0;
    final accent = widget.accent;

    return AnimatedOpacity(
      opacity: isDone ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 800),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) => Opacity(
                    opacity: _pulseAnim.value,
                    child: Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent,
                        boxShadow: [
                          BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _label(p),
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${(p * 100).round()}%',
                  style: TextStyle(
                    color: accent.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: p),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                builder: (_, val, __) => LinearProgressIndicator(
                  value: val,
                  backgroundColor: Colors.white.withValues(alpha: 0.07),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                  minHeight: 5,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _subLabel(p),
              style: TextStyle(
                color: accent.withValues(alpha: 0.55),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Members card ──────────────────────────────────────────────

class _MembersCard extends StatelessWidget {
  final SessionEntity session;
  final Color accent;
  final bool isOwner;
  final String myUid;

  const _MembersCard({
    required this.session,
    required this.accent,
    required this.isOwner,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Listeners (${session.onlineCount} online)',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...session.members.map((member) {
            final isCurrentOwner = member.uid == session.ownerId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: isCurrentOwner
                            ? [accent, accent.withValues(alpha: 0.5)]
                            : [
                                AppTheme.accentCyan.withValues(alpha: 0.5),
                                AppTheme.bgSurface
                              ],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        member.displayName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (member.uid == myUid) ...[
                          const SizedBox(width: 4),
                          const Text('😊', style: TextStyle(fontSize: 12)),
                        ],
                        if (isCurrentOwner) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'HOST',
                              style: TextStyle(
                                fontSize: 8,
                                color: accent,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: member.isOnline
                                ? const Color(0xFF22C55E)
                                : Colors.grey,
                            boxShadow: member.isOnline
                                ? [
                                    const BoxShadow(
                                      color: Color(0xFF22C55E),
                                      blurRadius: 6,
                                    )
                                  ]
                                : [],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          member.isOnline ? 'Online' : 'Away',
                          style: TextStyle(
                            fontSize: 11,
                            color: member.isOnline
                                ? const Color(0xFF22C55E)
                                : AppTheme.textSecondary,
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

// ══════════════════════════════════════════════════════════════
//  _TogetherUnifiedPlayer
//  Single adaptive player for audio (MP3), local MP4 video,
//  and YouTube — all in one card with shared controls.
//  Replaces: _NowPlayingCard + _TogetherVideoCard + _SyncedGuestVideoPlayer
// ══════════════════════════════════════════════════════════════

enum _MediaType { audio, localVideo, youtubeVideo }

class _TogetherUnifiedPlayer extends StatefulWidget {
  final SessionEntity session;
  final Color accent;
  final bool isOwner;
  final List<double> barHeights;

  const _TogetherUnifiedPlayer({
    required this.session,
    required this.accent,
    required this.isOwner,
    required this.barHeights,
  });

  @override
  State<_TogetherUnifiedPlayer> createState() => _TogetherUnifiedPlayerState();
}

class _TogetherUnifiedPlayerState extends State<_TogetherUnifiedPlayer> {
  // ── Position ticker ──────────────────────────────────────────
  Timer? _posTimer;
  int _livePositionMs = 0;

  // ── Local video ─────────────────────────────────────────────
  VideoPlayerController? _vidCtrl;
  bool _vidReady = false;
  String _loadedVidUrl = '';
  Timer? _bufferStallTimer;

  // ── YouTube WebView ──────────────────────────────────────────
  WebViewController? _webCtrl;
  bool _webLoading     = true;
  bool _webInitInProg  = false; // guard against concurrent init calls
  String _loadedYtId   = '';
  Timer? _webLoadTimeout;
  // FIX-152: tracks IFrame API error code (150/151/152 = embed disabled)
  String? _ytEmbedError;

  // ── Content-type detection ────────────────────────────────────
  _MediaType _getMediaType(SessionEntity s) {
    final isYt = s.streamUrl.startsWith('yt:') || s.songData.startsWith('yt:');
    if (isYt) return _MediaType.youtubeVideo;
    if (s.isVideo) return _MediaType.localVideo;
    return _MediaType.audio;
  }

  _MediaType get _mediaType => _getMediaType(widget.session);

  String get _youtubeId {
    final d = widget.session.songData;
    if (d.startsWith('yt:')) return d.substring(3);
    final u = widget.session.streamUrl;
    if (u.startsWith('yt:')) return u.substring(3);
    return '';
  }

  // ── Elapsed-corrected position ────────────────────────────────
  int _calcExpectedMs(SessionEntity s) {
    if (!s.isPlaying) return s.positionMs;
    if (s.songDurationMs <= 0) return s.positionMs;
    final elapsed = DateTime.now()
        .difference(s.effectivePlaybackUpdatedAt)
        .inMilliseconds;
    return (s.positionMs + elapsed.clamp(0, s.songDurationMs))
        .clamp(0, s.songDurationMs);
  }

  // ── Lifecycle ─────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _livePositionMs = widget.session.positionMs;
    _startTimer();
    _initMedia(widget.session);
  }

  @override
  void didUpdateWidget(_TogetherUnifiedPlayer old) {
    super.didUpdateWidget(old);
    final s = widget.session;
    final o = old.session;

    // Reset live position on seek / song change / pause
    if (o.positionMs != s.positionMs ||
        o.songId != s.songId ||
        o.isPlaying != s.isPlaying) {
      setState(() => _livePositionMs = s.positionMs);
      _startTimer();
    }

    // Handle media changes
    _syncMedia(s, o);
  }

  // ── Timer ─────────────────────────────────────────────────────
  void _startTimer() {
    _posTimer?.cancel();
    _posTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final dur = widget.session.songDurationMs;
      int newPos;
      if (widget.isOwner) {
        newPos = context.read<PlayerBloc>().state.position.inMilliseconds;
      } else {
        if (widget.session.isPlaying) {
          final elapsed = DateTime.now()
              .difference(widget.session.effectivePlaybackUpdatedAt)
              .inMilliseconds;
          newPos = widget.session.positionMs + elapsed;
        } else {
          newPos = widget.session.positionMs;
        }
      }
      if (dur > 0) newPos = newPos.clamp(0, dur);
      if (mounted) setState(() => _livePositionMs = newPos);
    });
  }

  // ── Media init / sync ─────────────────────────────────────────
  void _initMedia(SessionEntity s) {
    switch (_getMediaType(s)) {
      case _MediaType.localVideo:
        if (s.hasStreamUrl) _initVideoPlayer(s.streamUrl);
        break;
      case _MediaType.youtubeVideo:
        final id = _youtubeId;
        // _initYouTubeWebView is async (needs await for Android platform
        // call). Use unawaited() — fire-and-forget is intentional here;
        // the method's internal guards prevent duplicate/concurrent runs.
        if (id.isNotEmpty) unawaited(_initYouTubeWebView(id));
        break;
      case _MediaType.audio:
        break;
    }
  }

  void _syncMedia(SessionEntity curr, SessionEntity prev) {
    final type = _getMediaType(curr);

    if (type == _MediaType.localVideo) {
      if (curr.hasStreamUrl && curr.streamUrl != _loadedVidUrl) {
        _vidCtrl?.dispose();
        setState(() { _vidReady = false; _vidCtrl = null; });
        _initVideoPlayer(curr.streamUrl);
        return;
      }
      _handleVideoSync(curr);
    } else if (type == _MediaType.youtubeVideo) {
      final newId = _youtubeId;
      if (newId.isNotEmpty && newId != _loadedYtId) {
        unawaited(_initYouTubeWebView(newId));
      }
    }
  }

  // ── Local MP4 player ─────────────────────────────────────────
  Future<void> _initVideoPlayer(String url) async {
    if (url.isEmpty || !url.startsWith('http')) return;
    _loadedVidUrl = url;

    // BUG-VID-AUDIOFOCUS FIX: mixWithOthers=true tells ExoPlayer NOT to
    // request AUDIOFOCUS_GAIN. Without this, VideoPlayerController steals
    // audio focus from just_audio → just_audio pauses → PlayerBloc emits
    // isPlaying=false → TogetherSyncListener pushes isPlaying=false to
    // Firestore → video gets paused immediately after starting → endless
    // buffering loop.  Audio stays in just_audio (ctrl is muted below).
    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: const {
        'Connection': 'keep-alive',
        'Accept-Ranges': 'bytes',
      },
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _vidCtrl = ctrl;
    try {
      await ctrl.initialize();
      // Muted: audio comes from PlayerBloc / just_audio on the same URL
      await ctrl.setVolume(0.0);
      ctrl.addListener(_onVideoUpdate);
      if (!mounted) return;
      setState(() => _vidReady = true);
      final posMs = _calcExpectedMs(widget.session);
      await ctrl.seekTo(Duration(milliseconds: posMs));
      if (widget.session.isPlaying) await ctrl.play();
    } catch (e) {
      debugPrint('[UnifiedPlayer] Video init error: $e');
    }
  }

  void _onVideoUpdate() {
    if (!mounted) return;
    setState(() {});

    // Buffer-stall recovery: if buffering for > 8s while supposed to play,
    // seek forward 500ms to nudge ExoPlayer out of the stall.
    final ctrl = _vidCtrl;
    if (ctrl == null || !_vidReady) return;

    if (ctrl.value.isBuffering && widget.session.isPlaying) {
      _bufferStallTimer ??= Timer(const Duration(seconds: 8), () async {
        if (!mounted) { _bufferStallTimer = null; return; }
        final c = _vidCtrl;
        if (c != null && c.value.isBuffering) {
          final pos = c.value.position;
          await c.seekTo(pos + const Duration(milliseconds: 500));
          debugPrint('[UnifiedPlayer] Buffer stall → nudge seek to ${pos.inSeconds}s');
        }
        _bufferStallTimer = null;
      });
    } else {
      _bufferStallTimer?.cancel();
      _bufferStallTimer = null;
    }
  }

  void _handleVideoSync(SessionEntity s) {
    final ctrl = _vidCtrl;
    if (ctrl == null || !_vidReady) return;

    // BUG-VID-BUFF FIX: removed the old `!ctrl.value.isBuffering` guard.
    // Calling play() while the video is buffering is intentional — ExoPlayer
    // will begin playback as soon as the buffer is ready.  The old condition
    // meant play() was *never* called during the initial buffer phase, so
    // the video stayed frozen on "Buffering…" forever.
    if (s.isPlaying && !ctrl.value.isPlaying) {
      ctrl.play();
    } else if (!s.isPlaying && ctrl.value.isPlaying) {
      ctrl.pause();
    }

    // Drift correction: skip during buffering (position reads are unreliable
    // mid-buffer and seeking into an unbuffered position stalls further).
    if (s.isPlaying && !ctrl.value.isBuffering) {
      final expected = _calcExpectedMs(s);
      final actual   = ctrl.value.position.inMilliseconds;
      if ((expected - actual).abs() > 3000) {
        debugPrint('[UnifiedPlayer] Drift ${(expected - actual).abs()}ms → seeking');
        ctrl.seekTo(Duration(milliseconds: expected));
      }
    }
  }

  // ── YouTube WebView ────────────────────────────────────────────
  //
  // WHY ASYNC + HTML WRAPPER (not the old sync loadRequest approach):
  //
  // OLD CODE PROBLEMS:
  //  1. No setMediaPlaybackRequiresUserGesture(false)
  //     → Android WebView blocks autoplay → video frame stays BLACK.
  //  2. onPageFinished fired when HTML downloaded, not when player ready
  //     → spinner hid too early, revealing black player background.
  //  3. loadRequest with Referer header only covers the first request;
  //     subsequent player sub-requests have no Referer → YouTube may
  //     reject embedding.
  //  4. Navigation allowlist only covered 'youtube'/'youtu.be'; all
  //     CDN domains (googlevideo, ytimg, gstatic…) were blocked.
  //  5. No timeout → if onPageFinished never fires, spinner shows forever.
  //  6. No _webInitInProgress guard → rapid didUpdateWidget calls could
  //     start two concurrent initialisations, second overwriting first,
  //     creating a leaked WebViewController.
  //
  // NEW APPROACH:
  //  • async method so we can await the Android platform call
  //  • _webInitInProgress + _loadedYtId guard against concurrent/duplicate runs
  //  • setMediaPlaybackRequiresUserGesture(false) → autoplay works
  //  • setBackgroundColor(black) → no white flash
  //  • HTML wrapper with YouTube IFrame Player API:
  //      – onReady callback → YTTogether.postMessage('ready') → accurate load detection
  //      – player.playVideo() in onReady → reliable autoplay even if autoplay= blocked
  //      – baseUrl 'https://www.youtube.com' → correct document origin, no header tricks
  //  • Expanded navigation allowlist covers all YouTube CDN domains
  //  • 10-second fallback timer prevents infinite spinner on IFrame API failure
  Future<void> _initYouTubeWebView(String videoId) async {
    // ── Concurrency guard ───────────────────────────────────────
    // Prevents two concurrent WebView inits if _syncMedia / _initMedia
    // are called in quick succession (e.g. two rapid didUpdateWidget calls).
    if (_webInitInProg && _loadedYtId == videoId) return;
    // Also no-op if same video already loaded and WebView is live
    if (_loadedYtId == videoId && _webCtrl != null) return;

    _webInitInProg = true;
    _loadedYtId = videoId;
    _webLoadTimeout?.cancel();

    if (mounted) setState(() { _webLoading = true; _ytEmbedError = null; });

    // ── Create WebViewController ────────────────────────────────
    final ctrl = WebViewController();

    // ── CRITICAL FIX 1: Disable user-gesture media requirement ──
    // Root cause of black screen: Android WebView blocks all media
    // autoplay (including YouTube's player.playVideo()) unless a user
    // gesture originated the call. This flag disables that restriction
    // for this WebView instance. Must be awaited BEFORE loadHtmlString.
    if (ctrl.platform is AndroidWebViewController) {
      await (ctrl.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
      debugPrint('[UnifiedPlayer] ✓ setMediaPlaybackRequiresUserGesture(false)');
    }

    // If widget was disposed during the await, bail out
    if (!mounted) {
      _webInitInProg = false;
      return;
    }

    const kUA = 'Mozilla/5.0 (Linux; Android 10; Mobile) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36';

    ctrl
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // CRITICAL FIX 2: black background prevents white flash before
      // the YouTube player's dark UI finishes rendering.
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(kUA)
      // JS channel — receives player events from the HTML wrapper.
      // Name 'YTTogether' avoids collision with YoutubeVideoScreen's 'YTFlutter'.
      ..addJavaScriptChannel('YTTogether', onMessageReceived: (msg) {
        final data = msg.message;
        debugPrint('[UnifiedPlayer] YT JS: $data');
        // Hide spinner only after IFrame API confirms player is truly ready
        // (onPageFinished fires too early — player JS still downloading)
        if ((data == 'ready' || data.startsWith('state:')) && mounted && _webLoading) {
          _webLoadTimeout?.cancel();
          setState(() => _webLoading = false);
        } else if (data.startsWith('error:') && mounted) {
          // FIX-152: capture IFrame API error code.
          // 150/151/152 = video owner disabled embedding — show custom
          // fallback overlay with "Watch on YouTube" button instead of
          // YouTube's grey "This video is unavailable" screen.
          final errCode = data.substring(6);
          debugPrint('[UnifiedPlayer] YT player error code: $errCode');
          _webLoadTimeout?.cancel();
          setState(() {
            _webLoading = false;
            if (errCode == '150' || errCode == '151' || errCode == '152') {
              _ytEmbedError = errCode;
            }
          });
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        // CRITICAL FIX 3: do NOT hide spinner in onPageFinished.
        // This fires when the wrapper HTML's DOM loads — YouTube IFrame
        // API JS is still downloading. Wait for 'ready' via YTTogether.
        onPageFinished: (url) =>
            debugPrint('[UnifiedPlayer] YT page loaded — awaiting IFrame API ready'),
        onWebResourceError: (e) {
          debugPrint('[UnifiedPlayer] YT resource error: ${e.description} '
              '(code=${e.errorCode}, mainFrame=${e.isForMainFrame})');
          // Main-frame errors (DNS fail, SSL error) mean nothing will load;
          // hide spinner so screen isn't stuck.
          if (e.isForMainFrame == true && mounted && _webLoading) {
            _webLoadTimeout?.cancel();
            setState(() => _webLoading = false);
          }
        },
        // CRITICAL FIX 4: expanded allow-list covers all domains the
        // YouTube player needs. Old code only allowed 'youtube'/'youtu.be',
        // silently blocking video streams (googlevideo.com) and assets.
        onNavigationRequest: (req) {
          final url = req.url;
          if (url.contains('youtube.com')         ||
              url.contains('youtube-nocookie.com') ||
              url.contains('youtu.be')             ||
              url.contains('googlevideo.com')      ||
              url.contains('ytimg.com')            ||
              url.contains('ggpht.com')            ||
              url.contains('gstatic.com')          ||
              url.contains('googleapis.com')) {
            return NavigationDecision.navigate;
          }
          debugPrint('[UnifiedPlayer] Blocked WebView nav: $url');
          return NavigationDecision.prevent;
        },
      ))
      // FIX 5: loadHtmlString + baseUrl sets document.origin = youtube.com
      // so IFrame API postMessage handshake works without any Referer tricks.
      // Old loadRequest(headers:{Referer:...}) only covered the first HTTP
      // request; all subsequent player sub-requests had no Referer.
      ..loadHtmlString(_buildYouTubePlayerHtml(videoId),
          baseUrl: 'https://www.youtube.com');

    // FIX 6: Fallback — if IFrame API never fires ready (e.g. network
    // issue, embedding disabled), force-hide spinner after 10 s so the
    // YouTube player's own error UI becomes visible.
    _webLoadTimeout = Timer(const Duration(seconds: 10), () {
      if (mounted && _webLoading) {
        debugPrint('[UnifiedPlayer] YT load timeout — revealing player');
        setState(() => _webLoading = false);
      }
    });

    if (mounted) setState(() => _webCtrl = ctrl);
    _webInitInProg = false;
  }

  /// Self-contained HTML page hosting the YouTube IFrame Player API.
  ///
  /// Key design decisions:
  /// • YT.Player (IFrame API) instead of raw <iframe src> URL so we get
  ///   the onReady event and can call player.playVideo() programmatically.
  /// • player.playVideo() in onReady = guaranteed start; autoplay=1 alone
  ///   is unreliable in Android WebView even with the user-gesture flag.
  /// • <meta referrer="origin"> makes all requests from this page send
  ///   Referer: https://www.youtube.com, matching our baseUrl origin.
  /// • JS channel name 'YTTogether' avoids collision with the standalone
  ///   YoutubeVideoScreen which uses 'YTFlutter'.
  String _buildYouTubePlayerHtml(String videoId) {
    final id = videoId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '');
    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no">
  <meta name="referrer" content="origin">
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    html,body { width:100%; height:100%; background:#000; overflow:hidden; }
    #player { width:100%; height:100%; }
    iframe { display:block; width:100%!important; height:100%!important; border:none; }
  </style>
</head>
<body>
<div id="player"></div>
<script>
  (function(){
    var tag=document.createElement('script');
    tag.src='https://www.youtube.com/iframe_api';
    var first=document.getElementsByTagName('script')[0];
    first.parentNode.insertBefore(tag,first);
  })();

  var ytPlayer;
  function onYouTubeIframeAPIReady(){
    ytPlayer=new YT.Player('player',{
      videoId:'$id',
      playerVars:{
        autoplay:1, controls:1, playsinline:1,
        rel:0, modestbranding:1, enablejsapi:1,
        origin:'https://www.youtube.com'
      },
      events:{
        onReady:function(e){
          e.target.playVideo();
          if(typeof YTTogether!=='undefined') YTTogether.postMessage('ready');
        },
        onStateChange:function(e){
          if(typeof YTTogether!=='undefined') YTTogether.postMessage('state:'+e.data);
        },
        onError:function(e){
          if(typeof YTTogether!=='undefined') YTTogether.postMessage('error:'+e.data);
        }
      }
    });
  }
</script>
</body>
</html>''';
  }

  // ── Dispose ────────────────────────────────────────────────────
  @override
  void dispose() {
    _posTimer?.cancel();
    _bufferStallTimer?.cancel();
    _webLoadTimeout?.cancel();          // FIX: cancel fallback timer
    _webInitInProg = false;
    _vidCtrl?.removeListener(_onVideoUpdate);
    _vidCtrl?.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────
  String _fmt(int ms) {
    final cap = widget.session.songDurationMs > 0
        ? widget.session.songDurationMs
        : ms;
    final d = Duration(milliseconds: ms.clamp(0, cap));
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  IconData get _mediaIcon {
    switch (_mediaType) {
      case _MediaType.audio:       return Icons.music_note_rounded;
      case _MediaType.localVideo:  return Icons.videocam_rounded;
      case _MediaType.youtubeVideo:return Icons.smart_display_rounded;
    }
  }

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final session  = widget.session;
    final accent   = widget.accent;
    final posMs    = _livePositionMs;
    final durMs    = session.songDurationMs;
    final progress = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
    final isYt     = _mediaType == _MediaType.youtubeVideo;

    return BlocListener<TogetherBloc, TogetherState>(
      listenWhen: (prev, curr) {
        final p = prev.session;
        final c = curr.session;
        if (c == null) return false;
        return p?.isPlaying  != c.isPlaying  ||
               p?.positionMs != c.positionMs  ||
               p?.streamUrl  != c.streamUrl;
      },
      listener: (_, state) {
        if (state.session != null && _mediaType == _MediaType.localVideo) {
          _handleVideoSync(state.session!);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Icon(_mediaIcon, color: accent, size: 15),
                  const SizedBox(width: 6),
                  const Text(
                    'NOW PLAYING',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isYt) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF0000).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('YouTube',
                          style: TextStyle(
                              color: Color(0xFFFF0000),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5)),
                    ),
                  ],
                  const Spacer(),
                  // Mini waveform (audio mode only)
                  if (_mediaType == _MediaType.audio)
                    SizedBox(
                      width: 60, height: 20,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(
                          min(widget.barHeights.length, 12),
                          (i) {
                            final h = session.isPlaying
                                ? 20.0 * widget.barHeights[i]
                                : 4.0;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeInOut,
                              width: 2.5,
                              height: h.clamp(3.0, 20.0),
                              margin: const EdgeInsets.symmetric(horizontal: 0.8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: accent.withValues(alpha: 
                                    session.isPlaying ? 0.9 : 0.3),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Media Area (adapts per type) ────────────────────────
            _buildMediaArea(accent),

            // ── Title + Artist ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // FIX: for YouTube sessions with missing/garbled title,
                    // show a clean YouTube fallback instead of "unknown" or raw IDs.
                    isYt
                        ? _sanitizeYtTitle(session.songTitle)
                        : _sanitizeTitle(session.songTitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isYt
                        ? _sanitizeYtArtist(session.songArtist)
                        : _sanitizeArtist(session.songArtist),
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Progress + status (audio + local video) ─────────────
            if (!isYt) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (progress as double).clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                    minHeight: 4,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(posMs),
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary)),
                    Row(children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: session.isPlaying
                              ? const Color(0xFF22C55E)
                              : Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        session.isPlaying ? 'Playing' : 'Paused',
                        style: TextStyle(
                          fontSize: 11,
                          color: session.isPlaying
                              ? const Color(0xFF22C55E)
                              : Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                    Text(_fmt(durMs),
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ] else ...[
              // YouTube: LIVE indicator (YouTube controls are in the video)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Row(children: [
                  Container(
                    width: 7, height: 7,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Color(0xFFFF0000)),
                  ),
                  const SizedBox(width: 6),
                  const Text('LIVE',
                      style: TextStyle(
                          color: Color(0xFFFF0000),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                  const SizedBox(width: 10),
                  const Text('YouTube controls inside the video',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ]),
              ),
              const SizedBox(height: 4),
            ],

            // ── Host controls (audio + local video only) ────────────
            if (widget.isOwner && !isYt) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: _buildHostControls(accent, durMs),
              ),
            ] else ...[
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  // ── Media area builder ─────────────────────────────────────────
  Widget _buildMediaArea(Color accent) {
    switch (_mediaType) {
      case _MediaType.audio:
        return _buildAudioArtwork(accent);
      case _MediaType.localVideo:
        return _buildInlineVideoPlayer(accent);
      case _MediaType.youtubeVideo:
        return _buildYouTubeEmbed();
    }
  }

  // Audio: gradient strip with animated equalizer bars
  Widget _buildAudioArtwork(Color accent) {
    final session = widget.session;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      height: 76,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: 0.13), accent.withValues(alpha: 0.04)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18), width: 1),
      ),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
          child: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.music_note_rounded, color: accent, size: 22),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Audio Track',
                  style: TextStyle(
                      color: accent.withValues(alpha: 0.65),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 6),
              SizedBox(
                height: 22,
                child: Row(
                  children: List.generate(18, (i) {
                    final h = session.isPlaying && i < widget.barHeights.length
                        ? 22.0 * widget.barHeights[i]
                        : 4.0;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      width: 2.8,
                      height: h.clamp(3.0, 22.0),
                      margin: const EdgeInsets.only(right: 1.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: accent.withValues(alpha: 
                            session.isPlaying ? 0.85 : 0.25),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
      ]),
    );
  }

  // Local MP4: inline synced video frame with buffering overlay + fullscreen
  Widget _buildInlineVideoPlayer(Color accent) {
    final ctrl = _vidCtrl;
    final hasUrl = widget.session.hasStreamUrl;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      constraints: const BoxConstraints(minHeight: 160, maxHeight: 240),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video frame
            if (_vidReady && ctrl != null)
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width:  ctrl.value.size.width  > 0 ? ctrl.value.size.width  : 1920,
                    height: ctrl.value.size.height > 0 ? ctrl.value.size.height : 1080,
                    child: VideoPlayer(ctrl),
                  ),
                ),
              )
            else if (!hasUrl)
              // Uploading
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                CircularProgressIndicator(color: accent, strokeWidth: 2),
                const SizedBox(height: 10),
                Text('Video uploading… please wait',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
              ])
            else
              // Initializing player
              const Center(
                child: CircularProgressIndicator(
                    color: AppTheme.accentViolet),
              ),

            // Buffering overlay (shown during mid-playback stalls)
            if (_vidReady && ctrl?.value.isBuffering == true)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppTheme.accentViolet),
                      SizedBox(height: 10),
                      Text('Buffering…',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ),

            // Fullscreen button
            if (_vidReady && ctrl != null)
              Positioned(
                right: 8, top: 8,
                child: GestureDetector(
                  onTap: () {
                    final posMs = ctrl.value.position.inMilliseconds;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _TogetherLocalVideoPlayer(
                        streamUrl:    widget.session.streamUrl,
                        title:        widget.session.songTitle,
                        artist:       widget.session.songArtist,
                        initialPosMs: posMs,
                        isPlaying:    widget.session.isPlaying,
                      ),
                    ));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.fullscreen_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // YouTube: inline WebView embed
  Widget _buildYouTubeEmbed() {
    final ytId = _youtubeId;

    // No video ID yet — session data still propagating from host
    if (ytId.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        height: 120,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF0000)),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      height: 210,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFFF0000).withValues(alpha: 0.35), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // WebView is always present in the tree once created so it
            // keeps rendering even while the loading overlay is visible.
            // Removing it from tree on _webLoading=true would re-create
            // the platform view on every toggle, causing flicker.
            if (_webCtrl != null)
              WebViewWidget(controller: _webCtrl!)
            else
              const ColoredBox(color: Colors.black),

            // Loading overlay — hidden ONLY after YTTogether.postMessage('ready')
            // fires from the IFrame API onReady callback (or after 10-second
            // fallback timeout). NOT hidden on onPageFinished (too early).
            if (_webLoading)
              Container(
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                          color: Color(0xFFFF0000), strokeWidth: 2.5),
                      SizedBox(height: 12),
                      Text(
                        'Loading YouTube video…',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),

            // FIX-152: Embed-disabled overlay (error 150/151/152).
            // Replaces YouTube's grey "This video is unavailable" screen
            // with a clean on-brand card + "Watch on YouTube" fallback.
            if (_ytEmbedError != null)
              _buildYtEmbedErrorOverlay(ytId),
          ],
        ),
      ),
    );
  }

  // ── FIX-152: Embed-disabled error overlay ─────────────────────
  // Called when IFrame API fires error 150/151/152 (embedding blocked).
  // Shows a clean fallback instead of YouTube's grey "unavailable" screen.
  Widget _buildYtEmbedErrorOverlay(String videoId) {
    final ytUrl  = Uri.parse('https://www.youtube.com/watch?v=$videoId');
    final accent = widget.accent;

    // Wrap in SingleChildScrollView so content never overflows the 210px
    // container regardless of font scaling or "Try another video" row.
    return Container(
      color: const Color(0xFF0D0D0D),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(
          height: 210,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon — kept compact (44px) so total fits within 210px
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color:  Colors.red.withValues(alpha: 0.12),
                  shape:  BoxShape.circle,
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: const Center(
                  child: Text('🚫', style: TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(height: 8),

              // Error message
              const Text(
                'Embedding disabled',
                style: TextStyle(
                  color:      Colors.white,
                  fontSize:   13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Video owner has blocked embedding\non third-party apps.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color:    Colors.white38,
                    fontSize: 11,
                    height:   1.4,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Watch on YouTube button
              GestureDetector(
                onTap: () async {
                  if (await canLaunchUrl(ytUrl)) {
                    await launchUrl(ytUrl, mode: LaunchMode.externalApplication);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color:        Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.smart_display_rounded, color: Colors.white, size: 15),
                      SizedBox(width: 6),
                      Text(
                        'Watch on YouTube',
                        style: TextStyle(
                          color:      Colors.white,
                          fontSize:   12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // "Try another video" — owner only
              if (widget.isOwner)
                GestureDetector(
                  onTap: () {
                    setState(() => _ytEmbedError = null);
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => BlocProvider.value(
                        value: context.read<TogetherBloc>(),
                        child: YoutubeSearchSheet(isOwner: true),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '🔍  Try another video',
                      style: TextStyle(
                        color:      accent.withValues(alpha: 0.8),
                        fontSize:   11,
                        fontWeight: FontWeight.w600,
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

  // Host controls row
  Widget _buildHostControls(Color accent, int durMs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.admin_panel_settings_rounded, color: accent, size: 14),
          const SizedBox(width: 6),
          Text('Host Controls',
              style: TextStyle(
                  color: accent.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ControlBtn(
              icon: Icons.skip_previous_rounded,
              accent: accent, size: 22,
              onTap: () {
                context.read<PlayerBloc>().add(PlayerSeek(Duration.zero));
                context.read<TogetherBloc>().add(const TogetherPushSeek(0));
              },
            ),
            _ControlBtn(
              icon: Icons.replay_10_rounded,
              accent: accent, size: 22,
              onTap: () {
                final cur = context.read<PlayerBloc>().state.position.inMilliseconds;
                final pos = (cur - 10000).clamp(0, durMs);
                context.read<PlayerBloc>().add(PlayerSeek(Duration(milliseconds: pos)));
                context.read<TogetherBloc>().add(TogetherPushSeek(pos));
              },
            ),
            GestureDetector(
              onTap: () {
                final pb = context.read<PlayerBloc>();
                final ps = pb.state;
                if (ps.currentSong != null) {
                  if (ps.isPlaying) pb.add(PlayerPause());
                  else pb.add(PlayerResume());
                }
              },
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [accent, accent.withValues(alpha: 0.7)]),
                  boxShadow: [BoxShadow(
                      color: accent.withValues(alpha: 0.4), blurRadius: 14)],
                ),
                child: Icon(
                  widget.session.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white, size: 26,
                ),
              ),
            ),
            _ControlBtn(
              icon: Icons.forward_10_rounded,
              accent: accent, size: 22,
              onTap: () {
                final cur = context.read<PlayerBloc>().state.position.inMilliseconds;
                final pos = (cur + 10000).clamp(0, durMs);
                context.read<PlayerBloc>().add(PlayerSeek(Duration(milliseconds: pos)));
                context.read<TogetherBloc>().add(TogetherPushSeek(pos));
              },
            ),
            _ControlBtn(
              icon: Icons.skip_next_rounded,
              accent: accent, size: 22,
              onTap: () {
                final pos = durMs > 1000 ? durMs - 1000 : 0;
                context.read<PlayerBloc>().add(PlayerSeek(Duration(milliseconds: pos)));
                context.read<TogetherBloc>().add(TogetherPushSeek(pos));
              },
            ),
          ],
        ),
      ]),
    );
  }
}

// Helper: sanitize artist strings — filters Android MediaStore "<unknown>" sentinel
String _sanitizeArtist(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return 'Unknown Artist';
  if (t == '<unknown>') return 'Unknown Artist';
  if (t.startsWith('<') && t.endsWith('>') && t.length < 40) return 'Unknown Artist';
  return t;
}

// Helper: strip Firebase Storage URLs / file paths from song title display
String _sanitizeTitle(String raw) {
  if (raw.isEmpty) return 'Unknown Song';
  final tokenRe = RegExp(r'^[A-Za-z0-9+/=_\-]{30,}$');
  if (tokenRe.hasMatch(raw.trim())) return 'Unknown Song';
  if (raw.startsWith('http') || raw.startsWith('https')) {
    try {
      final uri   = Uri.parse(raw);
      final parts = uri.path.replaceAll('%2F', '/').split('/');
      final fn    = parts.lastWhere(
        (p) => p.isNotEmpty && !p.startsWith('v0') && !p.startsWith('b'),
        orElse: () => '',
      ).split('?').first;
      final decoded = Uri.decodeComponent(fn);
      final dot     = decoded.lastIndexOf('.');
      final name    = dot > 0 ? decoded.substring(0, dot) : decoded;
      if (name.isNotEmpty && name.length < 200) return name;
    } catch (_) {}
    return 'Unknown Song';
  }
  if (raw.startsWith('/') || raw.contains('://')) {
    final parts = raw.split('/');
    final fn    = parts.last.split('?').first;
    final dot   = fn.lastIndexOf('.');
    final name  = dot > 0 ? fn.substring(0, dot) : fn;
    return name.isEmpty ? 'Unknown Song' : name;
  }
  if (raw.length > 80 && !raw.contains(' ')) return 'Unknown Song';
  return raw;
}

// ── YouTube-aware sanitizers ──────────────────────────────────────────────
// Used when session.streamUrl starts with 'yt:'.
// Extra cases beyond the base helpers:
//   • 'unknown' / 'Unknown Song' literal → 'YouTube Video' (audio song's
//     old metadata leaked into the session before the YT video replaced it)
//   • purely lowercase/numeric strings with no spaces (garbled IDs) → 'YouTube Video'
String _sanitizeYtTitle(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return 'YouTube Video';
  final lower = t.toLowerCase();
  if (lower == 'unknown' || lower == 'unknown song' || lower == 'unknown title') {
    return 'YouTube Video';
  }
  // Detect raw IDs / hashes — all lowercase, no spaces, reasonable ID length
  if (t.length <= 30 && !t.contains(' ') && t == t.toLowerCase() &&
      RegExp(r'^[a-z0-9_\-]+$').hasMatch(t)) {
    return 'YouTube Video';
  }
  return _sanitizeTitle(t);
}

String _sanitizeYtArtist(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return 'YouTube';
  final lower = t.toLowerCase();
  if (lower == 'unknown' || lower == 'unknown artist' || lower == 'local video') {
    return 'YouTube';
  }
  // Garbled ID in artist field — same heuristic as above
  if (t.length <= 30 && !t.contains(' ') && t == t.toLowerCase() &&
      RegExp(r'^[a-z0-9_\-]+$').hasMatch(t)) {
    return 'YouTube';
  }
  return _sanitizeArtist(t);
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final double size;
  final VoidCallback onTap;

  const _ControlBtn({
    required this.icon,
    required this.accent,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: accent, size: size),
      ),
    );
  }
}

// ── Leave button ──────────────────────────────────────────────

class _LeaveButton extends StatelessWidget {
  final bool isOwner;
  final Color accent;

  const _LeaveButton({required this.isOwner, required this.accent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _confirmLeave(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.accentPink,
          side: const BorderSide(color: AppTheme.accentPink, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        icon: Icon(isOwner ? Icons.close_rounded : Icons.exit_to_app_rounded,
            size: 20),
        label: Text(
          isOwner ? 'End Session' : 'Leave Session',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
    );
  }

  void _confirmLeave(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isOwner ? 'End Session?' : 'Leave Session?',
          style: const TextStyle(
              color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
        ),
        content: Text(
          isOwner
              ? 'Ending the session will disconnect all listeners.'
              : 'You will stop listening with the group.',
          style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<TogetherBloc>().add(TogetherLeaveSession());
              context.pop();
            },
            child: Text(
              isOwner ? 'End' : 'Leave',
              style: const TextStyle(
                  color: AppTheme.accentPink, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  _YoutubeSearchCard  (search-only — playback is in unified player)
// ══════════════════════════════════════════════════════════════

class _YoutubeSearchCard extends StatelessWidget {
  final Color accent;
  final bool isOwner;

  const _YoutubeSearchCard({required this.accent, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TogetherBloc, TogetherState>(
      buildWhen: (p, c) => p.ytLoading != c.ytLoading,
      builder: (context, state) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: const Color(0xFFFF0000).withValues(alpha: 0.25), width: 1),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFF0000).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: state.ytLoading
                  ? const Padding(
                      padding: EdgeInsets.all(11),
                      child: CircularProgressIndicator(
                          color: Color(0xFFFF0000), strokeWidth: 2))
                  : const Icon(Icons.smart_display_rounded,
                      color: Color(0xFFFF0000), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('YouTube',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  Text(
                    state.ytLoading
                        ? 'Loading stream…'
                        : isOwner
                            ? 'Search & play for everyone'
                            : 'Search & share in chat',
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: state.ytLoading
                  ? null
                  : () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => BlocProvider.value(
                          value: context.read<TogetherBloc>(),
                          child: YoutubeSearchSheet(isOwner: isOwner),
                        ),
                      );
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(colors: [
                    const Color(0xFFFF0000)
                        .withValues(alpha: state.ytLoading ? 0.4 : 1.0),
                    const Color(0xFFFF0000)
                        .withValues(alpha: state.ytLoading ? 0.3 : 0.7),
                  ]),
                ),
                child: const Text('Search',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        );
      },
    );
  }
}


class _VideoCallComingSoon extends StatelessWidget {
  const _VideoCallComingSoon();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06060E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF06060E),
        title: const Text('Video Call'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_rounded,
                size: 64, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            const Text(
              'Video Call\nComing Soon',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 20,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'This feature will be re-enabled\nin a future update.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  TOGETHER BACKGROUND WRAPPER
// ═══════════════════════════════════════════════════════════════
/// Wraps Together screens with either the custom Together background image
/// (if set in Settings → Together Screen Background) or the default dark bg.
class _TogetherBackground extends StatelessWidget {
  final Widget child;
  const _TogetherBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, c) =>
          p.togetherBgType != c.togetherBgType ||
          p.togetherBgImagePath != c.togetherBgImagePath ||
          p.togetherBgDimOpacity != c.togetherBgDimOpacity,
      builder: (context, state) {
        final hasCustomBg = state.togetherBgType == 1 &&
            state.togetherBgImagePath != null &&
            state.togetherBgImagePath!.isNotEmpty;

        if (!hasCustomBg) {
          return ColoredBox(
            color: AppTheme.bgDeep,
            child: child,
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // Custom Together background image
            Image.file(
              File(state.togetherBgImagePath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: AppTheme.bgDeep,
              ),
            ),
            // Dim overlay
            ColoredBox(
              color: Colors.black.withValues(alpha: state.togetherBgDimOpacity),
            ),
            // Screen content
            child,
          ],
        );
      },
    );
  }
}

// ╔══════════════════════════════════════════════════════════════════════╗
// ║  _TogetherLocalVideoPlayer                                           ║
// ║  Full-screen video player opened via the fullscreen button above.    ║
// ║  Accepts initialPosMs so it starts at the same position as inline.  ║
// ╚══════════════════════════════════════════════════════════════════════╝
class _TogetherLocalVideoPlayer extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String artist;
  final int    initialPosMs;
  final bool   isPlaying;

  const _TogetherLocalVideoPlayer({
    required this.streamUrl,
    required this.title,
    required this.artist,
    this.initialPosMs = 0,
    this.isPlaying    = true,
  });

  @override
  State<_TogetherLocalVideoPlayer> createState() =>
      _TogetherLocalVideoPlayerState();
}

class _TogetherLocalVideoPlayerState
    extends State<_TogetherLocalVideoPlayer> {
  late VideoPlayerController _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    // BUG-VID-AUDIOFOCUS FIX: mixWithOthers=true so the fullscreen
    // VideoPlayerController doesn't steal audio focus from just_audio.
    _ctrl = VideoPlayerController.networkUrl(
      Uri.parse(widget.streamUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    await _ctrl.initialize();
    _ctrl.addListener(() { if (mounted) setState(() {}); });
    // Seek to the position passed from the inline player
    if (widget.initialPosMs > 0) {
      await _ctrl.seekTo(Duration(milliseconds: widget.initialPosMs));
    }
    setState(() => _ready = true);
    if (widget.isPlaying) _ctrl.play();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? "${d.inHours}:" : ""}$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        Text(widget.artist,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // BUG-VID-PORTRAIT FIX: same FittedBox fix as inline player
          // so portrait videos fill the full-screen view correctly.
          // BUG-VID-BUFF-FS FIX: added Stack + buffering overlay here
          // (fullscreen player had no buffering indicator after init).
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_ready)
                  SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _ctrl.value.size.width  > 0
                            ? _ctrl.value.size.width   : 1920,
                        height: _ctrl.value.size.height > 0
                            ? _ctrl.value.size.height  : 1080,
                        child: VideoPlayer(_ctrl),
                      ),
                    ),
                  )
                else
                  const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.accentViolet)),
                // Buffering overlay (shown mid-playback when network stalls)
                if (_ready && _ctrl.value.isBuffering)
                  const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.accentViolet)),
              ],
            ),
          ),
          if (_ready)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _ctrl,
                      builder: (_, v, __) {
                        final pos  = v.position;
                        final tot  = v.duration;
                        final prog = tot.inMilliseconds == 0
                            ? 0.0
                            : pos.inMilliseconds / tot.inMilliseconds;
                        return Column(
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                                trackHeight: 3,
                                activeTrackColor: AppTheme.accentViolet,
                                inactiveTrackColor:
                                    Colors.white.withValues(alpha: 0.3),
                                thumbColor: AppTheme.accentViolet,
                                overlayShape: SliderComponentShape.noOverlay,
                              ),
                              child: Slider(
                                value: prog.clamp(0.0, 1.0),
                                onChanged: (vv) => _ctrl.seekTo(Duration(
                                    milliseconds:
                                        (vv * tot.inMilliseconds).round())),
                              ),
                            ),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_fmt(pos),
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 11)),
                                Text(_fmt(tot),
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 11)),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.replay_10_rounded,
                              color: Colors.white, size: 36),
                          onPressed: () async {
                            final pos = _ctrl.value.position;
                            await _ctrl.seekTo(
                                pos - const Duration(seconds: 10));
                          },
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => _ctrl.value.isPlaying
                              ? _ctrl.pause()
                              : _ctrl.play(),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                                color: AppTheme.accentViolet,
                                shape: BoxShape.circle),
                            child: Icon(
                              _ctrl.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.forward_10_rounded,
                              color: Colors.white, size: 36),
                          onPressed: () async {
                            final pos = _ctrl.value.position;
                            await _ctrl.seekTo(
                                pos + const Duration(seconds: 10));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
