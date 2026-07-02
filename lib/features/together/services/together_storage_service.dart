import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/cloudinary_config.dart';

/// Handles uploading the host's audio file to Cloudinary (free tier).
///
/// PROGRESSIVE UPLOAD STRATEGY:
/// Instead of uploading the full file before guests can play, we:
///   1. Upload first ~20 seconds as a separate "preview" chunk → guests start
///      playing almost immediately (~5-8 sec wait instead of full-file wait)
///   2. Upload full file in background
///   3. When full upload completes, Firestore streamUrl is updated → guests
///      seamlessly switch to full URL (just_audio handles this transparently)
///
/// IMPROVEMENTS (v2):
///   A — Smart chunk size: bitrate-aware preview (~20 sec always, not fixed bytes)
///   B — Upload retry: 3 retries with exponential backoff (1s, 3s, 9s)
///   C — Upload cancel: CancelToken pattern — _activeUploadCancel.cancel() aborts
///   E — Delete retry: if Vercel call fails, retry silently after 10 seconds
class TogetherStorageService {

  // ── Cloudinary config (BUG-006+BUG-027: consolidated from CloudinaryConfig) ─
  static const _kCloudName    = CloudinaryConfig.cloudName;
  static const _kUploadPreset = CloudinaryConfig.uploadPreset;
  static const _kUploadUrl    = CloudinaryConfig.rawUploadUrl;

  // ── [C] Cancel support ────────────────────────────────────────
  /// Set a new Completer before each upload, complete it to signal cancellation.
  Completer<void>? _cancelCompleter;

  /// Call this to abort any in-progress Phase 1 or Phase 2 upload immediately.
  /// Safe to call even if no upload is running.
  void cancelActiveUpload() {
    if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
      debugPrint('[Storage] cancelActiveUpload() called — aborting upload');
      _cancelCompleter!.complete();
    }
  }

  bool get _isCancelled => _cancelCompleter?.isCompleted == true;

  // ── [A] Smart chunk size calculation ─────────────────────────
  /// BUG-013 FIX: Now accepts actual [songDurationMs] for accurate bitrate
  /// calculation. Previously used a hardcoded 3.5-min estimate which caused
  /// short/high-bitrate songs to generate preview chunks covering only
  /// 20-30 seconds instead of the intended 60 seconds.
  ///
  /// Returns number of bytes that represent approximately [targetSeconds] of audio.
  int _smartPreviewBytes(
    int fileSizeBytes, {
    int songDurationMs = 0,
    int targetSeconds = 20, // ← reduced from 60→20s so guests start 3x faster
  }) {
    if (songDurationMs > 0) {
      // Use actual duration for accurate bitrate calculation
      final actualBytesPerSec = fileSizeBytes / (songDurationMs / 1000.0);
      final chunkBytes = (actualBytesPerSec * targetSeconds).round();
      debugPrint('[Storage] Smart chunk (actual duration): '
          '${(chunkBytes / 1024).round()}KB '
          '(≈${targetSeconds}s of ${(songDurationMs / 1000).toStringAsFixed(1)}s song)');
      return chunkBytes.clamp(0, fileSizeBytes);
    }

    // Fallback: estimate bitrate from file size / assumed 3.5-min avg duration
    const estimatedDurationSec = 210.0;
    final estimatedBytesPerSec = fileSizeBytes / estimatedDurationSec;
    final estimatedKbps        = (estimatedBytesPerSec * 8 / 1024).round();

    final int bytesPerSec;
    if (estimatedKbps < 200) {
      bytesPerSec = 16000;
      debugPrint('[Storage] Detected bitrate tier: ~128kbps (estimated)');
    } else if (estimatedKbps < 280) {
      bytesPerSec = 32000;
      debugPrint('[Storage] Detected bitrate tier: ~256kbps (estimated)');
    } else {
      bytesPerSec = 40000;
      debugPrint('[Storage] Detected bitrate tier: ~320kbps (estimated)');
    }

    final chunkBytes = (bytesPerSec * targetSeconds).round();
    debugPrint('[Storage] Smart chunk (estimated): ${(chunkBytes / 1024).round()}KB '
        '(≈${targetSeconds}s at ~${estimatedKbps}kbps)');
    return chunkBytes;
  }

  // ── Public API ───────────────────────────────────────────────

  /// Progressive upload: uploads full file, reports progress via [onProgress].
  /// Returns the final download URL on success, null on failure.
  Future<String?> uploadAudio({
    required String sessionId,
    required String filePath,
    void Function(double progress)? onProgress,
  }) async {
    try {
      debugPrint('[Storage] uploadAudio → $filePath');

      if (filePath.startsWith('content://')) {
        // BUG-020: content:// URIs from SAF (Storage Access Framework) are not
        // supported for direct file upload. Show a specific, actionable error.
        debugPrint('[Storage] ✗ content:// URI: use a file manager to copy the '
            'song to your Music folder, then try sharing it in Together.');
        return null;
      }

      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) {
        debugPrint('[Storage] ✗ File not found: $filePath');
        return null;
      }
      final sourceSize = await sourceFile.length();
      if (sourceSize == 0) {
        debugPrint('[Storage] ✗ File is 0 bytes');
        return null;
      }
      debugPrint('[Storage] File OK: ${(sourceSize / 1024 / 1024).toStringAsFixed(2)}MB');

      // ── Read bytes (with cache) ───────────────────────────────
      final Uint8List bytes;
      try {
        final cacheDir  = await getTemporaryDirectory();
        final ext       = filePath.split('.').last.toLowerCase();
        final cacheName = 'together_up_${filePath.hashCode}.$ext';
        final cacheFile = File('${cacheDir.path}/$cacheName');

        if (await cacheFile.exists() && await cacheFile.length() == sourceSize) {
          debugPrint('[Storage] Reading from cache copy');
          bytes = await cacheFile.readAsBytes();
        } else {
          debugPrint('[Storage] Reading source file into memory');
          bytes = await sourceFile.readAsBytes();
          await cacheFile.writeAsBytes(bytes, flush: true);
        }
      } catch (readErr) {
        debugPrint('[Storage] File read error: $readErr — aborting');
        return null;
      }

      if (bytes.isEmpty) {
        debugPrint('[Storage] ✗ Read 0 bytes from file');
        return null;
      }
      debugPrint('[Storage] Read ${bytes.length} bytes into memory');

      // ── [C] Check cancel before starting full upload ─────────
      if (_isCancelled) {
        debugPrint('[Storage] Upload cancelled before Phase 2 start');
        return null;
      }

      // ── [B] Upload full file with retry ──────────────────────
      final url = await _uploadBytesWithRetry(
        bytes:     bytes,
        sessionId: sessionId,
        filePath:  filePath,
        suffix:    '',
        onProgress: onProgress,
      );

      return url;

    } catch (e, st) {
      debugPrint('[Storage] ✗ Upload error: $e\n$st');
      return null;
    }
  }

  /// PROGRESSIVE: Upload only the first N bytes (smart bitrate-aware chunk)
  /// so guests can start playing quickly, while the full file uploads in background.
  ///
  /// [A] previewBytes is now computed dynamically from file size + actual duration.
  /// [BUG-013] Pass [songDurationMs] for accurate bitrate-aware chunk sizing.
  /// Returns the preview URL immediately (guests start playing this).
  Future<String?> uploadPreview({
    required String sessionId,
    required String filePath,
    int? previewBytes,        // [A] null = auto-detect from bitrate
    int songDurationMs = 0,   // BUG-013: actual song duration for accurate sizing
  }) async {
    // ── [C] Reset cancel token for this new upload pair ───────
    _cancelCompleter = Completer<void>();

    try {
      debugPrint('[Storage] uploadPreview → $filePath');

      if (filePath.startsWith('content://')) {
        // BUG-020: specific error message for content:// URIs
        debugPrint('[Storage] ✗ content:// URI not supported for upload. '
            'Move file to Music folder and try again.');
        return null;
      }

      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) return null;
      final sourceSize = await sourceFile.length();
      if (sourceSize == 0) return null;

      // [A+BUG-013] Smart chunk size — uses actual duration if provided
      final chunkSize = previewBytes ??
          _smartPreviewBytes(sourceSize, songDurationMs: songDurationMs);
      final readSize  = chunkSize > sourceSize ? sourceSize : chunkSize;

      final raf        = await sourceFile.open();
      final previewBuf = Uint8List(readSize);
      await raf.readInto(previewBuf);
      await raf.close();

      debugPrint('[Storage] Preview chunk: ${(readSize / 1024).toStringAsFixed(0)}KB of '
          '${(sourceSize / 1024 / 1024).toStringAsFixed(2)}MB');

      // ── [C] Check cancel before starting ────────────────────
      if (_isCancelled) {
        debugPrint('[Storage] Upload cancelled before Phase 1 start');
        return null;
      }

      // ── [B] Retry-wrapped upload ─────────────────────────────
      final url = await _uploadBytesWithRetry(
        bytes:     previewBuf,
        sessionId: sessionId,
        filePath:  filePath,
        suffix:    '_preview',
        onProgress: (p) => debugPrint('[Storage] Preview upload: ${(p * 100).toStringAsFixed(0)}%'),
      );

      if (url != null) {
        debugPrint('[Storage] ✓ Preview URL ready → $url');
      }
      return url;

    } catch (e) {
      debugPrint('[Storage] ✗ uploadPreview error: $e');
      return null;
    }
  }

  // ── [B] Retry wrapper ─────────────────────────────────────────
  /// Wraps [_uploadBytes] with up to [maxRetries] attempts.
  /// Backoff: 1s → 3s → 9s (exponential).
  /// BUG-022: Captures the _cancelCompleter reference at call time to avoid
  /// using a stale/replaced completer from a concurrent upload cycle.
  Future<String?> _uploadBytesWithRetry({
    required Uint8List bytes,
    required String sessionId,
    required String filePath,
    required String suffix,
    void Function(double)? onProgress,
    int maxRetries = 3,
  }) async {
    // BUG-022: capture the current completer so a new upload cycle's reset
    // doesn't confuse this retry loop's cancellation detection.
    final cancelToken = _cancelCompleter;

    final delays = [
      const Duration(seconds: 1),
      const Duration(seconds: 3),
      const Duration(seconds: 9),
    ];

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      // [C] Abort immediately if cancelled between retries
      if (cancelToken?.isCompleted == true) {
        debugPrint('[Storage] Upload cancelled before attempt $attempt');
        return null;
      }

      debugPrint('[Storage] Upload attempt $attempt/$maxRetries'
          '${suffix.isNotEmpty ? " ($suffix)" : ""}');

      final url = await _uploadBytes(
        bytes:       bytes,
        sessionId:   sessionId,
        filePath:    filePath,
        suffix:      suffix,
        onProgress:  onProgress,
        cancelToken: cancelToken,
      );

      if (url != null) return url; // ✓ success

      if (attempt < maxRetries) {
        final delay = delays[attempt - 1];
        debugPrint('[Storage] Attempt $attempt failed — retrying in ${delay.inSeconds}s...');

        // [C] Race between delay and cancel so we abort instantly
        final delayFuture = Future<void>.delayed(delay);
        if (cancelToken != null) {
          await Future.any([delayFuture, cancelToken.future]);
        } else {
          await delayFuture;
        }

        if (cancelToken?.isCompleted == true) {
          debugPrint('[Storage] Upload cancelled during retry backoff');
          return null;
        }
      }
    }

    debugPrint('[Storage] ✗ All $maxRetries attempts failed');
    return null;
  }

  // ── Core upload helper ────────────────────────────────────────

  Future<String?> _uploadBytes({
    required Uint8List bytes,
    required String sessionId,
    required String filePath,
    required String suffix,          // '' for full, '_preview' for chunk
    void Function(double)? onProgress,
    Completer<void>? cancelToken,    // BUG-022: use captured token, not field
  }) async {
    // Sanitize public_id — spaces cause silent Cloudinary hang
    final safeId   = sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final fname    = filePath.split('/').last;
    final baseName = fname.contains('.')
        ? fname.substring(0, fname.lastIndexOf('.'))
        : fname;
    final safeBase = baseName
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final publicId = 'together_audio/$safeId/$safeBase$suffix';

    debugPrint('[Storage] public_id: "$publicId"');
    onProgress?.call(0.05);

    final client = http.Client();
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_kUploadUrl))
        ..fields['upload_preset'] = _kUploadPreset
        ..fields['public_id']     = publicId
        ..fields['resource_type'] = 'raw'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: '$safeBase$suffix',
        ));

      onProgress?.call(0.1);
      debugPrint('[Storage] Sending ${bytes.length ~/ 1024}KB to Cloudinary...');

      // [C] Race upload against cancel signal
      final uploadFuture = client.send(request).timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          debugPrint('[Storage] ✗ Upload timed out');
          throw Exception('Upload timed out');
        },
      );

      final http.StreamedResponse streamed;
      if (cancelToken != null) {
        final result = await Future.any<dynamic>([
          uploadFuture,
          cancelToken.future.then((_) => null),
        ]);
        if (result == null) {
          debugPrint('[Storage] ✗ Upload cancelled mid-flight');
          client.close();
          return null;
        }
        streamed = result as http.StreamedResponse;
      } else {
        streamed = await uploadFuture;
      }

      debugPrint('[Storage] HTTP ${streamed.statusCode}');
      onProgress?.call(0.9);

      final body = await streamed.stream.bytesToString();
      onProgress?.call(0.95);

      if (streamed.statusCode != 200) {
        debugPrint('[Storage] ✗ Cloudinary ${streamed.statusCode}: $body');
        return null;
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final url  = json['secure_url'] as String?;

      if (url == null || url.isEmpty) {
        debugPrint('[Storage] ✗ No secure_url: $body');
        return null;
      }

      onProgress?.call(1.0);
      debugPrint('[Storage] ✓ Done → $url');
      return url;

    } finally {
      client.close();
    }
  }

  // ── Delete via Vercel function ───────────────────────────────

  /// SECURITY (BUG-007): Rotate the exposed secret on Vercel, then pass it via:
  ///   flutter run --dart-define=DELETE_API_SECRET=your_new_secret
  /// The fallback keeps working without CI changes until you rotate.
  static const _kDeleteApiUrl    = 'https://beatflow-delete-api.vercel.app/api/delete-audio';
  static const _kDeleteAppSecret = String.fromEnvironment(
    'DELETE_API_SECRET',
    defaultValue: 'bf2024xyzSecret',
  );

  /// Called when Together session ends.
  /// Hits the Vercel serverless function which deletes all audio for [sessionId]
  /// from Cloudinary — keeps storage clean, completely free.
  ///
  /// BUG-029: old guard `_kDeleteApiUrl.startsWith('YOUR_')` was always false
  /// because the URL is already set, so deletes were attempted unconditionally
  // ── VIDEO UPLOAD ──────────────────────────────────────────────
  // For Together sessions with local MP4 video files.
  // Uses Cloudinary's "video" resource_type (auto-detects MP4 format).
  // Same 2-phase progressive strategy as audio.

  /// Phase 1 for video: upload first ~20s preview clip so guests can start
  /// watching quickly while the full video uploads in background.
  Future<String?> uploadVideoPreview({
    required String sessionId,
    required String filePath,
    int songDurationMs = 0,
  }) async {
    _cancelCompleter = Completer<void>();
    try {
      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) return null;
      final sourceSize = await sourceFile.length();
      if (sourceSize == 0) return null;

      // For video: use 20s chunk (same ratio as audio)
      final chunkSize = _smartPreviewBytes(sourceSize, songDurationMs: songDurationMs);
      final readSize  = chunkSize > sourceSize ? sourceSize : chunkSize;

      final raf        = await sourceFile.open();
      final previewBuf = Uint8List(readSize);
      await raf.readInto(previewBuf);
      await raf.close();

      debugPrint('[Storage:Video] Preview chunk: ${(readSize / 1024 / 1024).toStringAsFixed(2)}MB');

      if (_isCancelled) return null;

      return await _uploadVideoBytesWithRetry(
        bytes:     previewBuf,
        sessionId: sessionId,
        filePath:  filePath,
        suffix:    '_preview',
      );
    } catch (e) {
      debugPrint('[Storage:Video] ✗ uploadVideoPreview error: $e');
      return null;
    }
  }

  /// Phase 2 for video: upload full MP4 file.
  Future<String?> uploadVideo({
    required String sessionId,
    required String filePath,
    void Function(double)? onProgress,
  }) async {
    try {
      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) return null;

      if (_isCancelled) return null;

      final bytes = await sourceFile.readAsBytes();

      return await _uploadVideoBytesWithRetry(
        bytes:     bytes,
        sessionId: sessionId,
        filePath:  filePath,
        suffix:    '',
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('[Storage:Video] ✗ uploadVideo error: $e');
      return null;
    }
  }

  /// Like _uploadBytesWithRetry but uses Cloudinary video resource_type.
  Future<String?> _uploadVideoBytesWithRetry({
    required Uint8List bytes,
    required String sessionId,
    required String filePath,
    required String suffix,
    void Function(double)? onProgress,
    int maxRetries = 3,
  }) async {
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      if (_isCancelled) return null;
      final url = await _uploadVideoBytes(
        bytes:     bytes,
        sessionId: sessionId,
        filePath:  filePath,
        suffix:    suffix,
        onProgress: onProgress,
        cancelToken: _cancelCompleter,
      );
      if (url != null) return url;
      if (attempt < maxRetries) {
        final delay = Duration(seconds: pow(3, attempt - 1).toInt());
        debugPrint('[Storage:Video] Retry $attempt/$maxRetries in ${delay.inSeconds}s');
        await Future<void>.delayed(delay);
      }
    }
    return null;
  }

  /// Uploads video bytes to Cloudinary using video resource_type.
  Future<String?> _uploadVideoBytes({
    required Uint8List bytes,
    required String sessionId,
    required String filePath,
    required String suffix,
    void Function(double)? onProgress,
    Completer<void>? cancelToken,
  }) async {
    final safeId   = sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final fname    = filePath.split('/').last;
    final baseName = fname.contains('.')
        ? fname.substring(0, fname.lastIndexOf('.'))
        : fname;
    final safeBase = baseName
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final publicId = 'together_video/$safeId/$safeBase$suffix';

    onProgress?.call(0.05);

    final client = http.Client();
    try {
      // Use Cloudinary auto/upload with video resource_type
      const videoUploadUrl = 'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/video/upload';
      final request = http.MultipartRequest('POST', Uri.parse(videoUploadUrl))
        ..fields['upload_preset'] = _kUploadPreset
        ..fields['public_id']     = publicId
        ..fields['resource_type'] = 'video'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: '$safeBase$suffix.mp4',
        ));

      onProgress?.call(0.1);
      debugPrint('[Storage:Video] Uploading ${(bytes.length / 1024 / 1024).toStringAsFixed(2)}MB...');

      final uploadFuture = client.send(request).timeout(const Duration(minutes: 20));
      final http.StreamedResponse streamed;
      if (cancelToken != null) {
        final result = await Future.any<dynamic>([
          uploadFuture,
          cancelToken.future.then((_) => null),
        ]);
        if (result == null) { client.close(); return null; }
        streamed = result as http.StreamedResponse;
      } else {
        streamed = await uploadFuture;
      }

      onProgress?.call(0.9);
      final body   = await streamed.stream.bytesToString();
      onProgress?.call(0.95);
      final parsed = jsonDecode(body) as Map<String, dynamic>;

      if (streamed.statusCode == 200 && parsed.containsKey('secure_url')) {
        final url = parsed['secure_url'] as String;
        debugPrint('[Storage:Video] ✓ Upload OK → $url');
        onProgress?.call(1.0);
        return url;
      }
      debugPrint('[Storage:Video] ✗ Cloudinary error ${streamed.statusCode}: $body');
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> deleteSessionAudio(String sessionId) async {
    debugPrint('[Storage] Deleting session audio via Vercel: $sessionId');
    final success = await _tryDelete(sessionId);

    // [E] Retry once after 10s if first attempt failed
    if (!success) {
      debugPrint('[Storage] Delete failed — will retry in 10s');
      await Future<void>.delayed(const Duration(seconds: 10));
      await _tryDelete(sessionId, isRetry: true);
    }
  }

  /// Single delete attempt. Returns true on HTTP 200, false otherwise.
  Future<bool> _tryDelete(String sessionId, {bool isRetry = false}) async {
    final label = isRetry ? '[retry]' : '';
    try {
      final client = http.Client();
      try {
        final response = await client.post(
          Uri.parse(_kDeleteApiUrl),
          headers: {
            'Content-Type':      'application/json',
            'x-beatflow-secret': _kDeleteAppSecret,
          },
          body: jsonEncode({'sessionId': sessionId}),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final json    = jsonDecode(response.body) as Map<String, dynamic>;
          final deleted = json['deleted'] ?? 0;
          debugPrint('[Storage] $label ✓ Deleted $deleted file(s) for session $sessionId');
          return true;
        } else {
          debugPrint('[Storage] $label ✗ Delete API returned ${response.statusCode}: ${response.body}');
          return false;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      // Non-critical — session still ends normally
      debugPrint('[Storage] $label deleteSessionAudio error (non-critical): $e');
      return false;
    }
  }
}
