import 'package:equatable/equatable.dart';

class SongEntity extends Equatable {
  final int id;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final int duration; // milliseconds
  final String data; // file path
  final String? folderPath;
  final DateTime? dateAdded;
  final int playCount;
  final bool isFavorite;
  final DateTime? lastPlayed;

  const SongEntity({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.duration,
    required this.data,
    this.folderPath,
    this.dateAdded,
    this.playCount = 0,
    this.isFavorite = false,
    this.lastPlayed,
  });

  SongEntity copyWith({
    int? id,
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    int? duration,
    String? data,
    String? folderPath,
    DateTime? dateAdded,
    int? playCount,
    bool? isFavorite,
    DateTime? lastPlayed,
  }) {
    return SongEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      duration: duration ?? this.duration,
      data: data ?? this.data,
      folderPath: folderPath ?? this.folderPath,
      dateAdded: dateAdded ?? this.dateAdded,
      playCount: playCount ?? this.playCount,
      isFavorite: isFavorite ?? this.isFavorite,
      lastPlayed: lastPlayed ?? this.lastPlayed,
    );
  }

  String get durationFormatted {
    final d = Duration(milliseconds: duration);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  List<Object?> get props => [id, title, artist, album, duration, data, isFavorite, playCount];
}
