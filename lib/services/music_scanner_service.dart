import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../domain/entities/song_entity.dart';

// ── Channel that calls MainActivity.queryVideoFiles() ────────────────────
const _kMediaChannel = MethodChannel('com.beatflow.app/media');

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

  // ── Scan audio files (MP3, FLAC, AAC, etc.) ─────────────────
  Future<List<SongEntity>> scanDeviceSongs({bool filterShortClips = true}) async {
    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final total  = songs.length;
    final result = <SongEntity>[];

    for (var i = 0; i < songs.length; i++) {
      final s = songs[i];

      _progressController.add(ScanProgress(
        scanned: i + 1,
        total: total,
        currentFile: s.title,
      ));

      if (filterShortClips && (s.duration ?? 0) < 30000) continue;
      if (s.data == null) continue;

      // Skip temp Cloudinary/CDN cached files — they appear as gibberish
      // names from Together session uploads stored in app's cache dir.
      final filePath = s.data!;
      if (_isCachedTempFile(filePath)) continue;

      result.add(SongEntity(
        id:          s.id,
        title:       s.title,
        artist:      s.artist ?? 'Unknown Artist',
        album:       s.album ?? 'Unknown Album',
        albumArtist: s.artist ?? 'Unknown Artist',
        duration:    s.duration ?? 0,
        data:        filePath,
        folderPath:  _extractFolder(filePath),
        dateAdded:   s.dateAdded != null
            ? DateTime.fromMillisecondsSinceEpoch(s.dateAdded! * 1000)
            : null,
        isVideo:     false,
      ));
    }

    return result;
  }

  // ── Scan video files (MP4) via Android MediaStore ────────────
  // Uses MethodChannel → MainActivity.queryVideoFiles() which calls
  // Android's MediaStore.Video.Media — works on all Android versions
  // and respects READ_MEDIA_VIDEO permission (already in manifest).
  Future<List<SongEntity>> scanDeviceVideos() async {
    try {
      final jsonStr = await _kMediaChannel.invokeMethod<String>('queryVideos');
      if (jsonStr == null || jsonStr.isEmpty) return [];

      final list   = jsonDecode(jsonStr) as List<dynamic>;
      final result = <SongEntity>[];

      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final data = map['data'] as String? ?? '';
        if (data.isEmpty) continue;

        // BUG-VID-META FIX: sanitize <unknown> strings from Android MediaStore
        // (already sanitized in MainActivity.kt, but guard here for safety).
        final rawArtist = map['artist'] as String? ?? '';
        final cleanArtist = _sanitizeMediaStoreField(rawArtist, 'Unknown Artist');
        final rawAlbum  = map['album']  as String? ?? '';
        final cleanAlbum  = _sanitizeMediaStoreField(rawAlbum,  'Videos');
        final rawTitle  = map['title']  as String? ?? '';
        final cleanTitle  = _sanitizeMediaStoreField(rawTitle,  'Video');

        result.add(SongEntity(
          id:          (map['id'] as num).toInt(),
          title:       cleanTitle,
          artist:      cleanArtist,
          album:       cleanAlbum,
          albumArtist: cleanArtist,
          duration:    (map['duration'] as num? ?? 0).toInt(),
          data:        data,
          folderPath:  _extractFolder(data),
          dateAdded:   map['dateAdded'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  (map['dateAdded'] as num).toInt() * 1000)
              : null,
          isVideo:     true,
        ));
      }

      debugPrint('[Scanner] Found ${result.length} video files via MediaStore');
      return result;
    } catch (e) {
      // Non-fatal — app works without video support
      debugPrint('[Scanner] Video scan error: $e');
      return [];
    }
  }

  // ── Scan both audio + video ──────────────────────────────────
  Future<List<SongEntity>> scanAll({bool filterShortClips = true}) async {
    final audio  = await scanDeviceSongs(filterShortClips: filterShortClips);
    final videos = await scanDeviceVideos();
    return [...audio, ...videos];
  }

  /// Returns true for files that are temp/cache — Cloudinary CDN chunks,
  /// yt-dlp downloads stored in app data, etc.
  /// These show as gibberish names like "LWvXVRWUM0zs1ZeEwRFZ..." in the UI.
  bool _isCachedTempFile(String path) {
    // App internal data / cache directories
    if (path.contains('/data/data/') ||
        path.contains('/data/user/') ||
        path.contains('/cache/') ||
        path.contains('/code_cache/') ||
        path.contains('/.cache/')) return true;

    // Cloudinary CDN filenames are long random Base64-like strings (>20 chars)
    // with no spaces. Real song files have normal names.
    final filename = path.split('/').last;
    final nameWithoutExt = filename.contains('.')
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;

    // Heuristic: a filename that's >28 chars and looks like Base64 (no spaces,
    // no dashes except at start, only alphanumeric + some special chars)
    // is likely a CDN temp file.
    if (nameWithoutExt.length > 28 &&
        RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(nameWithoutExt)) {
      return true;
    }

    return false;
  }

  /// Sanitize Android MediaStore fields that may contain "<unknown>" literals.
  /// Android writes the literal string "<unknown>" (with angle brackets) when
  /// embedded metadata is missing. Replace with [fallback].
  String _sanitizeMediaStoreField(String raw, String fallback) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return fallback;
    if (trimmed == '<unknown>') return fallback;
    // Generic angle-bracket sentinel: <anything>
    if (trimmed.startsWith('<') && trimmed.endsWith('>') && trimmed.length < 30) {
      return fallback;
    }
    return trimmed;
  }

  String? _extractFolder(String path) {
    final idx = path.lastIndexOf('/');
    return idx > 0 ? path.substring(0, idx) : null;
  }

  void dispose() {
    _progressController.close();
  }
}
