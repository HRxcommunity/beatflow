// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'song_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SongModelAdapter extends TypeAdapter<SongModel> {
  @override
  final int typeId = 0;

  @override
  SongModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SongModel()
      ..id = fields[0] as int
      ..title = fields[1] as String
      ..artist = fields[2] as String
      ..album = fields[3] as String
      ..albumArtist = fields[4] as String
      ..duration = fields[5] as int
      ..data = fields[6] as String
      ..folderPath = fields[7] as String?
      ..dateAdded = fields[8] as DateTime?
      ..playCount = fields[9] as int
      ..isFavorite = fields[10] as bool
      ..lastPlayed = fields[11] as DateTime?
      ..isVideo = fields[12] as bool? ?? false;
  }

  @override
  void write(BinaryWriter writer, SongModel obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.artist)
      ..writeByte(3)
      ..write(obj.album)
      ..writeByte(4)
      ..write(obj.albumArtist)
      ..writeByte(5)
      ..write(obj.duration)
      ..writeByte(6)
      ..write(obj.data)
      ..writeByte(7)
      ..write(obj.folderPath)
      ..writeByte(8)
      ..write(obj.dateAdded)
      ..writeByte(9)
      ..write(obj.playCount)
      ..writeByte(10)
      ..write(obj.isFavorite)
      ..writeByte(11)
      ..write(obj.lastPlayed)
      ..writeByte(12)
      ..write(obj.isVideo);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
