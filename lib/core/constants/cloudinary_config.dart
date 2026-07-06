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
  static const cloudName    = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'drddsneg8',
  );
  static const uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'beatflow_audio',
  );
  static const rawUploadUrl  =
      'https://api.cloudinary.com/v1_1/$cloudName/raw/upload';
  static const autoUploadUrl =
      'https://api.cloudinary.com/v1_1/$cloudName/auto/upload';
}
