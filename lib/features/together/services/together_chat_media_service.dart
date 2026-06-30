import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/cloudinary_config.dart';

class ChatMediaResult {
  final String url;
  final String? fileName;
  final bool isImage;

  const ChatMediaResult({
    required this.url,
    this.fileName,
    required this.isImage,
  });
}

/// Chat media upload using Cloudinary (same free account as audio uploads).
/// Completely replaces Firebase Storage — no premium plan required.
///
/// BUG-006+BUG-027: Cloudinary config now read from CloudinaryConfig so both
/// services stay in sync — no more dual-update risk.
///
/// Resource type 'auto' → Cloudinary detects image/raw automatically.
/// Public IDs stored under:  together_sessions/{sessionId}/chat_images/
///                           together_sessions/{sessionId}/chat_files/
class TogetherChatMediaService {
  // ── Cloudinary config (BUG-006+BUG-027: shared via CloudinaryConfig) ──────
  static const _kCloudName    = CloudinaryConfig.cloudName;
  static const _kUploadPreset = CloudinaryConfig.uploadPreset;
  // 'auto' lets Cloudinary decide image vs raw — works for both pics and docs
  static const _kUploadUrl    = CloudinaryConfig.autoUploadUrl;

  final ImagePicker _picker = ImagePicker();

  // ── Request media permissions (Android 13+) ──────────────────

  Future<bool> _requestMediaPermissions({bool forFiles = false}) async {
    if (!Platform.isAndroid) return true;

    final permissions = forFiles
        ? [Permission.photos, Permission.videos, Permission.storage]
        : [Permission.photos];

    final results = await permissions.request();
    final anyGranted = results.values.any(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );

    if (!anyGranted) debugPrint('[ChatMedia] Permissions denied: $results');
    return anyGranted;
  }

  // ── Pick & upload image ──────────────────────────────────────

  Future<ChatMediaResult?> pickAndUploadImage({
    required String sessionId,
    void Function(double)? onProgress,
  }) async {
    try {
      final ok = await _requestMediaPermissions(forFiles: false);
      if (!ok) {
        debugPrint('[ChatMedia] Image permission denied');
        return null;
      }

      final xFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      if (xFile == null) return null;

      return _uploadToCloudinary(
        file: File(xFile.path),
        sessionId: sessionId,
        folder: 'chat_images',
        isImage: true,
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('[ChatMedia] pickImage error: $e');
      return null;
    }
  }

  // ── Pick & upload file ───────────────────────────────────────

  Future<ChatMediaResult?> pickAndUploadFile({
    required String sessionId,
    void Function(double)? onProgress,
  }) async {
    try {
      final ok = await _requestMediaPermissions(forFiles: true);
      if (!ok) {
        debugPrint('[ChatMedia] File permission denied');
        return null;
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return null;
      final picked = result.files.first;
      if (picked.path == null) return null;

      final file = File(picked.path!);
      if (!await file.exists()) {
        debugPrint('[ChatMedia] Picked file does not exist: ${picked.path}');
        return null;
      }

      final mime = lookupMimeType(picked.path!) ?? 'application/octet-stream';
      final isImage = mime.startsWith('image/');

      return _uploadToCloudinary(
        file: file,
        sessionId: sessionId,
        folder: 'chat_files',
        isImage: isImage,
        onProgress: onProgress,
        customFileName: picked.name,
      );
    } catch (e) {
      debugPrint('[ChatMedia] pickFile error: $e');
      return null;
    }
  }

  // ── Upload to Cloudinary ─────────────────────────────────────

  Future<ChatMediaResult?> _uploadToCloudinary({
    required File file,
    required String sessionId,
    required String folder,
    required bool isImage,
    void Function(double)? onProgress,
    String? customFileName,
  }) async {
    try {
      final originalName = customFileName ?? p.basename(file.path);

      // Sanitize names — spaces/special chars cause Cloudinary issues
      final safeTs   = DateTime.now().millisecondsSinceEpoch;
      final safeName = originalName
          .replaceAll(RegExp(r'\s+'), '_')
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '');
      final fullName = '${safeTs}_$safeName';

      // public_id organises files in Cloudinary's media library
      final safeId   = sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final publicId = 'together_sessions/$safeId/$folder/$fullName';

      debugPrint('[ChatMedia] Uploading to Cloudinary: $publicId');
      onProgress?.call(0.05);

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        debugPrint('[ChatMedia] File is empty, aborting');
        return null;
      }
      onProgress?.call(0.15);

      debugPrint('[ChatMedia] Sending ${bytes.length ~/ 1024}KB...');

      final client = http.Client();
      try {
        final request = http.MultipartRequest('POST', Uri.parse(_kUploadUrl))
          ..fields['upload_preset'] = _kUploadPreset
          ..fields['public_id']     = publicId
          ..files.add(http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: fullName,
          ));

        onProgress?.call(0.2);

        final streamed = await client.send(request).timeout(
          const Duration(minutes: 5),
          onTimeout: () => throw Exception('[ChatMedia] Upload timed out'),
        );

        final body = await streamed.stream.bytesToString();
        onProgress?.call(0.95);

        if (streamed.statusCode != 200) {
          debugPrint('[ChatMedia] Cloudinary ${streamed.statusCode}: $body');
          return null;
        }

        final json = jsonDecode(body) as Map<String, dynamic>;
        final url  = json['secure_url'] as String?;

        if (url == null || url.isEmpty) {
          debugPrint('[ChatMedia] No secure_url in response: $body');
          return null;
        }

        onProgress?.call(1.0);
        debugPrint('[ChatMedia] ✓ Uploaded: $url');
        return ChatMediaResult(url: url, fileName: originalName, isImage: isImage);

      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[ChatMedia] _uploadToCloudinary error: $e');
      return null;
    }
  }

  // ── Delete session media (best-effort) ───────────────────────

  /// Cloudinary deletion requires API secret (server-side only).
  /// For free tier this is skipped — 25GB limit is generous for chat media.
  /// When you add a Vercel delete function later, hook it up here.
  Future<void> deleteSessionMedia(String sessionId) async {
    debugPrint('[ChatMedia] deleteSessionMedia: skipped (use Vercel function for cleanup)');
  }
}
