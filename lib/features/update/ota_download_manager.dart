// lib/features/update/ota_download_manager.dart
//
// BeatFlow In-App OTA Download Manager
// ─────────────────────────────────────
// Dio-based APK downloader with:
//   • Pause / Resume (HTTP Range header)
//   • Cancel + cleanup
//   • Live progress + speed + remaining-time stream
//   • Persistent notification while downloading
//   • FileProvider-based APK install via MethodChannel

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Download state enum
// ─────────────────────────────────────────────────────────────────────────────

enum OtaDownloadState { idle, downloading, paused, completed, failed }

// ─────────────────────────────────────────────────────────────────────────────
//  Status snapshot — emitted on every meaningful change
// ─────────────────────────────────────────────────────────────────────────────

class OtaDownloadStatus {
  final OtaDownloadState state;
  final double progress;       // 0.0–1.0
  final int downloadedBytes;
  final int totalBytes;
  final double speedBps;       // bytes per second
  final Duration? remaining;
  final String? filePath;      // non-null when completed
  final String? error;
  final String version;        // e.g. "1.2.0"

  const OtaDownloadStatus({
    required this.state,
    this.progress = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBps = 0,
    this.remaining,
    this.filePath,
    this.error,
    this.version = '',
  });

  static const idle = OtaDownloadStatus(state: OtaDownloadState.idle);

  bool get isIdle        => state == OtaDownloadState.idle;
  bool get isDownloading => state == OtaDownloadState.downloading;
  bool get isPaused      => state == OtaDownloadState.paused;
  bool get isCompleted   => state == OtaDownloadState.completed;
  bool get isFailed      => state == OtaDownloadState.failed;
  bool get isActive      => !isIdle;

  OtaDownloadStatus copyWith({
    OtaDownloadState? state,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    double? speedBps,
    Duration? remaining,
    bool clearRemaining = false,
    String? filePath,
    String? error,
    String? version,
  }) =>
      OtaDownloadStatus(
        state:           state           ?? this.state,
        progress:        progress        ?? this.progress,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        totalBytes:      totalBytes      ?? this.totalBytes,
        speedBps:        speedBps        ?? this.speedBps,
        remaining:       clearRemaining ? null : (remaining ?? this.remaining),
        filePath:        filePath        ?? this.filePath,
        error:           error           ?? this.error,
        version:         version         ?? this.version,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  OtaDownloadManager — singleton
// ─────────────────────────────────────────────────────────────────────────────

class OtaDownloadManager {
  OtaDownloadManager._();
  static final instance = OtaDownloadManager._();

  // ── Stream ────────────────────────────────────────────────────────────────
  final _ctrl = StreamController<OtaDownloadStatus>.broadcast();
  Stream<OtaDownloadStatus> get stream => _ctrl.stream;

  OtaDownloadStatus _status = OtaDownloadStatus.idle;
  OtaDownloadStatus get currentStatus => _status;

  // ── Dio + cancellation ────────────────────────────────────────────────────
  CancelToken? _cancelToken;
  bool _paused = false;

  // ── Resume support ────────────────────────────────────────────────────────
  int _resumeFrom = 0;
  String? _activeUrl;
  String? _activeVersion;

  /// The URL that is currently downloading (or last attempted). Used for retry.
  String? get activeUrl => _activeUrl;

  // ── APK file reference ────────────────────────────────────────────────────
  File? _apkFile;

  // ── Speed calculation ─────────────────────────────────────────────────────
  int _lastBytes = 0;
  DateTime _lastSpeedAt = DateTime.now();

  // ── Notification ──────────────────────────────────────────────────────────
  static const int _kNotifId = 9876;
  static const String _kChannel = 'ota_download';
  final _notif = FlutterLocalNotificationsPlugin();

  // ── MethodChannel for APK install ─────────────────────────────────────────
  static const _installerChannel = MethodChannel('beatflow/installer');

  // ─────────────────────────────────────────────────────────────────────────
  //  PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Begin downloading the APK. Safe to call even if another download is active
  /// (cancels the old one first). Emits [OtaDownloadStatus] events on [stream].
  Future<void> startDownload({
    required String url,
    required String version,
  }) async {
    // Cancel any in-progress download
    if (!_status.isIdle) {
      cancel(deleteFile: true);
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _activeUrl     = url;
    _activeVersion = version;
    _resumeFrom    = 0;
    _paused        = false;

    // Clean up APKs from previous version downloads
    await _cleanOldApks(version);

    await _doDownload();
  }

  /// Pause a running download (uses HTTP Range on resume).
  void pause() {
    if (!_status.isDownloading) return;
    _paused = true;
    _resumeFrom = _status.downloadedBytes;
    _cancelToken?.cancel('paused');
    _emit(_status.copyWith(
      state: OtaDownloadState.paused,
      clearRemaining: true,
    ));
    _cancelProgressNotif();
    debugPrint('[OTA] Paused at ${_fmtSize(_resumeFrom)}');
  }

  /// Resume a paused download.
  Future<void> resume() async {
    if (!_status.isPaused) return;
    _paused = false;
    await _doDownload();
  }

  /// Cancel download and optionally delete the partial file.
  void cancel({bool deleteFile = true}) {
    _cancelToken?.cancel('cancelled');
    _paused        = false;
    _activeUrl     = null;
    _activeVersion = null;
    _resumeFrom    = 0;
    if (deleteFile) _deleteApkFile();
    _cancelProgressNotif();
    _emit(OtaDownloadStatus.idle);
    debugPrint('[OTA] Cancelled');
  }

  /// Launch Android Package Installer for the downloaded APK.
  Future<void> installApk() async {
    final path = _status.filePath ?? _apkFile?.path;
    if (path == null) {
      debugPrint('[OTA] installApk: no file path');
      return;
    }
    try {
      await _installerChannel.invokeMethod('installApk', {'path': path});
      debugPrint('[OTA] Installer intent sent for: $path');
    } catch (e) {
      debugPrint('[OTA] installApk error: $e');
      _emit(_status.copyWith(
        state: OtaDownloadState.failed,
        error: 'Install failed: $e',
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  PRIVATE: CORE DOWNLOAD
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _doDownload() async {
    final url     = _activeUrl;
    final version = _activeVersion;
    if (url == null || version == null) return;

    // ── REQUEST_INSTALL_PACKAGES permission (Android 8+) ─────────────────
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        _emit(OtaDownloadStatus(
          state:   OtaDownloadState.failed,
          version: version,
          error:   'Install permission denied. Settings → Install unknown apps → BeatFlow ON.',
        ));
        return;
      }
    }

    _cancelToken = CancelToken();
    _lastBytes   = _resumeFrom;
    _lastSpeedAt = DateTime.now();

    // ── Get APK file path ─────────────────────────────────────────────────
    try {
      _apkFile = await _getApkFile(version);
    } catch (e) {
      _emit(OtaDownloadStatus(
        state:   OtaDownloadState.failed,
        version: version,
        error:   'Storage error: $e',
      ));
      return;
    }

    // Emit initial downloading state
    _emit(OtaDownloadStatus(
      state:           OtaDownloadState.downloading,
      version:         version,
      downloadedBytes: _resumeFrom,
      progress:        0,
    ));

    // ── Show persistent notification ──────────────────────────────────────
    _showProgressNotif(version, 0, '');

    // ── Dio download ──────────────────────────────────────────────────────
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
    ));

    try {
      final openMode = _resumeFrom > 0 ? FileMode.append : FileMode.write;
      final sink     = _apkFile!.openWrite(mode: openMode);

      final response = await dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            if (_resumeFrom > 0) 'Range': 'bytes=$_resumeFrom-',
            'User-Agent': 'BeatFlow-OTA/1.0',
          },
        ),
        cancelToken: _cancelToken,
      );

      // ── Resume guard: if server ignores Range and returns 200, restart ──
      // response.statusCode is directly on Response<T>, not response.response
      if (_resumeFrom > 0 && response.statusCode == 200) {
        debugPrint('[OTA] Server returned 200 for range request — restarting from 0');
        _resumeFrom = 0;
        await _apkFile!.writeAsBytes([]); // clear file
        await sink.close();
        // Reopen as write mode
        final freshSink = _apkFile!.openWrite(mode: FileMode.write);
        await _streamDownload(
          response: response,
          sink: freshSink,
          version: version,
          startBytes: 0,
        );
        return;
      }

      final contentLength = response.headers.value('content-length') != null
          ? int.tryParse(response.headers.value('content-length')!) ?? 0
          : 0;
      final total = contentLength + _resumeFrom;

      await _streamDownload(
        response: response,
        sink: sink,
        version: version,
        startBytes: _resumeFrom,
        knownTotal: total,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // Intentional cancel/pause — state already set by pause()/cancel()
        debugPrint('[OTA] DioException: cancelled (${_paused ? "paused" : "cancelled"})');
        return;
      }
      final msg = _friendlyError(e);
      debugPrint('[OTA] DioException: $msg');
      _cancelProgressNotif();
      _emit(_status.copyWith(
        state:          OtaDownloadState.failed,
        error:          msg,
        version:        version,
        clearRemaining: true,
      ));
    } catch (e, st) {
      debugPrint('[OTA] Unexpected error: $e\n$st');
      _cancelProgressNotif();
      _emit(_status.copyWith(
        state:          OtaDownloadState.failed,
        error:          'Unexpected error: $e',
        version:        version,
        clearRemaining: true,
      ));
    }
  }

  /// Streams download chunks to [sink], emitting progress events.
  Future<void> _streamDownload({
    required Response<ResponseBody> response,
    required IOSink sink,
    required String version,
    required int startBytes,
    int knownTotal = 0,
  }) async {
    int received = startBytes;

    try {
      await for (final chunk in response.data!.stream) {
        if (_cancelToken?.isCancelled ?? false) break;
        sink.add(chunk);
        received += chunk.length;

        final progress = knownTotal > 0
            ? (received / knownTotal).clamp(0.0, 1.0)
            : 0.0;
        final speedData = _calcSpeed(received);

        _emit(_status.copyWith(
          state:           OtaDownloadState.downloading,
          progress:        progress,
          downloadedBytes: received,
          totalBytes:      knownTotal,
          speedBps:        speedData.$1,
          remaining:       speedData.$2,
          version:         version,
        ));

        // Throttle notification updates (every ~1%)
        _maybeUpdateProgressNotif(
            version, progress, received, knownTotal, speedData.$1);
      }

      await sink.flush();
      await sink.close();

      if (_cancelToken?.isCancelled ?? false) {
        debugPrint('[OTA] Download cancelled mid-stream');
        return;
      }

      // ── APK integrity check ──────────────────────────────────────────────
      if (!await _isValidApk(_apkFile!)) {
        debugPrint('[OTA] APK invalid — corrupt download');
        _deleteApkFile();
        _cancelProgressNotif();
        _emit(OtaDownloadStatus(
          state:   OtaDownloadState.failed,
          error:   'Corrupt download. Retry karo.',
          version: version,
        ));
        return;
      }

      // ── Success ──────────────────────────────────────────────────────────
      debugPrint('[OTA] Download complete: ${_apkFile!.path}');
      _resumeFrom  = 0;
      _cancelToken = null;

      final finalSize = knownTotal > 0 ? knownTotal : received;
      _emit(OtaDownloadStatus(
        state:           OtaDownloadState.completed,
        progress:        1.0,
        downloadedBytes: finalSize,
        totalBytes:      finalSize,
        filePath:        _apkFile!.path,
        version:         version,
      ));

      _showCompleteNotif(version);
    } catch (e) {
      await sink.close();
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  PRIVATE: HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  void _emit(OtaDownloadStatus s) {
    _status = s;
    if (!_ctrl.isClosed) _ctrl.add(s);
  }

  Future<File> _getApkFile(String version) async {
    late Directory base;
    if (Platform.isAndroid) {
      base = (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/ota_updates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/beatflow_v$version.apk');
  }

  void _deleteApkFile() {
    try {
      if (_apkFile != null && _apkFile!.existsSync()) {
        _apkFile!.deleteSync();
        debugPrint('[OTA] Deleted partial APK: ${_apkFile!.path}');
      }
    } catch (e) {
      debugPrint('[OTA] Delete error: $e');
    }
    _apkFile = null;
  }

  /// Delete APK files from previous version downloads to free storage.
  Future<void> _cleanOldApks(String currentVersion) async {
    try {
      late Directory base;
      if (Platform.isAndroid) {
        base = (await getExternalStorageDirectory()) ??
            await getApplicationDocumentsDirectory();
      } else {
        base = await getApplicationDocumentsDirectory();
      }
      final dir = Directory('${base.path}/ota_updates');
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File &&
            entity.path.endsWith('.apk') &&
            !entity.path.contains('beatflow_v$currentVersion')) {
          await entity.delete();
          debugPrint('[OTA] Cleaned old APK: ${entity.path}');
        }
      }
    } catch (e) {
      debugPrint('[OTA] cleanOldApks error: $e');
    }
  }

  /// APK is a ZIP — verify magic bytes 0x504B0304 to detect corrupt downloads.
  Future<bool> _isValidApk(File file) async {
    try {
      final bytes = await file.openRead(0, 4).expand((b) => b).toList();
      return bytes.length >= 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4B &&
          bytes[2] == 0x03 &&
          bytes[3] == 0x04;
    } catch (_) {
      return false;
    }
  }

  // Speed + remaining calculation (throttled to 500ms windows)
  (double, Duration?) _calcSpeed(int received) {
    final now     = DateTime.now();
    final elapsed = now.difference(_lastSpeedAt).inMilliseconds;
    if (elapsed < 500) return (_status.speedBps, _status.remaining);

    final bytesDiff = received - _lastBytes;
    final bps       = bytesDiff * 1000 / elapsed;
    _lastBytes      = received;
    _lastSpeedAt    = now;

    Duration? remaining;
    if (bps > 0 && _status.totalBytes > 0) {
      final left = _status.totalBytes - received;
      remaining = Duration(seconds: (left / bps).round());
    }
    return (bps, remaining);
  }

  String _friendlyError(DioException e) {
    final code = e.response?.statusCode;
    if (code == 403) return 'Access denied (403). GitHub release private hai?';
    if (code == 404) return 'APK nahi mila (404). Release exist karta hai?';
    if (e.type == DioExceptionType.connectionTimeout) {
      return 'Connection timeout. Internet check karo.';
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      return 'Download timeout. Network slow hai — retry karo.';
    }
    return 'Network error: ${e.message}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  PRIVATE: NOTIFICATIONS
  // ─────────────────────────────────────────────────────────────────────────

  int _lastNotifPercent = -1;

  void _showProgressNotif(String version, double progress, String speedStr) {
    try {
      _notif.show(
        _kNotifId,
        '⬇️ Downloading BeatFlow v$version',
        'Preparing...',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _kChannel, 'OTA Updates',
            channelDescription: 'BeatFlow app update download progress',
            importance:      Importance.low,
            priority:        Priority.low,
            ongoing:         true,
            autoCancel:      false,
            showProgress:    true,
            maxProgress:     100,
            progress:        0,
            icon:            '@drawable/ic_notification',
            playSound:       false,
            enableVibration: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[OTA] notif error: $e');
    }
  }

  void _maybeUpdateProgressNotif(
      String version, double progress, int received, int total, double bps) {
    final pct = (progress * 100).round();
    if (pct == _lastNotifPercent) return;
    _lastNotifPercent = pct;
    try {
      _notif.show(
        _kNotifId,
        '⬇️ Downloading BeatFlow v$version',
        '$pct% • ${_fmtSize(received)} / ${_fmtSize(total)} • ${_fmtSpeed(bps)}',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _kChannel, 'OTA Updates',
            channelDescription: 'BeatFlow app update download progress',
            importance:      Importance.low,
            priority:        Priority.low,
            ongoing:         true,
            autoCancel:      false,
            showProgress:    true,
            maxProgress:     100,
            progress:        pct,
            icon:            '@drawable/ic_notification',
            playSound:       false,
            enableVibration: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[OTA] notif update error: $e');
    }
  }

  void _showCompleteNotif(String version) {
    try {
      _notif.show(
        _kNotifId,
        '✅ BeatFlow v$version Ready to Install!',
        'Tap the in-app notification to install the update.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _kChannel, 'OTA Updates',
            channelDescription: 'BeatFlow app update download progress',
            importance: Importance.high,
            priority:   Priority.high,
            ongoing:    false,
            autoCancel: true,
            icon:       '@drawable/ic_notification',
          ),
        ),
      );
    } catch (e) {
      debugPrint('[OTA] complete notif error: $e');
    }
  }

  void _cancelProgressNotif() {
    try {
      _notif.cancel(_kNotifId);
    } catch (_) {}
    _lastNotifPercent = -1;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  PRIVATE: FORMATTERS (also exposed as static for widgets)
  // ─────────────────────────────────────────────────────────────────────────

  static String fmtSpeed(double bps) {
    if (bps >= 1024 * 1024) {
      return '${(bps / 1024 / 1024).toStringAsFixed(1)} MB/s';
    }
    if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
    return '${bps.toStringAsFixed(0)} B/s';
  }

  String _fmtSpeed(double bps) => fmtSpeed(bps);

  static String fmtSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  String _fmtSize(int bytes) => fmtSize(bytes);

  static String fmtRemaining(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m left';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s left';
    }
    return '${d.inSeconds}s left';
  }
}
