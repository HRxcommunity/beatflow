import 'package:hive/hive.dart';
import '../../domain/entities/song_entity.dart';

part 'song_model.g.dart';

@HiveType(typeId: 0)
class SongModel extends HiveObject {
  @HiveField(0)
  late int id;

  @HiveField(1)
  late String title;

  @HiveField(2)
  late String artist;

  @HiveField(3)
  late String album;

  @HiveField(4)
  late String albumArtist;

  @HiveField(5)
  late int duration;

  @HiveField(6)
  late String data;

  @HiveField(7)
  String? folderPath;

  @HiveField(8)
  DateTime? dateAdded;

  @HiveField(9)
  int playCount = 0;

  @HiveField(10)
  bool isFavorite = false;

  @HiveField(11)
  DateTime? lastPlayed;

  SongModel();

  factory SongModel.fromEntity(SongEntity e) => SongModel()
    ..id = e.id
    ..title = e.title
    ..artist = e.artist
    ..album = e.album
    ..albumArtist = e.albumArtist
    ..duration = e.duration
    ..data = e.data
    ..folderPath = e.folderPath
    ..dateAdded = e.dateAdded
    ..playCount = e.playCount
    ..isFavorite = e.isFavorite
    ..lastPlayed = e.lastPlayed;

  SongEntity toEntity() => SongEntity(
        id: id,
        title: title,
        artist: artist,
        album: album,
        albumArtist: albumArtist,
        duration: duration,
        data: data,
        folderPath: folderPath,
        dateAdded: dateAdded,
        playCount: playCount,
        isFavorite: isFavorite,
        lastPlayed: lastPlayed,
      );
}
