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
        backgroundColor: AppTheme.bgDeep.withOpacity(0.85),
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
                'Listen Together ❤️',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: 0.2,
                  shadows: [
                    Shadow(color: accent.withOpacity(0.5), blurRadius: 20)
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Share music moments in real time.\nAnywhere. Together.',
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
                accent.withOpacity(0.12),
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
                color: accent.withOpacity(0.18),
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
                  accent.withOpacity(0.3),
                  AppTheme.accentCyan.withOpacity(0.2),
                ],
              ),
              border: Border.all(color: accent.withOpacity(0.4), width: 2),
              boxShadow: [
                BoxShadow(
                    color: accent.withOpacity(0.3),
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
          colors: [accent.withOpacity(0.5), accent.withOpacity(0.2)],
        ),
        border: Border.all(color: accent.withOpacity(0.6), width: 1.5),
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
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
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
            Icon(Icons.edit_rounded, color: accent.withOpacity(0.7), size: 14),
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
            fillColor: Colors.white.withOpacity(0.05),
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
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
        border: Border.all(color: Colors.white.withOpacity(0.07), width: 1),
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
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: Colors.white.withOpacity(0.1), width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: Colors.white.withOpacity(0.1), width: 1),
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
                  ? [accent.withOpacity(0.5), accent.withOpacity(0.35)]
                  : [accent, accent.withOpacity(0.75)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: isLoading
              ? []
              : [
                  BoxShadow(
                    color: accent.withOpacity(0.35),
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
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withOpacity(0.4), width: 1.5),
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

class _HowItWorksCard extends StatelessWidget {
  final Color accent;
  const _HowItWorksCard({required this.accent});

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.play_circle_rounded, 'Play any song in BeatFlow'),
      (Icons.share_rounded, 'Create a session & share code'),
      (Icons.group_rounded, 'Friends join with your code'),
      (Icons.sync_rounded, 'Listen in perfect sync ✨'),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
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
                      color: accent.withOpacity(0.12),
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

class _CreateSessionSheet extends StatelessWidget {
  final PlayerBloc playerBloc;
  final Color accent;

  const _CreateSessionSheet(
      {required this.playerBloc, required this.accent});

  @override
  Widget build(BuildContext context) {
    final playerState = playerBloc.state;
    final song = playerState.currentSong!;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
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
                color: Colors.white.withOpacity(0.2),
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
                Shadow(color: accent.withOpacity(0.4), blurRadius: 12)
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
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.white.withOpacity(0.06), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(colors: [
                      accent.withOpacity(0.3),
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
          const SizedBox(height: 24),
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
                                  isPlaying: playerState.isPlaying,
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
              Border.all(color: Colors.white.withOpacity(0.08), width: 1),
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
                  color: Colors.white.withOpacity(0.2),
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
                      color: widget.accent.withOpacity(0.4),
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
                  color: AppTheme.textSecondary.withOpacity(0.4),
                  fontSize: 22,
                  letterSpacing: 6,
                ),
                counterText: '',
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.1), width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.1), width: 1),
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
                  accent.withOpacity(0.10),
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
                  AppTheme.accentCyan.withOpacity(0.08),
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
                            color: Colors.white.withOpacity(0.08),
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
                                        ? const Color(0xFF7C3AED).withOpacity(0.25)
                                        : Colors.white.withOpacity(0.08),
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
                                    ? accent.withOpacity(0.2)
                                    : Colors.white.withOpacity(0.08),
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
                                    ? const Color(0xFF22C55E).withOpacity(0.2)
                                    : Colors.white.withOpacity(0.08),
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
                                  color: Colors.white.withOpacity(0.08),
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

                              // ── Now Playing + Controls ──
                              _NowPlayingCard(
                                session:    session,
                                accent:     accent,
                                isOwner:    isOwner,
                                barHeights: _barHeights,
                              ),

                              const SizedBox(height: 16),

                              // ── YouTube in Together ──
                              _YoutubeInTogetherCard(
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
            Border.all(color: Colors.white.withOpacity(0.07), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: accent.withOpacity(0.7), size: 18),
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
                      ? Colors.white.withOpacity(0.1)
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
          colors: [accent.withOpacity(0.15), AppTheme.bgCard],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.25), width: 1),
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
                        Shadow(color: accent.withOpacity(0.6), blurRadius: 20)
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
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.copy_rounded, color: accent, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Share this code with friends',
            style: TextStyle(
              color: AppTheme.textSecondary.withOpacity(0.7),
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
          color: accent.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withOpacity(0.18)),
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
                          BoxShadow(color: accent.withOpacity(0.5), blurRadius: 6),
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
                    color: accent.withOpacity(0.7),
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
                  backgroundColor: Colors.white.withOpacity(0.07),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                  minHeight: 5,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _subLabel(p),
              style: TextStyle(
                color: accent.withOpacity(0.55),
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
        border: Border.all(color: Colors.white.withOpacity(0.07), width: 1),
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
                            ? [accent, accent.withOpacity(0.5)]
                            : [
                                AppTheme.accentCyan.withOpacity(0.5),
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
                              color: accent.withOpacity(0.15),
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

// ── Now Playing Card (with host play/pause controls) ──────────

// ── FIX: NowPlayingCard is now StatefulWidget with a live 500ms timer
//  Host  → reads position from PlayerBloc (actual audio playhead)
//  Guest → calculates positionMs + elapsed_since_updatedAt (Firestore clock)
//  This ensures the displayed time MOVES even though Firestore positionMs
//  is only updated on seek/song-change, not continuously.
class _NowPlayingCard extends StatefulWidget {
  final SessionEntity session;
  final Color accent;
  final bool isOwner;
  final List<double> barHeights;

  const _NowPlayingCard({
    required this.session,
    required this.accent,
    required this.isOwner,
    required this.barHeights,
  });

  @override
  State<_NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends State<_NowPlayingCard> {
  Timer? _posTimer;
  int _livePositionMs = 0;

  @override
  void initState() {
    super.initState();
    _livePositionMs = widget.session.positionMs;
    _startTimer();
  }

  @override
  void didUpdateWidget(_NowPlayingCard old) {
    super.didUpdateWidget(old);
    // On session update (seek/song change/pause) — reset live position
    if (old.session.positionMs  != widget.session.positionMs ||
        old.session.songId       != widget.session.songId      ||
        old.session.isPlaying    != widget.session.isPlaying) {
      // Restart timer so elapsed calculation starts fresh from new anchor
      // BUG-S05 FIX: immediately update position so guest UI doesn't show
      // stale position for up to 500ms while waiting for next timer tick.
      setState(() => _livePositionMs = widget.session.positionMs);
      _startTimer();
    }
  }

  void _startTimer() {
    _posTimer?.cancel();
    _posTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final dur = widget.session.songDurationMs;

      int newPos;
      if (widget.isOwner) {
        // Host: read actual audio playhead from PlayerBloc
        newPos = context.read<PlayerBloc>().state.position.inMilliseconds;
      } else {
        // Guest: reconstruct position from Firestore anchor + elapsed time
        if (widget.session.isPlaying) {
          // BUG-S01 FIX: use effectivePlaybackUpdatedAt (anchored to
          // play/pause/seek only) so guest joins don't corrupt the
          // elapsed-time position estimate shown in the UI.
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

  @override
  void dispose() {
    _posTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posMs    = _livePositionMs;
    final durMs    = widget.session.songDurationMs;
    final progress = durMs > 0 ? posMs / durMs : 0.0;

    final session  = widget.session;
    final accent   = widget.accent;
    final isOwner  = widget.isOwner;
    final barHeights = widget.barHeights;

    String fmt(int ms) {
      final d = Duration(milliseconds: ms.clamp(0, durMs > 0 ? durMs : ms));
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.music_note_rounded, color: accent, size: 16),
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
              const Spacer(),
              // Mini waveform
              SizedBox(
                width: 60, height: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(
                    min(barHeights.length, 12),
                    (i) {
                      final h = session.isPlaying
                          ? 20.0 * barHeights[i]
                          : 4.0;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeInOut,
                        width: 2.5,
                        height: h.clamp(3.0, 20.0),
                        margin: const EdgeInsets.symmetric(horizontal: 0.8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: accent.withOpacity(
                              session.isPlaying ? 0.9 : 0.3),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Text(
            _sanitizeTitle(session.songTitle),
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
            session.songArtist,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 16),

          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(fmt(posMs),
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
              Row(
                children: [
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
                ],
              ),
              Text(fmt(durMs),
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ),

          // ── HOST PLAYBACK CONTROLS ──
          if (isOwner) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withOpacity(0.18)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.admin_panel_settings_rounded,
                          color: accent, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Host Controls',
                        style: TextStyle(
                          color: accent.withOpacity(0.85),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Previous — seek to 0
                      _ControlBtn(
                        icon: Icons.skip_previous_rounded,
                        accent: accent,
                        size: 22,
                        onTap: () {
                          context.read<PlayerBloc>()
                              .add(PlayerSeek(Duration.zero));
                          context.read<TogetherBloc>()
                              .add(const TogetherPushSeek(0));
                        },
                      ),
                      // Seek back 10s
                      _ControlBtn(
                        icon: Icons.replay_10_rounded,
                        accent: accent,
                        size: 22,
                        onTap: () {
                          final curPos = context.read<PlayerBloc>()
                              .state.position.inMilliseconds;
                          final newPos = (curPos - 10000).clamp(0, durMs);
                          context.read<PlayerBloc>().add(
                              PlayerSeek(Duration(milliseconds: newPos)));
                          context.read<TogetherBloc>().add(
                              TogetherPushSeek(newPos));
                        },
                      ),
                      // Play / Pause (main button)
                      GestureDetector(
                        onTap: () {
                          final playerBloc = context.read<PlayerBloc>();
                          final ps         = playerBloc.state;
                          if (ps.currentSong != null) {
                            if (ps.isPlaying) {
                              playerBloc.add(PlayerPause());
                            } else {
                              playerBloc.add(PlayerResume());
                            }
                          }
                        },
                        child: Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                                colors: [accent, accent.withOpacity(0.7)]),
                            boxShadow: [
                              BoxShadow(
                                  color: accent.withOpacity(0.4),
                                  blurRadius: 14)
                            ],
                          ),
                          child: Icon(
                            session.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                      // Seek forward 10s
                      _ControlBtn(
                        icon: Icons.forward_10_rounded,
                        accent: accent,
                        size: 22,
                        onTap: () {
                          final curPos = context.read<PlayerBloc>()
                              .state.position.inMilliseconds;
                          final newPos = (curPos + 10000).clamp(0, durMs);
                          context.read<PlayerBloc>().add(
                              PlayerSeek(Duration(milliseconds: newPos)));
                          context.read<TogetherBloc>().add(
                              TogetherPushSeek(newPos));
                        },
                      ),
                      // Skip to end / next
                      _ControlBtn(
                        icon: Icons.skip_next_rounded,
                        accent: accent,
                        size: 22,
                        onTap: () {
                          final endPos = durMs > 1000 ? durMs - 1000 : 0;
                          context.read<PlayerBloc>().add(
                              PlayerSeek(Duration(milliseconds: endPos)));
                          context.read<TogetherBloc>().add(
                              TogetherPushSeek(endPos));
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Helper: strip Firebase Storage URLs / file paths from song title display
String _sanitizeTitle(String raw) {
  if (raw.isEmpty) return 'Unknown Song';

  // Firebase Storage download token — base64url with no spaces, very long
  // e.g. "WaKHhMug5gpuLs4G1ejr+h..." → garbage, show Unknown Song
  final tokenRe = RegExp(r'^[A-Za-z0-9+/=_\-]{30,}$');
  if (tokenRe.hasMatch(raw.trim())) return 'Unknown Song';

  // Looks like a Firebase Storage / HTTP URL → extract readable filename
  if (raw.startsWith('http') || raw.startsWith('https')) {
    try {
      final uri   = Uri.parse(raw);
      // Try "alt=media&token=..." style URLs — get path segment
      final parts = uri.path.replaceAll('%2F', '/').split('/');
      final filename = parts.lastWhere(
        (p) => p.isNotEmpty && !p.startsWith('v0') && !p.startsWith('b'),
        orElse: () => '',
      ).split('?').first;
      final decoded = Uri.decodeComponent(filename);
      final dot = decoded.lastIndexOf('.');
      final name = dot > 0 ? decoded.substring(0, dot) : decoded;
      if (name.isNotEmpty && name.length < 200) return name;
    } catch (_) {}
    return 'Unknown Song';
  }

  // Local file path
  if (raw.startsWith('/') || raw.contains('://')) {
    final parts = raw.split('/');
    final filename = parts.last.split('?').first;
    final dot = filename.lastIndexOf('.');
    final name = dot > 0 ? filename.substring(0, dot) : filename;
    return name.isEmpty ? 'Unknown Song' : name;
  }

  // Suspiciously long with no spaces → garbage token
  if (raw.length > 80 && !raw.contains(' ')) return 'Unknown Song';

  return raw;
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
          color: Colors.white.withOpacity(0.07),
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
        icon: Icon(
          isOwner ? Icons.close_rounded : Icons.exit_to_app_rounded,
          size: 20,
        ),
        label: Text(
          isOwner ? 'End Session' : 'Leave Session',
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
    );
  }

  void _confirmLeave(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
//  YOUTUBE IN TOGETHER CARD
// ══════════════════════════════════════════════════════════════

class _YoutubeInTogetherCard extends StatelessWidget {
  final Color accent;
  final bool isOwner;

  const _YoutubeInTogetherCard({required this.accent, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TogetherBloc, TogetherState>(
      buildWhen: (p, c) =>
          p.ytLoading  != c.ytLoading  ||
          p.ytResults  != c.ytResults  ||
          p.session?.songId != c.session?.songId ||
          p.session?.songTitle != c.session?.songTitle,
      builder: (context, state) {
        // Detect if a YouTube track is currently playing in session
        final session      = state.session;
        final isYtPlaying  = session != null &&
            session.streamUrl.isNotEmpty &&
            session.streamUrl.startsWith('http') &&
            !session.songData.startsWith('/'); // local files start with /

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isYtPlaying
                  ? const Color(0xFFFF0000).withOpacity(0.5)
                  : const Color(0xFFFF0000).withOpacity(0.25),
              width: isYtPlaying ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF0000).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: state.ytLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                                color: Color(0xFFFF0000), strokeWidth: 2),
                          )
                        : const Icon(Icons.smart_display_rounded,
                            color: Color(0xFFFF0000), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'YouTube Music',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          state.ytLoading
                              ? 'Loading stream...'
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
                          const Color(0xFFFF0000).withOpacity(
                              state.ytLoading ? 0.4 : 1.0),
                          const Color(0xFFFF0000).withOpacity(
                              state.ytLoading ? 0.3 : 0.7),
                        ]),
                      ),
                      child: const Text(
                        'Search',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),

              // ── Now Playing strip (YouTube track active) ──
              if (isYtPlaying) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF0000).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.music_note_rounded,
                          color: Color(0xFFFF0000), size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          session!.songTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFF0000),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Color(0xFFFF0000),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Video Call stub (Agora removed to reduce APK size) ───────────────────────
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
                size: 64, color: Colors.white.withOpacity(0.3)),
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
              color: Colors.black.withOpacity(state.togetherBgDimOpacity),
            ),
            // Screen content
            child,
          ],
        );
      },
    );
  }
}
