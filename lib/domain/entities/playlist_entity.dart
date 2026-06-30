import 'package:equatable/equatable.dart';
import 'song_entity.dart';

enum PlaylistType { user, recentlyPlayed, mostPlayed, favorites }

class PlaylistEntity extends Equatable {
  final String id;
  final String name;
  final String? description;
  final List<int> songIds;
  final PlaylistType type;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const PlaylistEntity({
    required this.id,
    required this.name,
    this.description,
    required this.songIds,
    this.type = PlaylistType.user,
    required this.createdAt,
    this.updatedAt,
  });

  PlaylistEntity copyWith({
    String? id,
    String? name,
    String? description,
    List<int>? songIds,
    PlaylistType? type,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PlaylistEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      songIds: songIds ?? this.songIds,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  List<SongEntity> getSongs(List<SongEntity> allSongs) {
    final map = {for (final s in allSongs) s.id: s};
    return songIds.map((id) => map[id]).whereType<SongEntity>().toList();
  }

  @override
  List<Object?> get props => [id, name, songIds, type];
}
