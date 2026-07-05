/// BUG-006 + BUG-027: Cloudinary credentials consolidated into one place.
/// Previously duplicated in together_storage_service.dart and
/// together_chat_media_service.dart.
///
/// SECURITY (BUG-006): Rotate your cloud_name and upload_preset if this
/// code is in a public repo, then pass them via --dart-define:
///   flutter run \
///     --dart-define=CLOUDINARY_CLOUD_NAME=your_cloud \
///     --dart-define=CLOUDINARY_UPLOAD_PRESET=your_preset
///
/// The dart-define values take precedence; the fallback strings are the
/// current hardcoded values so the app keeps working without any CI changes.
abstract class CloudinaryConfig {
  // BUG-LOW-01 FIX: removed hardcoded defaultValue strings — they were compiled
  // into the APK string table and extractable via `strings beatflow.apk`.
  // Rotate credentials immediately if this repo is/was public.
  //
  // REQUIRED: pass credentials at build time via --dart-define:
  //   flutter build apk \
  //     --dart-define=CLOUDINARY_CLOUD_NAME=your_cloud \
  //     --dart-define=CLOUDINARY_UPLOAD_PRESET=your_preset
  static const cloudName    = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
  static const uploadPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');
  static const rawUploadUrl  =
      'https://api.cloudinary.com/v1_1/$cloudName/raw/upload';
  static const autoUploadUrl =
      'https://api.cloudinary.com/v1_1/$cloudName/auto/upload';
}
