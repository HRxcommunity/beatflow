import 'package:hive/hive.dart';

part 'settings_model.g.dart';

@HiveType(typeId: 2)
class SettingsModel extends HiveObject {
  @HiveField(0)
  int themeMode = 0; // 0=system, 1=light, 2=dark

  @HiveField(1)
  int accentColorIndex = 0;

  @HiveField(2)
  bool eqEnabled = false;

  @HiveField(3)
  List<double> eqBands = [0, 0, 0, 0, 0];

  @HiveField(4)
  String eqPreset = 'Normal';

  @HiveField(5)
  double bassBoost = 0;

  @HiveField(6)
  double virtualizer = 0;

  @HiveField(7)
  double reverb = 0;

  @HiveField(8)
  double loudnessEnhancer = 0;

  @HiveField(9)
  bool filterShortClips = true;

  @HiveField(10)
  List<String> excludedFolders = [];

  @HiveField(11)
  bool showAlbumArtInNotification = true;

  @HiveField(12)
  bool gaplessPlayback = true;

  // ── Background Theme (WhatsApp-style) ──────────────────────────
  /// 0 = solid color (default app bg), 1 = custom image from gallery
  @HiveField(13)
  int backgroundType = 0;

  /// Absolute file path to user-picked background image (null = none)
  @HiveField(14)
  String? backgroundImagePath;

  /// Overlay opacity on top of background image (0.0–1.0). Default 0.55.
  @HiveField(15)
  double backgroundDimOpacity = 0.55;

  // ── Song Card Style ─────────────────────────────────────────────
  /// Song card background opacity (0.0=transparent, 1.0=solid). Default 0.6.
  @HiveField(16)
  double songCardOpacity = 0.6;

  /// Song card color index (0=default dark, 1=accent tint, 2=white, 3=black, 4=custom).
  /// When using custom color, songCardColorValue holds the 0xAARRGGBB int.
  @HiveField(17)
  int songCardColorIndex = 0;

  /// Custom card color as ARGB int (used when songCardColorIndex == 4)
  @HiveField(18)
  int songCardColorValue = 0xFF0F0F1E;

  // ── Together Background ─────────────────────────────────────────
  /// 0 = same as app bg, 1 = custom image from gallery
  @HiveField(19)
  int togetherBgType = 0;

  /// Path to Together-specific background image
  @HiveField(20)
  String? togetherBgImagePath;

  /// Dim opacity for Together bg image (0.0–1.0). Default 0.6.
  @HiveField(21)
  double togetherBgDimOpacity = 0.6;

  // ── Groq API Key (user's own key) ──────────────────────────────
  /// User's custom Groq API key. Empty = use hardcoded fallback.
  @HiveField(22)
  String groqApiKey = '';

  SettingsModel();
}
