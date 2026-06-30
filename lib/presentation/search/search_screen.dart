import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:go_router/go_router.dart';
import '../songs/library_bloc.dart';
import '../player/player_bloc.dart';
import '../../domain/entities/song_entity.dart';
import '../../widgets/common/song_artwork_widget.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          focusNode: _focus,
          autofocus: true,
          onChanged: (q) {
            setState(() => _query = q);
            context.read<LibraryBloc>().add(LibrarySearch(q));
          },
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Songs, artists, albums...',
            border: InputBorder.none,
            hintStyle: TextStyle(
              fontFamily: 'Poppins',
              color: cs.onSurface.withOpacity(0.4),
            ),
            filled: false,
          ),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              onPressed: () {
                _ctrl.clear();
                setState(() => _query = '');
                context.read<LibraryBloc>().add(const LibrarySearch(''));
              },
            ),
        ],
      ),
      body: BlocBuilder<LibraryBloc, LibraryState>(
        builder: (context, state) {
          if (_query.isEmpty) {
            return _EmptySearchState();
          }

          if (state.filteredSongs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off_rounded,
                      size: 64, color: cs.onSurface.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text(
                    'No results for "$_query"',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      color: cs.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            );
          }

          final songs = state.filteredSongs;
          final albums = state.albums.entries
              .where((e) =>
                  e.key.toLowerCase().contains(_query.toLowerCase()))
              .take(5)
              .toList();
          final artists = state.artists.entries
              .where((e) =>
                  e.key.toLowerCase().contains(_query.toLowerCase()))
              .take(5)
              .toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              // Artists
              if (artists.isNotEmpty) ...[
                _SearchSectionHeader('Artists (${artists.length})'),
                ...artists.map((e) => _ArtistSearchTile(
                      name: e.key,
                      songCount: e.value.length,
                      songs: e.value,
                    )),
                const SizedBox(height: 8),
              ],

              // Albums
              if (albums.isNotEmpty) ...[
                _SearchSectionHeader('Albums (${albums.length})'),
                SizedBox(
                  height: 150,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: albums.length,
                    itemBuilder: (ctx, i) {
                      final album = albums[i];
                      final first = album.value.first;
                      return GestureDetector(
                        onTap: () => context.push(
                          '/album/${Uri.encodeComponent(album.key)}',
                        ),
                        child: Container(
                          width: 110,
                          margin: const EdgeInsets.only(right: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SongArtworkWidget(
                                  songId: first.id,
                                  size: 110,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                album.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: cs.onSurface,
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

              // Songs
              if (songs.isNotEmpty) ...[
                _SearchSectionHeader('Songs (${songs.length})'),
                AnimationLimiter(
                  child: Column(
                    children: List.generate(songs.length, (i) {
                      final song = songs[i];
                      return AnimationConfiguration.staggeredList(
                        position: i,
                        duration: const Duration(milliseconds: 250),
                        child: SlideAnimation(
                          horizontalOffset: 20,
                          child: FadeInAnimation(
                            child: _SongSearchTile(
                              song: song,
                              query: _query,
                              onTap: () {
                                final pb = context.read<PlayerBloc>();
                                final isCurrentSong = pb.state.currentSong?.id == song.id;
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
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Recent searches hint
              Text(
                'Browse',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 16),

              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.5,
                children: [
                  _BrowseChip(
                    label: 'Songs',
                    icon: Icons.music_note_rounded,
                    color: cs.primary,
                  ),
                  _BrowseChip(
                    label: 'Albums',
                    icon: Icons.album_rounded,
                    color: Colors.orangeAccent,
                  ),
                  _BrowseChip(
                    label: 'Artists',
                    icon: Icons.people_rounded,
                    color: Colors.teal,
                  ),
                  _BrowseChip(
                    label: 'Favorites',
                    icon: Icons.favorite_rounded,
                    color: Colors.pinkAccent,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BrowseChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _BrowseChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchSectionHeader extends StatelessWidget {
  final String title;
  const _SearchSectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      ),
    );
  }
}

class _SongSearchTile extends StatelessWidget {
  final SongEntity song;
  final String query;
  final VoidCallback onTap;

  const _SongSearchTile({
    required this.song,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: SongArtworkWidget(
        songId: song.id,
        size: 48,
        borderRadius: 10,
      ),
      title: _HighlightedText(
        text: song.title,
        query: query,
        baseStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        highlightColor: cs.primary,
      ),
      subtitle: Text(
        song.artist,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          color: cs.onSurface.withOpacity(0.55),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        song.durationFormatted,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          color: cs.onSurface.withOpacity(0.4),
        ),
      ),
      onTap: onTap,
    );
  }
}

/// Highlights query within text
class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle baseStyle;
  final Color highlightColor;

  const _HighlightedText({
    required this.text,
    required this.query,
    required this.baseStyle,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return Text(text, style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final idx = lowerText.indexOf(lowerQuery);

    if (idx == -1) return Text(text, style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);

    return Text.rich(
      TextSpan(
        children: [
          if (idx > 0) TextSpan(text: text.substring(0, idx), style: baseStyle),
          TextSpan(
            text: text.substring(idx, idx + query.length),
            style: baseStyle.copyWith(
              color: highlightColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (idx + query.length < text.length)
            TextSpan(text: text.substring(idx + query.length), style: baseStyle),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _ArtistSearchTile extends StatelessWidget {
  final String name;
  final int songCount;
  final List<SongEntity> songs;

  const _ArtistSearchTile({
    required this.name,
    required this.songCount,
    required this.songs,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: SongArtworkWidget(
        songId: songs.first.id,
        size: 48,
        isCircle: true,
      ),
      title: Text(
        name,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        '$songCount songs',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          color: cs.onSurface.withOpacity(0.55),
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push('/artist/${Uri.encodeComponent(name)}'),
    );
  }
}
