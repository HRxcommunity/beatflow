import 'dart:async';
import 'package:on_audio_query/on_audio_query.dart';
import '../domain/entities/song_entity.dart';

class ScanProgress {
  final int scanned;
  final int total;
  final String currentFile;

  const ScanProgress({
    required this.scanned,
    required this.total,
    required this.currentFile,
  });

  double get percentage => total == 0 ? 0 : scanned / total;
}

class MusicScannerService {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final StreamController<ScanProgress> _progressController =
      StreamController<ScanProgress>.broadcast();

  Stream<ScanProgress> get progressStream => _progressController.stream;

  Future<List<SongEntity>> scanDeviceSongs({bool filterShortClips = true}) async {
    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final total = songs.length;
    final result = <SongEntity>[];

    for (var i = 0; i < songs.length; i++) {
      final s = songs[i];

      _progressController.add(ScanProgress(
        scanned: i + 1,
        total: total,
        currentFile: s.title,
      ));

      // Filter very short clips (ringtones etc.)
      if (filterShortClips && (s.duration ?? 0) < 30000) continue;

      // Skip if file path is null
      if (s.data == null) continue;

      result.add(SongEntity(
        id: s.id,
        title: s.title,
        artist: s.artist ?? 'Unknown Artist',
        album: s.album ?? 'Unknown Album',
        albumArtist: s.artist ?? 'Unknown Artist',
        duration: s.duration ?? 0,
        data: s.data!,
        folderPath: _extractFolder(s.data!),
        dateAdded: s.dateAdded != null
            ? DateTime.fromMillisecondsSinceEpoch(s.dateAdded! * 1000)
            : null,
      ));
    }

    return result;
  }

  String? _extractFolder(String path) {
    final idx = path.lastIndexOf('/');
    return idx > 0 ? path.substring(0, idx) : null;
  }

  void dispose() {
    _progressController.close();
  }
}
