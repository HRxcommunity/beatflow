// lib/features/downloader/downloader_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:media_scanner/media_scanner.dart';
import 'models/download_item.dart';
import 'download_history_service.dart';

// Cobalt API — free, open-source, no key needed
// Supports: YouTube, Instagram, TikTok, Twitter/X, Reddit,
//           Pinterest, Vimeo, Dailymotion, Soundcloud, Twitch clips
const String _kCobaltApi = 'https://api.cobalt.tools/';

// Max simultaneous downloads
const int _kMaxConcurrent = 3;

// ── Platform detection ─────────────────────────────────────────────
SourcePlatform detectPlatform(String url) {
  final u = url.toLowerCase();
  if (u.contains('youtube.com') || u.contains('youtu.be'))
    return SourcePlatform.youtube;
  if (u.contains('instagram.com'))  return SourcePlatform.instagram;
  if (u.contains('tiktok.com'))     return SourcePlatform.tiktok;
  if (u.contains('twitter.com') || u.contains('x.com'))
    return SourcePlatform.twitter;
  if (u.contains('facebook.com') || u.contains('fb.watch'))
    return SourcePlatform.facebook;
  if (u.contains('reddit.com') || u.contains('redd.it'))
    return SourcePlatform.reddit;
  if (u.contains('vimeo.com'))       return SourcePlatform.vimeo;
  if (u.contains('dailymotion.com')) return SourcePlatform.dailymotion;
  // Direct video URL
  const directExts = ['.mp4', '.mkv', '.webm', '.avi', '.mov',
                      '.mp3', '.m4a', '.ogg', '.wav', '.flac'];
  if (directExts.any((ext) => u.split('?').first.endsWith(ext)))
    return SourcePlatform.direct;
  return SourcePlatform.unknown;
}

// ── Main service ───────────────────────────────────────────────────
class UniversalDownloaderService {
  static final instance = UniversalDownloaderService._();
  UniversalDownloaderService._();

  final _yt   = YoutubeExplode();
  final _dio  = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 30),
  ));
  final _uuid = const Uuid();

  // Active cancel tokens — key: downloadItem.id
  final Map<String, CancelToken> _cancelTokens = {};

  // Download queue (active count tracker)
  int _activeCount = 0;
  final List<_QueuedDownload> _queue = [];

  // Progress stream
  final _progressCtrl = StreamController<DownloadItem>.broadcast();
  Stream<DownloadItem> get progressStream => _progressCtrl.stream;

  // ── Step A: Fetch video info ────────────────────────────────────
  Future<VideoInfo> fetchVideoInfo(String url) async {
    final platform = detectPlatform(url);
    return switch (platform) {
      SourcePlatform.youtube => _fetchYouTubeInfo(url),
      SourcePlatform.direct  => _fetchDirectInfo(url),
      _                      => _fetchViaCobalt(url, platform),
    };
  }

  // ── YouTube via youtube_explode_dart + Cobalt for 1080p ─────────
  Future<VideoInfo> _fetchYouTubeInfo(String url) async {
    final video    = await _yt.videos.get(url);
    final manifest = await _yt.videos.streamsClient.getManifest(url);
    final qualities = <DownloadQualityOption>[];

    // ── Muxed streams (video + audio, usually up to 720p) ─────────
    for (final s in manifest.muxed.sortByVideoQuality()) {
      qualities.add(DownloadQualityOption(
        label        : '${s.videoResolution.height}p Muxed '
            '(${_fmtSize(s.size.totalBytes)})',
        url          : s.url.toString(),
        fileSizeBytes: s.size.totalBytes,
        isAudioOnly  : false,
        mimeType     : 'video/mp4',
        fileExtension: 'mp4',
      ));
    }

    // BUG-DL02 FIX: Cobalt se 1080p aur 720p try karo.
    // yt_explode muxed sirf 720p tak deta hai (YouTube muxed streams mein
    // 1080p nahi hota). Cobalt server-side merge karta hai isliye 1080p
    // bhi deta hai aur India CGNAT ke liye bhi better hai (proxied).
    for (final q in ['1080', '720']) {
      // Skip if we already have this quality from muxed streams
      final already = qualities.any(
          (opt) => opt.label.startsWith('${q}p'));
      if (already) continue;
      try {
        final cobaltUrl = await _callCobaltApi(
            url: url, videoQuality: q, downloadMode: 'auto');
        if (cobaltUrl != null) {
          qualities.add(DownloadQualityOption(
            label        : '${q}p HD (Cobalt)',
            url          : cobaltUrl,
            isAudioOnly  : false,
            mimeType     : 'video/mp4',
            fileExtension: 'mp4',
          ));
        }
      } catch (_) {}
    }

    // ── Audio only (M4A preferred, highest bitrate) ───────────────
    final audioStreams = manifest.audioOnly.toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    for (final s in audioStreams) {
      if (s.codec.mimeType.contains('mp4') ||
          s.codec.mimeType.contains('m4a')) {
        qualities.add(DownloadQualityOption(
          label        : 'Audio M4A '
              '${(s.bitrate.bitsPerSecond / 1000).round()}kbps '
              '(${_fmtSize(s.size.totalBytes)})',
          url          : s.url.toString(),
          fileSizeBytes: s.size.totalBytes,
          isAudioOnly  : true,
          mimeType     : 'audio/mp4',
          fileExtension: 'm4a',
        ));
        break;
      }
    }

    // Sort: highest resolution first, audio last
    qualities.sort((a, b) {
      if (a.isAudioOnly != b.isAudioOnly) return a.isAudioOnly ? 1 : -1;
      final aRes = int.tryParse(
              RegExp(r'(\d+)p').firstMatch(a.label)?.group(1) ?? '0') ??
          0;
      final bRes = int.tryParse(
              RegExp(r'(\d+)p').firstMatch(b.label)?.group(1) ?? '0') ??
          0;
      return bRes.compareTo(aRes);
    });

    return VideoInfo(
      title       : video.title,
      author      : video.author,
      thumbnailUrl: video.thumbnails.highResUrl,
      platform    : SourcePlatform.youtube,
      durationSecs: video.duration?.inSeconds ?? 0,
      qualities   : qualities,
    );
  }

  // ── Cobalt API for other platforms ─────────────────────────────
  Future<VideoInfo> _fetchViaCobalt(
      String url, SourcePlatform platform) async {
    final qualities = <DownloadQualityOption>[];

    // BUG-DL01 FIX: break hata diya — sab 4 qualities try karo
    // Cobalt har quality ke liye best available stream deta hai
    for (final q in ['1080', '720', '480', '360']) {
      try {
        final cobaltUrl = await _callCobaltApi(
          url: url, videoQuality: q, downloadMode: 'auto');
        if (cobaltUrl != null) {
          qualities.add(DownloadQualityOption(
            label        : '${q}p',
            url          : cobaltUrl,
            isAudioOnly  : false,
            mimeType     : 'video/mp4',
            fileExtension: 'mp4',
          ));
          // NO break — collect all available qualities
        }
      } catch (_) {}
    }

    // Audio only
    try {
      final audioUrl = await _callCobaltApi(
        url: url, downloadMode: 'audio', audioFormat: 'mp3');
      if (audioUrl != null) {
        qualities.add(DownloadQualityOption(
          label        : 'Audio Only MP3',
          url          : audioUrl,
          isAudioOnly  : true,
          mimeType     : 'audio/mpeg',
          fileExtension: 'mp3',
        ));
      }
    } catch (_) {}

    if (qualities.isEmpty) {
      throw Exception(
        'Is URL se video nahi mili.\n'
        '• URL correct hai?\n'
        '• Private video/reel to nahi?\n'
        '• Internet connection check karo.',
      );
    }

    // BUG-DL01 FIX: deduplicate by URL — Cobalt sometimes returns the same
    // URL for multiple quality levels (platform only has one resolution)
    final seen   = <String>{};
    final unique = qualities.where((q) => seen.add(q.url)).toList();

    return VideoInfo(
      title       : _titleFromUrl(url) ?? platform.displayName,
      author      : platform.displayName,
      thumbnailUrl: null,
      platform    : platform,
      durationSecs: 0,
      qualities   : unique,
    );
  }

  // ── Direct video URL ────────────────────────────────────────────
  Future<VideoInfo> _fetchDirectInfo(String url) async {
    final uri  = Uri.parse(url);
    final name = uri.pathSegments.lastOrNull ?? 'video.mp4';
    final ext  = name.contains('.') ? name.split('.').last : 'mp4';
    final title = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.')).replaceAll('-', ' ')
        : name;
    return VideoInfo(
      title       : title,
      author      : uri.host,
      thumbnailUrl: null,
      platform    : SourcePlatform.direct,
      durationSecs: 0,
      qualities   : [
        DownloadQualityOption(
          label        : 'Direct Download',
          url          : url,
          isAudioOnly  : ['mp3','m4a','ogg','wav','flac'].contains(ext.toLowerCase()),
          mimeType     : 'video/mp4',
          fileExtension: ext.toLowerCase(),
        ),
      ],
    );
  }

  // ── Cobalt API call ─────────────────────────────────────────────
  Future<String?> _callCobaltApi({
    required String url,
    String videoQuality = '1080',
    String downloadMode = 'auto',  // 'auto' | 'audio' | 'mute'
    String audioFormat  = 'mp3',
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_kCobaltApi),
        headers: {
          'Accept'      : 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'url'          : url,
          'videoQuality' : videoQuality,
          'downloadMode' : downloadMode,
          'audioFormat'  : audioFormat,
          'filenameStyle': 'pretty',
          'allowH265'    : true,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data   = jsonDecode(response.body) as Map<String, dynamic>;
        final status = data['status'] as String?;

        if (status == 'error') {
          final code = data['error']?['code'] as String? ?? 'unknown';
          debugPrint('[Cobalt] error code: $code');
          return null;
        }

        // Single URL response
        if (data.containsKey('url')) return data['url'] as String?;

        // Picker response (Instagram carousel etc.)
        if (status == 'picker' && data.containsKey('picker')) {
          final picker = data['picker'] as List;
          if (picker.isNotEmpty) return picker.first['url'] as String?;
        }
      }
    } catch (e) {
      debugPrint('[Cobalt] call error: $e');
    }
    return null;
  }

  // ── Step B: Start download ──────────────────────────────────────
  Future<DownloadItem> startDownload({
    required String originalUrl,
    required VideoInfo info,
    required DownloadQualityOption quality,
  }) async {
    // Android storage permission
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      debugPrint('[Downloader] storage permission: $status');
      // Android 13+ doesn't need storage for Download folder — continue anyway
    }

    final item = DownloadItem(
      id             : _uuid.v4(),
      originalUrl    : originalUrl,
      title          : info.title,
      thumbnailUrl   : info.thumbnailUrl,
      // BUG-DL03 FIX: store the exact URL so retry doesn't re-fetch
      retryUrl       : quality.url,
      retryExt       : quality.fileExtension,
      platform       : info.platform,
      filePath       : '',
      status         : DownloadStatus.pending,
      progress       : 0.0,
      createdAt      : DateTime.now(),
      downloadType   : quality.isAudioOnly
          ? DownloadType.audioOnly : DownloadType.videoWithAudio,
      qualityLabel   : quality.label,
      fileSizeBytes  : quality.fileSizeBytes ?? 0,
      downloadedBytes: 0,
    );

    await DownloadHistoryService.instance.addItem(item);
    _progressCtrl.add(item);

    // Queue or start immediately
    if (_activeCount < _kMaxConcurrent) {
      _executeDownload(item, quality.url, quality.fileExtension);
    } else {
      _queue.add(_QueuedDownload(item, quality.url, quality.fileExtension));
    }

    return item;
  }

  // ── Execute download ────────────────────────────────────────────
  Future<void> _executeDownload(
      DownloadItem item, String downloadUrl, String ext) async {
    _activeCount++;
    try {
      final saveDir   = await _getSaveDirectory();
      final safeTitle = item.title
          .replaceAll(RegExp(r'[<>:"/\\|?*\n\r\t]'), '_')
          .substring(0, item.title.length.clamp(0, 50));
      final fileName  =
          '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final filePath  = '${saveDir.path}/$fileName';

      item.filePath = filePath;
      item.status   = DownloadStatus.downloading;
      await DownloadHistoryService.instance.updateItem(item);
      _progressCtrl.add(item);

      final cancelToken = CancelToken();
      _cancelTokens[item.id] = cancelToken;

      await _dio.download(
        downloadUrl,
        filePath,
        cancelToken : cancelToken,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 13) '
                'AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
            'Referer': _refererFor(item.platform),
          },
          responseType  : ResponseType.stream,
          followRedirects: true,
          maxRedirects  : 5,
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            item.downloadedBytes = received;
            item.fileSizeBytes   = total;
            item.progress        = received / total;
            _progressCtrl.add(item);
            DownloadHistoryService.instance.updateItem(item);
          }
        },
      );

      _cancelTokens.remove(item.id);

      // Scan so file appears in Gallery / Files app
      try {
        await MediaScanner.loadMedia(path: filePath);
      } catch (e) {
        debugPrint('[Downloader] media scan error: $e');
      }

      item.status      = DownloadStatus.completed;
      item.progress    = 1.0;
      item.completedAt = DateTime.now();
      await DownloadHistoryService.instance.updateItem(item);
      _progressCtrl.add(item);

      _showCompletionNotif(item);
    } on DioException catch (e) {
      _cancelTokens.remove(item.id);
      if (e.type == DioExceptionType.cancel) {
        item.status = DownloadStatus.cancelled;
      } else {
        item.status       = DownloadStatus.failed;
        item.errorMessage = _friendlyDioError(e);
      }
      await DownloadHistoryService.instance.updateItem(item);
      _progressCtrl.add(item);
    } catch (e) {
      _cancelTokens.remove(item.id);
      item.status       = DownloadStatus.failed;
      item.errorMessage = 'Download fail hua: $e';
      await DownloadHistoryService.instance.updateItem(item);
      _progressCtrl.add(item);
    } finally {
      _activeCount--;
      _processQueue();
    }
  }

  // ── Queue processing ────────────────────────────────────────────
  void _processQueue() {
    if (_queue.isNotEmpty && _activeCount < _kMaxConcurrent) {
      final next = _queue.removeAt(0);
      _executeDownload(next.item, next.url, next.ext);
    }
  }

  // ── Cancel ──────────────────────────────────────────────────────
  Future<void> cancelDownload(String itemId) async {
    _cancelTokens[itemId]?.cancel('User ne cancel kiya');
    // Also remove from queue if pending
    _queue.removeWhere((q) => q.item.id == itemId);
  }

  // ── Retry ───────────────────────────────────────────────────────
  Future<void> retryDownload(DownloadItem item) async {
    item.status       = DownloadStatus.downloading;
    item.progress     = 0.0;
    item.errorMessage = null;
    item.filePath     = '';
    await DownloadHistoryService.instance.updateItem(item);
    _progressCtrl.add(item);

    // BUG-DL03 FIX: use the stored URL + ext so we retry with the exact
    // same quality the user originally selected — no re-fetch, no always-
    // first-quality bug.
    if (item.retryUrl.isNotEmpty) {
      _executeDownload(item, item.retryUrl, item.retryExt);
      return;
    }

    // Fallback for older items that were saved before retryUrl was added:
    // re-fetch and pick the best available quality.
    try {
      final info    = await fetchVideoInfo(item.originalUrl);
      final quality = info.qualities.first;
      _executeDownload(item, quality.url, quality.fileExtension);
    } catch (e) {
      item.status       = DownloadStatus.failed;
      item.errorMessage = e.toString().replaceFirst('Exception: ', '');
      await DownloadHistoryService.instance.updateItem(item);
      _progressCtrl.add(item);
    }
  }

  // ── Save directory ───────────────────────────────────────────────
  Future<Directory> _getSaveDirectory() async {
    Directory dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/BeatFlow');
    } else {
      final base = await getApplicationDocumentsDirectory();
      dir = Directory('${base.path}/BeatFlow Downloads');
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── Completion notification ──────────────────────────────────────
  void _showCompletionNotif(DownloadItem item) {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      plugin.show(
        item.id.hashCode & 0x7FFFFFFF,
        '✅ Download Complete!',
        '${item.title.substring(0, item.title.length.clamp(0, 40))} — ${item.qualityLabel}',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'downloader', 'Downloads',
            channelDescription: 'BeatFlow download notifications',
            importance: Importance.high,
            priority  : Priority.high,
            icon      : '@drawable/ic_notification',
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Downloader] notification error: $e');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────
  String _refererFor(SourcePlatform p) => switch (p) {
    SourcePlatform.instagram => 'https://www.instagram.com/',
    SourcePlatform.twitter   => 'https://twitter.com/',
    SourcePlatform.tiktok    => 'https://www.tiktok.com/',
    SourcePlatform.youtube   => 'https://www.youtube.com/',
    _                        => 'https://www.google.com/',
  };

  String _friendlyDioError(DioException e) {
    final code = e.response?.statusCode;
    if (code == 403)
      return 'Access denied (403). URL expire ho gayi ya private hai.';
    if (code == 404) return 'Video nahi mili (404). Delete ho chuka shayad.';
    if (e.type == DioExceptionType.connectionTimeout)
      return 'Connection timeout. Internet check karo.';
    if (e.type == DioExceptionType.receiveTimeout)
      return 'Download timeout. Network slow hai — retry karo.';
    return 'Network error: ${e.message}';
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024 * 1024)
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String? _titleFromUrl(String url) {
    try {
      final parts = Uri.parse(url).pathSegments
          .where((p) => p.isNotEmpty && p.length > 3).toList();
      if (parts.isNotEmpty) return parts.last.replaceAll('-', ' ');
    } catch (_) {}
    return null;
  }

  void dispose() {
    _progressCtrl.close();
    _yt.close();
  }
}

// ── Internal queue entry ──────────────────────────────────────────
class _QueuedDownload {
  final DownloadItem item;
  final String url;
  final String ext;
  _QueuedDownload(this.item, this.url, this.ext);
}
