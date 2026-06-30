import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../domain/entities/song_entity.dart';
import '../../core/theme/app_theme.dart';
import '../../presentation/settings/settings_bloc.dart';
import '../../widgets/common/app_background.dart';
import '../player/player_bloc.dart';
import '../../widgets/common/song_tile.dart';

class AlbumDetailScreen extends StatelessWidget {
  final String albumName;
  final List<SongEntity> songs;

  const AlbumDetailScreen({super.key, required this.albumName, required this.songs});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final hasBg = context.select<SettingsBloc, bool>(
      (b) => b.state.backgroundType == 1 && (b.state.backgroundImagePath?.isNotEmpty ?? false),
    );

    // Build the main screen content
    final screenContent = Scaffold(
      backgroundColor: hasBg ? Colors.transparent : AppTheme.bgDeep,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: hasBg
            ? AppTheme.bgCard.withOpacity(0.75)
            : AppTheme.bgCard.withOpacity(0.92),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
          onPressed: () => context.pop(),
        ),
        title: Text(
          albumName,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        actions: [
          if (songs.isNotEmpty)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.play_arrow_rounded, color: accent, size: 22),
              ),
              onPressed: () => context.read<PlayerBloc>().add(
                PlayerPlay(queue: songs, index: 0),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Album header card
            Container(
              height: 180,
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withOpacity(0.25),
                    AppTheme.bgCard,
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        accent.withOpacity(0.35),
                        AppTheme.bgSurface,
                      ]),
                    ),
                    child: Icon(Icons.album_rounded, size: 44, color: accent.withOpacity(0.8)),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      albumName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${songs.length} song${songs.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Song list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: songs.length,
                itemBuilder: (ctx, i) {
                  final playerState = ctx.watch<PlayerBloc>().state;
                  final isCurrentSong = playerState.currentSong?.id == songs[i].id;
                  return SongTile(
                    song: songs[i],
                    isPlaying: isCurrentSong,
                    onTap: () {
                      final pb = ctx.read<PlayerBloc>();
                      if (isCurrentSong) {
                        if (pb.state.isPlaying) {
                          pb.add(PlayerPause());
                        } else {
                          pb.add(PlayerResume());
                        }
                      } else {
                        pb.add(PlayerPlay(queue: songs, index: i));
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    // Wrap with background if user has set one
    if (hasBg) {
      return AppBackground(child: screenContent);
    }
    return screenContent;
  }
}
