import 'package:hive/hive.dart';
import '../../domain/entities/playlist_entity.dart';

part 'playlist_model.g.dart';

@HiveType(typeId: 1)
class PlaylistModel extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String name;

  @HiveField(2)
  String? description;

  @HiveField(3)
  late List<int> songIds;

  @HiveField(4)
  late int typeIndex; // PlaylistType.index

  @HiveField(5)
  late DateTime createdAt;

  @HiveField(6)
  DateTime? updatedAt;

  PlaylistModel();

  factory PlaylistModel.fromEntity(PlaylistEntity e) => PlaylistModel()
    ..id = e.id
    ..name = e.name
    ..description = e.description
    ..songIds = List<int>.from(e.songIds)
    ..typeIndex = e.type.index
    ..createdAt = e.createdAt
    ..updatedAt = e.updatedAt;

  PlaylistEntity toEntity() => PlaylistEntity(
        id: id,
        name: name,
        description: description,
        songIds: List<int>.from(songIds),
        type: PlaylistType.values[typeIndex],
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
