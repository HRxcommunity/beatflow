// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SettingsModelAdapter extends TypeAdapter<SettingsModel> {
  @override
  final int typeId = 2;

  @override
  SettingsModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SettingsModel()
      ..themeMode = fields[0] as int
      ..accentColorIndex = fields[1] as int
      ..eqEnabled = fields[2] as bool
      ..eqBands = (fields[3] as List).cast<double>()
      ..eqPreset = fields[4] as String
      ..bassBoost = fields[5] as double
      ..virtualizer = fields[6] as double
      ..reverb = fields[7] as double
      ..loudnessEnhancer = fields[8] as double
      ..filterShortClips = fields[9] as bool
      ..excludedFolders = (fields[10] as List).cast<String>()
      ..showAlbumArtInNotification = fields[11] as bool
      ..gaplessPlayback = fields[12] as bool
      ..backgroundType = fields[13] as int
      ..backgroundImagePath = fields[14] as String?
      ..backgroundDimOpacity = fields[15] as double
      ..songCardOpacity = fields[16] as double
      ..songCardColorIndex = fields[17] as int
      ..songCardColorValue = fields[18] as int
      ..togetherBgType = fields[19] as int
      ..togetherBgImagePath = fields[20] as String?
      ..togetherBgDimOpacity = fields[21] as double
      ..groqApiKey = fields[22] as String? ?? '';
  }

  @override
  void write(BinaryWriter writer, SettingsModel obj) {
    writer
      ..writeByte(23)
      ..writeByte(0)
      ..write(obj.themeMode)
      ..writeByte(1)
      ..write(obj.accentColorIndex)
      ..writeByte(2)
      ..write(obj.eqEnabled)
      ..writeByte(3)
      ..write(obj.eqBands)
      ..writeByte(4)
      ..write(obj.eqPreset)
      ..writeByte(5)
      ..write(obj.bassBoost)
      ..writeByte(6)
      ..write(obj.virtualizer)
      ..writeByte(7)
      ..write(obj.reverb)
      ..writeByte(8)
      ..write(obj.loudnessEnhancer)
      ..writeByte(9)
      ..write(obj.filterShortClips)
      ..writeByte(10)
      ..write(obj.excludedFolders)
      ..writeByte(11)
      ..write(obj.showAlbumArtInNotification)
      ..writeByte(12)
      ..write(obj.gaplessPlayback)
      ..writeByte(13)
      ..write(obj.backgroundType)
      ..writeByte(14)
      ..write(obj.backgroundImagePath)
      ..writeByte(15)
      ..write(obj.backgroundDimOpacity)
      ..writeByte(16)
      ..write(obj.songCardOpacity)
      ..writeByte(17)
      ..write(obj.songCardColorIndex)
      ..writeByte(18)
      ..write(obj.songCardColorValue)
      ..writeByte(19)
      ..write(obj.togetherBgType)
      ..writeByte(20)
      ..write(obj.togetherBgImagePath)
      ..writeByte(21)
      ..write(obj.togetherBgDimOpacity)
      ..writeByte(22)
      ..write(obj.groqApiKey);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
