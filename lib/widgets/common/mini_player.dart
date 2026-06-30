import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../domain/entities/player_state_entity.dart';
import '../../presentation/player/player_bloc.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import 'song_artwork_widget.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> with TickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _glowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerBloc, PlayerStateEntity>(
      builder: (context, state) {
        if (state.currentSong == null) return const SizedBox.shrink();

        _slideCtrl.forward();

        final song = state.currentSong!;
        final accent = Theme.of(context).colorScheme.primary;

        return SlideTransition(
          position: _slideAnim,
          child: GestureDetector(
            onTap: () => context.push(AppRouter.nowPlaying),
            child: AnimatedBuilder(
              animation: _glowAnim,
              builder: (_, child) => Container(
                height: 70,
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: accent.withOpacity(0.15 + 0.1 * _glowAnim.value),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.12 * _glowAnim.value),
                      blurRadius: 20,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: child,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    // Progress bar at bottom
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 2,
                        width: MediaQuery.of(context).size.width *
                            state.progress.clamp(0.0, 1.0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            accent,
                            accent.withOpacity(0.5),
                          ]),
                        ),
                      ),
                    ),
                    // Content
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          // Art
                          SongArtworkWidget(
                            songId: song.id,
                            size: 44,
                            borderRadius: 10,
                          ),
                          const SizedBox(width: 12),
                          // Title + artist
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                    )),
                                Text(song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    )),
                              ],
                            ),
                          ),
                          // Controls
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white70),
                            iconSize: 24,
                            onPressed: () => context.read<PlayerBloc>().add(PlayerPrevious()),
                          ),
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withOpacity(0.9),
                            ),
                            child: state.isLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: Icon(
                                      state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                    ),
                                    iconSize: 22,
                                    onPressed: () {
                                      if (state.isPlaying) {
                                        context.read<PlayerBloc>().add(PlayerPause());
                                      } else {
                                        context.read<PlayerBloc>().add(PlayerResume());
                                      }
                                    },
                                  ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, color: Colors.white70),
                            iconSize: 24,
                            onPressed: () => context.read<PlayerBloc>().add(PlayerNext()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
