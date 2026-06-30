import 'package:hive_flutter/hive_flutter.dart';
import '../data/models/settings_model.dart';

class SettingsService {
  static const _boxName = 'settings';
  static const _key = 'prefs';

  late Box<SettingsModel> _box;

  Future<void> init() async {
    _box = await Hive.openBox<SettingsModel>(_boxName);
    if (_box.get(_key) == null) {
      await _box.put(_key, SettingsModel());
    }
  }

  SettingsModel get settings => _box.get(_key) ?? SettingsModel();

  Future<void> save(SettingsModel model) => _box.put(_key, model);

  Future<void> updateThemeMode(int mode) async {
    final s = settings..themeMode = mode;
    await save(s);
  }

  Future<void> updateAccentColor(int index) async {
    final s = settings..accentColorIndex = index;
    await save(s);
  }

  Future<void> updateBackground({
    int? backgroundType,
    String? backgroundImagePath,
    double? backgroundDimOpacity,
    bool clearImage = false,
  }) async {
    final s = settings;
    if (backgroundType != null) s.backgroundType = backgroundType;
    if (clearImage) {
      s.backgroundImagePath = null;
    } else if (backgroundImagePath != null) {
      s.backgroundImagePath = backgroundImagePath;
    }
    if (backgroundDimOpacity != null) s.backgroundDimOpacity = backgroundDimOpacity;
    await save(s);
  }

  // ── Song Card Style ──────────────────────────────────────────────
  Future<void> updateSongCard({
    double? opacity,
    int? colorIndex,
    int? colorValue,
  }) async {
    final s = settings;
    if (opacity != null) s.songCardOpacity = opacity;
    if (colorIndex != null) s.songCardColorIndex = colorIndex;
    if (colorValue != null) s.songCardColorValue = colorValue;
    await save(s);
  }

  // ── Together Background ──────────────────────────────────────────
  Future<void> updateTogetherBackground({
    int? bgType,
    String? bgImagePath,
    double? dimOpacity,
    bool clearImage = false,
  }) async {
    final s = settings;
    if (bgType != null) s.togetherBgType = bgType;
    if (clearImage) {
      s.togetherBgImagePath = null;
    } else if (bgImagePath != null) {
      s.togetherBgImagePath = bgImagePath;
    }
    if (dimOpacity != null) s.togetherBgDimOpacity = dimOpacity;
    await save(s);
  }

  Future<void> updateEq({
    bool? enabled,
    List<double>? bands,
    String? preset,
    double? bassBoost,
    double? virtualizer,
    double? reverb,
    double? loudnessEnhancer,
  }) async {
    final s = settings;
    if (enabled != null) s.eqEnabled = enabled;
    if (bands != null) s.eqBands = bands;
    if (preset != null) s.eqPreset = preset;
    if (bassBoost != null) s.bassBoost = bassBoost;
    if (virtualizer != null) s.virtualizer = virtualizer;
    if (reverb != null) s.reverb = reverb;
    if (loudnessEnhancer != null) s.loudnessEnhancer = loudnessEnhancer;
    await save(s);
  }

  Future<void> updateFilterShortClips(bool value) async {
    final s = settings..filterShortClips = value;
    await save(s);
  }

  Future<void> updateGaplessPlayback(bool value) async {
    final s = settings..gaplessPlayback = value;
    await save(s);
  }
}
