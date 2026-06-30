import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../songs/library_bloc.dart';
import '../player/player_bloc.dart';
import '../settings/settings_bloc.dart';
import '../../widgets/common/song_artwork_widget.dart';
import '../../widgets/common/app_background.dart';
import '../../widgets/common/song_tile.dart';
import '../../core/theme/app_theme.dart';

class ArtistDetailScreen extends StatelessWidget {
  final String artistName;
  const ArtistDetailScreen({super.key, required this.artistName});

  @override
  Widget build(BuildContext context) {
    final hasBg = context.select<SettingsBloc, bool>(
      (b) => b.state.backgroundType == 1 && (b.state.backgroundImagePath?.isNotEmpty ?? false),
    );

    final screenContent = Scaffold(
      backgroundColor: hasBg ? Colors.transparent : AppTheme.bgDeep,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: hasBg
            ? AppTheme.bgCard.withOpacity(0.75)
            : AppTheme.bgCard.withOpacity(0.92),
        elevation: 0,
        // ✅ FIX: context.pop() works with GoRouter (Navigator.pop does not)
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
          onPressed: () => context.pop(),
        ),
        title: Text(
          artistName,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
            fontFamily: 'Poppins',
          ),
        ),
      ),
      body: BlocBuilder<LibraryBloc, LibraryState>(
        builder: (context, state) {
          final songs = state.artists[artistName] ?? [];

          // Group into albums
          final albumMap = <String, List>{}; 
          for (final s in songs) {
            albumMap.putIfAbsent(s.album, () => []).add(s);
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Artist header art ─────────────────────────────────────
              SliverToBoxAdapter(
                child: _ArtistHeaderBanner(
                  songs: songs,
                  artistName: artistName,
                ),
              ),

              // ── Play all button ────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        '${songs.length} songs',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: songs.isEmpty
                            ? null
                            : () => context.read<PlayerBloc>().add(
                                  PlayerPlay(queue: songs, index: 0),
                                ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Play All',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Albums section (horizontal scroll) ────────────────────
              if (albumMap.length > 1)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                        child: Text(
                          'Albums',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 160,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          itemCount: albumMap.length,
                          itemBuilder: (ctx, i) {
                            final album = albumMap.entries.elementAt(i);
                            final first = album.value.first;
                            return GestureDetector(
                              // ✅ FIX: ctx.push (not ctx.go) so back works
                              onTap: () => ctx.push(
                                '/album/${Uri.encodeComponent(album.key)}',
                                extra: album.value,
                              ),
                              child: Container(
                                width: 120,
                                margin: const EdgeInsets.only(right: 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: SongArtworkWidget(
                                        songId: first.id,
                                        size: 120,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      album.key,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${album.value.length} songs',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

              // ── All songs ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    'All Songs',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),

              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final song = songs[i];
                    final playerState = context.watch<PlayerBloc>().state;
                    final isCurrentSong = playerState.currentSong?.id == song.id;
                    return SongTile(
                      song: song,
                      isPlaying: isCurrentSong,
                      onTap: () {
                        final pb = context.read<PlayerBloc>();
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
                  childCount: songs.length,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
    );

    if (hasBg) return AppBackground(child: screenContent);
    return screenContent;
  }
}

// ── Artist Header Banner ─────────────────────────────────────────────────────

class _ArtistHeaderBanner extends StatelessWidget {
  final List songs;
  final String artistName;

  const _ArtistHeaderBanner({
    required this.songs,
    required this.artistName,
  });

  @override
  Widget build(BuildContext context) {
    final firstSong = songs.isNotEmpty ? songs.first : null;
    final size = MediaQuery.of(context).size;

    return SizedBox(
      height: 220,
      width: size.width,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred art background
          if (firstSong != null)
            Opacity(
              opacity: 0.35,
              child: SongArtworkWidget(
                songId: firstSong.id,
                size: size.width,
                borderRadius: 0,
              ),
            ),

          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppTheme.bgDeep.withOpacity(0.7),
                  AppTheme.bgDeep,
                ],
                stops: const [0, 0.5, 1],
              ),
            ),
          ),

          // Artist icon + name at bottom
          Positioned(
            bottom: 16,
            left: 16,
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.bgCard,
                    border: Border.all(color: Colors.white24, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white60,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      artistName,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'Artist',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
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
}
