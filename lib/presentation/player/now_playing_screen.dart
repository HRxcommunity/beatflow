import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/player_state_entity.dart';
import '../../domain/entities/song_entity.dart';
import '../player/player_bloc.dart';
import '../settings/settings_bloc.dart';
import '../songs/library_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../features/together/bloc/together_bloc.dart';
import '../../core/router/app_router.dart';
import '../../widgets/common/song_artwork_widget.dart';
import 'package:go_router/go_router.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with TickerProviderStateMixin {
  // Disc rotation
  late AnimationController _rotationCtrl;
  // Pulsing glow ring
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;
  // Particle float
  late AnimationController _particleCtrl;
  // Waveform bars
  late AnimationController _waveCtrl;
  late List<double> _barHeights;
  final _rng = Random();
  // Background orb drift
  late AnimationController _orbCtrl;
  late Animation<Alignment> _orbAnim;

  static const int _barCount = 26;

  @override
  void initState() {
    super.initState();

    _barHeights = List.generate(_barCount, (_) => 0.15 + _rng.nextDouble() * 0.85);

    _rotationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        if (mounted) {
          setState(() {
            _barHeights = List.generate(
              _barCount,
              (_) => 0.15 + _rng.nextDouble() * 0.85,
            );
          });
        }
      });

    _orbCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _orbAnim = AlignmentTween(
      begin: const Alignment(-0.6, -0.5),
      end: const Alignment(0.6, 0.3),
    ).animate(CurvedAnimation(parent: _orbCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _rotationCtrl.dispose();
    _glowCtrl.dispose();
    _particleCtrl.dispose();
    _waveCtrl.dispose();
    _orbCtrl.dispose();
    super.dispose();
  }

  void _syncPlayState(bool isPlaying) {
    if (isPlaying) {
      if (!_rotationCtrl.isAnimating) _rotationCtrl.repeat();
      if (!_waveCtrl.isAnimating) _waveCtrl.repeat();
    } else {
      _rotationCtrl.stop();
      _waveCtrl.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerBloc, PlayerStateEntity>(
      builder: (context, state) {
        if (state.currentSong == null) {
          return const Scaffold(
            body: Center(child: Text('Nothing playing')),
          );
        }

        _syncPlayState(state.isPlaying);

        final song = state.currentSong!;
        final accent = Theme.of(context).colorScheme.primary;
        final size = MediaQuery.of(context).size;
        final hasBg = context.select<SettingsBloc, bool>(
          (b) => b.state.backgroundType == 1 && (b.state.backgroundImagePath?.isNotEmpty ?? false),
        );

        return Scaffold(
          backgroundColor: hasBg ? Colors.transparent : AppTheme.bgDeep,
          body: Stack(
            children: [
              // ── Background ambient orbs ──
              AnimatedBuilder(
                animation: _orbAnim,
                builder: (_, __) => Stack(children: [
                  Positioned.fill(
                    child: Align(
                      alignment: _orbAnim.value,
                      child: Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [
                            accent.withOpacity(0.18),
                            Colors.transparent,
                          ]),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -80,
                    right: -60,
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          AppTheme.accentCyan.withOpacity(0.10),
                          Colors.transparent,
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),

              // ── Floating particles ──
              AnimatedBuilder(
                animation: _particleCtrl,
                builder: (_, __) => CustomPaint(
                  size: Size(size.width, size.height),
                  painter: _ParticlePainter(_particleCtrl.value, accent),
                ),
              ),

              // ── Main content ──
              SafeArea(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                  children: [
                    // App bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white, size: 22),
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Expanded(
                            child: Column(
                              children: [
                                Text('NOW PLAYING',
                                    style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 3,
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    )),
                              ],
                            ),
                          ),
                          // Together live indicator
                          BlocBuilder<TogetherBloc, TogetherState>(
                            buildWhen: (p, c) => p.isInSession != c.isInSession,
                            builder: (context, togetherState) {
                              if (!togetherState.isInSession) {
                                return IconButton(
                                  icon: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.more_horiz_rounded,
                                        color: Colors.white, size: 22),
                                  ),
                                  onPressed: () {},
                                );
                              }
                              return GestureDetector(
                                onTap: () => context.push(AppRouter.together),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [
                                      accent,
                                      AppTheme.accentCyan.withOpacity(0.8),
                                    ]),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accent.withOpacity(0.4),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.favorite_rounded,
                                          color: Colors.white, size: 12),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${togetherState.session?.onlineCount ?? 0}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Rotating disc with glow rings ──
                    AnimatedBuilder(
                      animation: Listenable.merge([_rotationCtrl, _glowAnim]),
                      builder: (_, __) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer glow ring
                            Container(
                              width: 280,
                              height: 280,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: accent.withOpacity(0.12 * _glowAnim.value),
                                  width: 24,
                                ),
                              ),
                            ),
                            // Mid glow ring
                            Container(
                              width: 255,
                              height: 255,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: accent.withOpacity(0.20 * _glowAnim.value),
                                  width: 8,
                                ),
                              ),
                            ),
                            // Disc
                            Transform.rotate(
                              angle: _rotationCtrl.value * 2 * pi,
                              child: Container(
                                width: 236,
                                height: 236,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: SweepGradient(
                                    colors: [
                                      AppTheme.bgCard,
                                      AppTheme.bgSurface,
                                      AppTheme.bgCard,
                                      accent.withOpacity(0.12),
                                      AppTheme.bgCard,
                                    ],
                                    stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accent.withOpacity(0.3 * _glowAnim.value),
                                      blurRadius: 32,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Vinyl grooves
                                    for (double r in [60.0, 75.0, 90.0, 105.0])
                                      Container(
                                        width: r * 2,
                                        height: r * 2,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.04),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                    // Center hub with artwork
                                    SongArtworkWidget(
                                      songId: song.id,
                                      size: 56,
                                      isCircle: true,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Needle arm
                            if (state.isPlaying)
                              Positioned(
                                top: 18,
                                right: 38,
                                child: Transform.rotate(
                                  angle: -0.4,
                                  alignment: Alignment.topCenter,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 3,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(4),
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.white.withOpacity(0.8),
                                              accent.withOpacity(0.6),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: accent,
                                          boxShadow: [
                                            BoxShadow(color: accent, blurRadius: 6),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 28),

                    // ── Song info ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          Text(
                            song.title,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            song.artist,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Like & add buttons ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _GlassIconBtn(
                            icon: song.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: song.isFavorite ? AppTheme.accentPink : AppTheme.textSecondary,
                            onTap: () => context
                                .read<PlayerBloc>()
                                .add(PlayerToggleFavorite(song.id)),
                          ),
                          // Waveform visualizer inline
                          _PremiumWaveform(
                            isPlaying: state.isPlaying,
                            barHeights: _barHeights,
                            color: accent,
                          ),
                          _GlassIconBtn(
                            icon: Icons.playlist_add_rounded,
                            color: AppTheme.textSecondary,
                            onTap: () => _showAddToPlaylistSheet(context, song),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ── Progress bar ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          _PremiumSlider(
                            value: state.progress.clamp(0.0, 1.0),
                            accent: accent,
                            onChanged: (v) {
                              final pos = Duration(
                                milliseconds: (v * state.duration.inMilliseconds).round(),
                              );
                              context.read<PlayerBloc>().add(PlayerSeek(pos));
                            },
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_fmt(state.position),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w500)),
                              Text(_fmt(state.duration),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Controls ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Shuffle
                          _ControlBtn(
                            icon: state.isShuffled
                                ? Icons.shuffle_on_outlined
                                : Icons.shuffle_rounded,
                            size: 22,
                            color: state.isShuffled ? accent : AppTheme.textSecondary,
                            onTap: () => context
                                .read<PlayerBloc>()
                                .add(PlayerToggleShuffle()),
                          ),
                          // Previous
                          _ControlBtn(
                            icon: Icons.skip_previous_rounded,
                            size: 36,
                            color: AppTheme.textPrimary,
                            onTap: () =>
                                context.read<PlayerBloc>().add(PlayerPrevious()),
                          ),
                          // Play / Pause — big button
                          AnimatedBuilder(
                            animation: _glowAnim,
                            builder: (_, __) => GestureDetector(
                              onTap: () {
                                if (state.isPlaying) {
                                  context.read<PlayerBloc>().add(PlayerPause());
                                } else {
                                  context.read<PlayerBloc>().add(PlayerResume());
                                }
                              },
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      accent,
                                      accent.withOpacity(0.7),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accent.withOpacity(
                                          0.45 + 0.15 * _glowAnim.value),
                                      blurRadius: 24 + 8 * _glowAnim.value,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: state.isLoading
                                    ? const Padding(
                                        padding: EdgeInsets.all(22),
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2),
                                      )
                                    : Icon(
                                        state.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 36,
                                      ),
                              ),
                            ),
                          ),
                          // Next
                          _ControlBtn(
                            icon: Icons.skip_next_rounded,
                            size: 36,
                            color: AppTheme.textPrimary,
                            onTap: () =>
                                context.read<PlayerBloc>().add(PlayerNext()),
                          ),
                          // Repeat
                          _ControlBtn(
                            icon: _repeatIcon(state.repeatMode),
                            size: 22,
                            color: state.repeatMode != RepeatMode.off
                                ? accent
                                : AppTheme.textSecondary,
                            onTap: () {
                              final next = RepeatMode.values[
                                  (state.repeatMode.index + 1) %
                                      RepeatMode.values.length];
                              context.read<PlayerBloc>().add(PlayerSetRepeat(next));
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Bottom extras row ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _GlassIconBtn(
                            icon: Icons.tune_rounded,
                            color: AppTheme.textSecondary,
                            onTap: () => context.push(AppRouter.equalizer),
                            label: 'EQ',
                          ),
                          _SpeedBtn(
                            speed: state.speed,
                            onTap: () => _showSpeedSheet(context, state),
                          ),
                          _GlassIconBtn(
                            icon: Icons.lyrics_outlined,
                            color: AppTheme.textSecondary,
                            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Lyrics coming soon'),
                                duration: Duration(seconds: 2),
                              ),
                            ),
                            label: 'Lyrics',
                          ),
                          _GlassIconBtn(
                            icon: Icons.queue_music_rounded,
                            color: AppTheme.textSecondary,
                            onTap: () => _showQueueSheet(context, state),
                            label: 'Queue',
                          ),
                          _GlassIconBtn(
                            icon: state.sleepTimerMinutes != null
                                ? Icons.bedtime_rounded
                                : Icons.bedtime_outlined,
                            color: state.sleepTimerMinutes != null
                                ? Theme.of(context).colorScheme.primary
                                : AppTheme.textSecondary,
                            onTap: () => _showSleepTimerSheet(context, state),
                            label: state.sleepTimerMinutes != null
                                ? '${state.sleepTimerMinutes}m'
                                : 'Sleep',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ), // SingleChildScrollView
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _repeatIcon(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.one:
        return Icons.repeat_one_rounded;
      case RepeatMode.all:
        return Icons.repeat_on_outlined;
      case RepeatMode.off:
        return Icons.repeat_rounded;
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showAddToPlaylistSheet(BuildContext context, SongEntity song) {
    final libraryBloc = context.read<LibraryBloc>();
    final playlists = libraryBloc.state.playlists;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Add to Playlist',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No playlists yet. Create one from the Playlists tab.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              else
                ...playlists.map((pl) => ListTile(
                      leading: const Icon(Icons.queue_music_rounded,
                          color: AppTheme.textSecondary),
                      title: Text(pl.name,
                          style: const TextStyle(color: AppTheme.textPrimary)),
                      onTap: () {
                        libraryBloc
                            .add(LibraryAddSongToPlaylist(pl.id, song.id));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Added to ${pl.name}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showSpeedSheet(BuildContext context, PlayerStateEntity state) {
    final accent  = Theme.of(context).colorScheme.primary;
    const speeds  = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    const labels  = ['0.5×', '0.75×', '1×', '1.25×', '1.5×', '2×'];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                // Header
                Row(children: [
                  Icon(Icons.speed_rounded, color: accent, size: 22),
                  const SizedBox(width: 10),
                  const Text('Playback Speed',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    )),
                  const Spacer(),
                  if (state.speed != 1.0)
                    TextButton(
                      onPressed: () {
                        context.read<PlayerBloc>().add(const PlayerSetSpeed(1.0));
                        Navigator.pop(context);
                      },
                      child: Text('Reset',
                          style: TextStyle(color: accent, fontSize: 13)),
                    ),
                ]),
                const SizedBox(height: 16),
                // Speed chips
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(speeds.length, (i) {
                    final spd      = speeds[i];
                    final lbl      = labels[i];
                    final isActive = (state.speed - spd).abs() < 0.01;
                    return GestureDetector(
                      onTap: () {
                        context.read<PlayerBloc>().add(PlayerSetSpeed(spd));
                        Navigator.pop(context);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 13),
                        decoration: BoxDecoration(
                          color: isActive
                              ? accent.withOpacity(0.18)
                              : AppTheme.bgSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive ? accent : Colors.white12,
                            width: isActive ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          lbl,
                          style: TextStyle(
                            color: isActive ? accent : AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showQueueSheet(BuildContext context, PlayerStateEntity state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: context.read<PlayerBloc>(),
        child: const _QueueSheet(),
      ),
    );
  }

  void _showSleepTimerSheet(BuildContext context, PlayerStateEntity state) {
    final accent = Theme.of(context).colorScheme.primary;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Icon(Icons.bedtime_rounded, color: accent, size: 22),
                  const SizedBox(width: 10),
                  const Text('Sleep Timer',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      )),
                  const Spacer(),
                  if (state.sleepTimerMinutes != null)
                    TextButton(
                      onPressed: () {
                        context.read<PlayerBloc>().add(const PlayerSetSleepTimer(null));
                        Navigator.pop(context);
                      },
                      child: Text('Cancel Timer',
                          style: TextStyle(color: accent, fontSize: 13)),
                    ),
                ]),
                const SizedBox(height: 8),
                if (state.sleepTimerMinutes != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '⏱ Active: ${state.sleepTimerMinutes} min remaining',
                      style: TextStyle(color: accent, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 4),
                ...([15, 30, 45, 60]).map((min) {
                  final isActive = state.sleepTimerMinutes == min;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: isActive
                              ? accent.withOpacity(0.15)
                              : Colors.transparent,
                          side: BorderSide(
                            color: isActive ? accent : Colors.white24,
                            width: isActive ? 1.5 : 1,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          context.read<PlayerBloc>().add(PlayerSetSleepTimer(min));
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Sleep timer set for $min minutes'),
                            backgroundColor: AppTheme.bgSurface,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            duration: const Duration(seconds: 2),
                          ));
                        },
                        child: Text(
                          '$min minutes',
                          style: TextStyle(
                            color: isActive ? accent : AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

} // end _NowPlayingScreenState

// ─────────────────────────────────────────────────────────────────────────────
// Queue Sheet — drag to reorder, swipe to remove
// ─────────────────────────────────────────────────────────────────────────────
class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerBloc, PlayerStateEntity>(
      builder: (context, state) {
        final accent = Theme.of(context).colorScheme.primary;
        final queue  = state.queue;

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (_, scrollCtrl) => Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  const Text(
                    'Queue',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${queue.length} songs',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.drag_handle_rounded,
                      color: AppTheme.textSecondary, size: 18),
                  const SizedBox(width: 4),
                  const Text('Drag to reorder',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ]),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: queue.isEmpty
                    ? const Center(
                        child: Text('Queue is empty',
                            style: TextStyle(color: AppTheme.textSecondary)),
                      )
                    : ReorderableListView.builder(
                        scrollController: scrollCtrl,
                        padding: const EdgeInsets.only(bottom: 20),
                        itemCount: queue.length,
                        onReorder: (oldIdx, newIdx) {
                          context
                              .read<PlayerBloc>()
                              .add(PlayerReorderQueue(oldIdx, newIdx));
                        },
                        itemBuilder: (_, i) {
                          final s         = queue[i];
                          final isCurrent = i == state.currentIndex;
                          return Dismissible(
                            key: ValueKey('${s.id}_$i'),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) {
                              context
                                  .read<PlayerBloc>()
                                  .add(PlayerRemoveFromQueue(i));
                            },
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Colors.redAccent.withOpacity(0.15),
                              child: const Icon(Icons.delete_outline_rounded,
                                  color: Colors.redAccent),
                            ),
                            child: ListTile(
                              key: ValueKey('tile_${s.id}_$i'),
                              leading: Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? accent.withOpacity(0.15)
                                      : AppTheme.bgSurface,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  isCurrent
                                      ? Icons.equalizer_rounded
                                      : Icons.music_note_rounded,
                                  color: isCurrent
                                      ? accent
                                      : AppTheme.textSecondary,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrent
                                      ? accent
                                      : AppTheme.textPrimary,
                                  fontWeight: isCurrent
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                s.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11),
                              ),
                              trailing: ReorderableDragStartListener(
                                index: i,
                                child: const Icon(Icons.drag_handle_rounded,
                                    color: AppTheme.textSecondary),
                              ),
                              onTap: () {
                                context.read<PlayerBloc>().add(
                                    PlayerPlay(queue: queue, index: i));
                                Navigator.pop(context);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Premium Waveform ──
class _PremiumWaveform extends StatelessWidget {
  final bool isPlaying;
  final List<double> barHeights;
  final Color color;

  const _PremiumWaveform({
    required this.isPlaying,
    required this.barHeights,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barHeights.length, (i) {
          final h = isPlaying ? 36.0 * barHeights[i] : 6.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            width: 2.5,
            height: h.clamp(4.0, 36.0),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  color,
                  color.withOpacity(0.4),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Premium Slider ──
class _PremiumSlider extends StatelessWidget {
  final double value;
  final Color accent;
  final ValueChanged<double> onChanged;

  const _PremiumSlider({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: Colors.white12,
        thumbColor: Colors.white,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayColor: accent.withOpacity(0.15),
        trackHeight: 3,
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(value: value, onChanged: onChanged),
    );
  }
}

// ── Glass icon button ──

// ── Speed Button — shows current speed, tapping opens sheet ──
class _SpeedBtn extends StatelessWidget {
  final double speed;
  final VoidCallback onTap;

  const _SpeedBtn({required this.speed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDefault = (speed - 1.0).abs() < 0.01;
    final accent    = Theme.of(context).colorScheme.primary;
    final label     = isDefault
        ? '1×'
        : speed == speed.truncateToDouble()
            ? '${speed.toInt()}×'
            : '${speed}×';

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: isDefault
                  ? Colors.white.withOpacity(0.06)
                  : accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDefault
                    ? Colors.white.withOpacity(0.08)
                    : accent.withOpacity(0.5),
                width: isDefault ? 1 : 1.5,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isDefault ? AppTheme.textSecondary : accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('Speed',
              style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _GlassIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? label;

  const _GlassIconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(label!,
                style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500)),
          ]
        ],
      ),
    );
  }
}

// ── Control button ──
class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback onTap;

  const _ControlBtn({
    required this.icon,
    required this.size,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: color, size: size),
      ),
    );
  }
}

// ── Particle Painter ──
class _ParticlePainter extends CustomPainter {
  final double progress;
  final Color color;

  _ParticlePainter(this.progress, this.color);

  static final _particles = List.generate(14, (i) {
    final rng = Random(i * 7 + 3);
    return _Particle(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      size: 1.5 + rng.nextDouble() * 2.5,
      speed: 0.04 + rng.nextDouble() * 0.08,
      phase: rng.nextDouble(),
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final t = (progress + p.phase) % 1.0;
      final x = (p.x + sin(t * 2 * pi) * 0.08) * size.width;
      final y = (p.y - t * p.speed * 3) % 1.0 * size.height;
      final opacity = sin(t * pi).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(x, y),
        p.size,
        Paint()..color = color.withOpacity(0.25 * opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}

class _Particle {
  final double x, y, size, speed, phase;
  const _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
  });
}
