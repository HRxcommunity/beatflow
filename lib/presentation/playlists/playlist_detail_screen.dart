import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../songs/library_bloc.dart';
import '../player/player_bloc.dart';
import '../../widgets/common/song_tile.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final String playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, state) {
        final playlist = state.playlists.where((p) => p.id == playlistId).firstOrNull;
        if (playlist == null) {
          return const Scaffold(body: Center(child: Text('Playlist not found')));
        }

        final songs = playlist.getSongs(state.allSongs);

        return Scaffold(
          appBar: AppBar(
            title: Text(playlist.name),
            actions: [
              if (songs.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () => context.read<PlayerBloc>().add(
                    PlayerPlay(queue: songs, index: 0),
                  ),
                ),
            ],
          ),
          body: songs.isEmpty
              ? const Center(child: Text('No songs in this playlist'))
              : ReorderableListView.builder(
                  itemCount: songs.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    context.read<LibraryBloc>().add(
                      LibraryReorderPlaylist(playlistId, oldIndex, newIndex),
                    );
                  },
                  itemBuilder: (ctx, i) {
                    final song = songs[i];
                    final playerState = ctx.watch<PlayerBloc>().state;
                    final isCurrentSong = playerState.currentSong?.id == song.id;
                    return SongTile(
                      key: ValueKey(song.id),
                      song: song,
                      isPlaying: isCurrentSong,
                      trailing: const Icon(Icons.drag_handle),
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
        );
      },
    );
  }
}
