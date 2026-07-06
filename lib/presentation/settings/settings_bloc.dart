import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../services/settings_service.dart';
import '../../core/config/groq_config.dart';
import '../../data/models/settings_model.dart';

// ─── State ────────────────────────────────────────────────────

class SettingsState extends Equatable {
  final ThemeMode themeMode;
  final int accentColorIndex;
  final bool eqEnabled;
  final List<double> eqBands;
  final String eqPreset;
  final double bassBoost;
  final double virtualizer;
  final double reverb;
  final double loudnessEnhancer;
  // Background theme
  final int backgroundType;          // 0=solid, 1=image
  final String? backgroundImagePath; // null = none
  final double backgroundDimOpacity; // 0.0–1.0
  // Playback settings
  final bool filterShortClips;
  final bool gaplessPlayback;
  // Song Card Style
  final double songCardOpacity;      // 0.0–1.0 (default 0.6)
  final int songCardColorIndex;      // 0=dark, 1=accent, 2=white, 3=black
  final int songCardColorValue;      // custom color ARGB int
  // Together Background
  final int togetherBgType;          // 0=default, 1=custom image
  final String? togetherBgImagePath;
  final double togetherBgDimOpacity;
  final String groqApiKey;

  const SettingsState({
    this.themeMode = ThemeMode.dark,
    this.accentColorIndex = 0,
    this.eqEnabled = false,
    this.eqBands = const [0, 0, 0, 0, 0],
    this.eqPreset = 'Normal',
    this.bassBoost = 0,
    this.virtualizer = 0,
    this.reverb = 0,
    this.loudnessEnhancer = 0,
    this.backgroundType = 0,
    this.backgroundImagePath,
    this.backgroundDimOpacity = 0.55,
    this.filterShortClips = true,
    this.gaplessPlayback = true,
    this.songCardOpacity = 0.6,
    this.songCardColorIndex = 0,
    this.songCardColorValue = 0xFF0F0F1E,
    this.togetherBgType = 0,
    this.togetherBgImagePath,
    this.togetherBgDimOpacity = 0.6,
    this.groqApiKey = '',
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    int? accentColorIndex,
    bool? eqEnabled,
    List<double>? eqBands,
    String? eqPreset,
    double? bassBoost,
    double? virtualizer,
    double? reverb,
    double? loudnessEnhancer,
    int? backgroundType,
    String? backgroundImagePath,
    bool clearBgImage = false,
    double? backgroundDimOpacity,
    bool? filterShortClips,
    bool? gaplessPlayback,
    double? songCardOpacity,
    int? songCardColorIndex,
    int? songCardColorValue,
    int? togetherBgType,
    String? togetherBgImagePath,
    bool clearTogetherBgImage = false,
    double? togetherBgDimOpacity,
    String? groqApiKey,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      accentColorIndex: accentColorIndex ?? this.accentColorIndex,
      eqEnabled: eqEnabled ?? this.eqEnabled,
      eqBands: eqBands ?? this.eqBands,
      eqPreset: eqPreset ?? this.eqPreset,
      bassBoost: bassBoost ?? this.bassBoost,
      virtualizer: virtualizer ?? this.virtualizer,
      reverb: reverb ?? this.reverb,
      loudnessEnhancer: loudnessEnhancer ?? this.loudnessEnhancer,
      backgroundType: backgroundType ?? this.backgroundType,
      backgroundImagePath: clearBgImage ? null : (backgroundImagePath ?? this.backgroundImagePath),
      backgroundDimOpacity: backgroundDimOpacity ?? this.backgroundDimOpacity,
      filterShortClips: filterShortClips ?? this.filterShortClips,
      gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
      songCardOpacity: songCardOpacity ?? this.songCardOpacity,
      songCardColorIndex: songCardColorIndex ?? this.songCardColorIndex,
      songCardColorValue: songCardColorValue ?? this.songCardColorValue,
      togetherBgType: togetherBgType ?? this.togetherBgType,
      togetherBgImagePath: clearTogetherBgImage
          ? null
          : (togetherBgImagePath ?? this.togetherBgImagePath),
      togetherBgDimOpacity: togetherBgDimOpacity ?? this.togetherBgDimOpacity,
      groqApiKey: groqApiKey ?? this.groqApiKey,
    );
  }

  @override
  List<Object?> get props => [
        themeMode, accentColorIndex, eqEnabled, eqBands, eqPreset,
        bassBoost, virtualizer, reverb, loudnessEnhancer,
        backgroundType, backgroundImagePath, backgroundDimOpacity,
        filterShortClips, gaplessPlayback,
        songCardOpacity, songCardColorIndex, songCardColorValue,
        togetherBgType, togetherBgImagePath, togetherBgDimOpacity,
        groqApiKey,
      ];
}

// ─── Events ──────────────────────────────────────────────────

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();
  @override
  List<Object?> get props => [];
}

class SettingsLoad extends SettingsEvent {}

class SettingsThemeChanged extends SettingsEvent {
  final ThemeMode mode;
  const SettingsThemeChanged(this.mode);
  @override
  List<Object?> get props => [mode];
}

class SettingsAccentChanged extends SettingsEvent {
  final int index;
  const SettingsAccentChanged(this.index);
  @override
  List<Object?> get props => [index];
}

class SettingsEqToggled extends SettingsEvent {
  final bool enabled;
  const SettingsEqToggled(this.enabled);
}

class SettingsEqBandChanged extends SettingsEvent {
  final int bandIndex;
  final double value;
  const SettingsEqBandChanged(this.bandIndex, this.value);
  @override
  List<Object?> get props => [bandIndex, value];
}

class SettingsEqPresetChanged extends SettingsEvent {
  final String preset;
  const SettingsEqPresetChanged(this.preset);
  @override
  List<Object?> get props => [preset];
}

/// Set a custom background image from gallery (WhatsApp-style)
class SettingsBackgroundImageSet extends SettingsEvent {
  final String path;
  final double dimOpacity;
  const SettingsBackgroundImageSet(this.path, {this.dimOpacity = 0.55});
  @override
  List<Object?> get props => [path, dimOpacity];
}

/// Reset background to default solid color
class SettingsBackgroundReset extends SettingsEvent {}

/// Change the dim opacity of the background image overlay
class SettingsBackgroundDimChanged extends SettingsEvent {
  final double opacity;
  const SettingsBackgroundDimChanged(this.opacity);
  @override
  List<Object?> get props => [opacity];
}

class SettingsFilterShortClipsChanged extends SettingsEvent {
  final bool value;
  const SettingsFilterShortClipsChanged(this.value);
  @override
  List<Object?> get props => [value];
}

class SettingsGaplessPlaybackChanged extends SettingsEvent {
  final bool value;
  const SettingsGaplessPlaybackChanged(this.value);
  @override
  List<Object?> get props => [value];
}

// ── Song Card Style Events ────────────────────────────────────

class SettingsSongCardOpacityChanged extends SettingsEvent {
  final double opacity;
  const SettingsSongCardOpacityChanged(this.opacity);
  @override
  List<Object?> get props => [opacity];
}

class SettingsSongCardColorChanged extends SettingsEvent {
  final int colorIndex;
  final int? customColorValue; // only for colorIndex == 4
  const SettingsSongCardColorChanged(this.colorIndex, {this.customColorValue});
  @override
  List<Object?> get props => [colorIndex, customColorValue];
}

// ── Together Background Events ────────────────────────────────

class SettingsTogetherBgImageSet extends SettingsEvent {
  final String path;
  final double dimOpacity;
  const SettingsTogetherBgImageSet(this.path, {this.dimOpacity = 0.6});
  @override
  List<Object?> get props => [path, dimOpacity];
}

class SettingsTogetherBgReset extends SettingsEvent {}

class SettingsTogetherBgDimChanged extends SettingsEvent {
  final double opacity;
  const SettingsTogetherBgDimChanged(this.opacity);
  @override
  List<Object?> get props => [opacity];
}

class SettingsGroqKeyChanged extends SettingsEvent {
  final String key;
  const SettingsGroqKeyChanged(this.key);
  @override
  List<Object?> get props => [key];
}

// ─── BLoC ─────────────────────────────────────────────────────

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsService _service;

  SettingsBloc({required SettingsService service})
      : _service = service,
        super(const SettingsState()) {
    on<SettingsLoad>(_onLoad);
    on<SettingsThemeChanged>(_onThemeChanged);
    on<SettingsAccentChanged>(_onAccentChanged);
    on<SettingsEqToggled>(_onEqToggled);
    on<SettingsEqBandChanged>(_onEqBandChanged);
    on<SettingsEqPresetChanged>(_onEqPresetChanged);
    on<SettingsBackgroundImageSet>(_onBgImageSet);
    on<SettingsBackgroundReset>(_onBgReset);
    on<SettingsBackgroundDimChanged>(_onBgDimChanged);
    on<SettingsFilterShortClipsChanged>(_onFilterShortClipsChanged);
    on<SettingsGaplessPlaybackChanged>(_onGaplessPlaybackChanged);
    // Song card
    on<SettingsSongCardOpacityChanged>(_onSongCardOpacityChanged);
    on<SettingsSongCardColorChanged>(_onSongCardColorChanged);
    // Together bg
    on<SettingsTogetherBgImageSet>(_onTogetherBgImageSet);
    on<SettingsTogetherBgReset>(_onTogetherBgReset);
    on<SettingsTogetherBgDimChanged>(_onTogetherBgDimChanged);
    on<SettingsGroqKeyChanged>(_onGroqKeyChanged);
  }

  void _onLoad(SettingsLoad e, Emitter<SettingsState> emit) {
    final s = _service.settings;
    emit(SettingsState(
      themeMode: ThemeMode.values[s.themeMode],
      accentColorIndex: s.accentColorIndex,
      eqEnabled: s.eqEnabled,
      eqBands: List<double>.from(s.eqBands),
      eqPreset: s.eqPreset,
      bassBoost: s.bassBoost,
      virtualizer: s.virtualizer,
      reverb: s.reverb,
      loudnessEnhancer: s.loudnessEnhancer,
      backgroundType: s.backgroundType,
      backgroundImagePath: s.backgroundImagePath,
      backgroundDimOpacity: s.backgroundDimOpacity,
      filterShortClips: s.filterShortClips,
      gaplessPlayback: s.gaplessPlayback,
      songCardOpacity: s.songCardOpacity,
      songCardColorIndex: s.songCardColorIndex,
      songCardColorValue: s.songCardColorValue,
      togetherBgType: s.togetherBgType,
      togetherBgImagePath: s.togetherBgImagePath,
      togetherBgDimOpacity: s.togetherBgDimOpacity,
      groqApiKey: s.groqApiKey,
    ));
  }

  Future<void> _onThemeChanged(
      SettingsThemeChanged e, Emitter<SettingsState> emit) async {
    await _service.updateThemeMode(e.mode.index);
    emit(state.copyWith(themeMode: e.mode));
  }

  Future<void> _onAccentChanged(
      SettingsAccentChanged e, Emitter<SettingsState> emit) async {
    await _service.updateAccentColor(e.index);
    emit(state.copyWith(accentColorIndex: e.index));
  }

  Future<void> _onEqToggled(
      SettingsEqToggled e, Emitter<SettingsState> emit) async {
    await _service.updateEq(enabled: e.enabled);
    emit(state.copyWith(eqEnabled: e.enabled));
  }

  Future<void> _onEqBandChanged(
      SettingsEqBandChanged e, Emitter<SettingsState> emit) async {
    final bands = List<double>.from(state.eqBands);
    bands[e.bandIndex] = e.value;
    await _service.updateEq(bands: bands, preset: 'Custom');
    emit(state.copyWith(eqBands: bands, eqPreset: 'Custom'));
  }

  Future<void> _onEqPresetChanged(
      SettingsEqPresetChanged e, Emitter<SettingsState> emit) async {
    const presets = {
      'Normal':     [0.0, 0.0, 0.0, 0.0, 0.0],
      'Rock':       [5.0, 3.0, -1.0, 3.0, 5.0],
      'Pop':        [-1.0, 2.0, 5.0, 2.0, -1.0],
      'Classical':  [5.0, 3.0, -1.0, 3.0, 4.0],
      'Jazz':       [4.0, 2.0, -1.0, 2.0, 4.0],
      'Dance':      [6.0, 0.0, 2.0, 4.0, 1.0],
      'Electronic': [4.0, 3.0, 0.0, 3.0, 4.0],
      'Hip-Hop':    [5.0, 4.0, 1.0, 1.0, 2.0],
    };
    final bands = presets[e.preset] ?? state.eqBands;
    await _service.updateEq(bands: bands, preset: e.preset);
    emit(state.copyWith(eqBands: bands, eqPreset: e.preset));
  }

  Future<void> _onBgImageSet(
      SettingsBackgroundImageSet e, Emitter<SettingsState> emit) async {
    await _service.updateBackground(
      backgroundType: 1,
      backgroundImagePath: e.path,
      backgroundDimOpacity: e.dimOpacity,
    );
    emit(state.copyWith(
      backgroundType: 1,
      backgroundImagePath: e.path,
      backgroundDimOpacity: e.dimOpacity,
    ));
  }

  Future<void> _onBgReset(
      SettingsBackgroundReset e, Emitter<SettingsState> emit) async {
    await _service.updateBackground(backgroundType: 0, clearImage: true);
    emit(state.copyWith(backgroundType: 0, clearBgImage: true));
  }

  Future<void> _onBgDimChanged(
      SettingsBackgroundDimChanged e, Emitter<SettingsState> emit) async {
    await _service.updateBackground(backgroundDimOpacity: e.opacity);
    emit(state.copyWith(backgroundDimOpacity: e.opacity));
  }

  Future<void> _onFilterShortClipsChanged(
      SettingsFilterShortClipsChanged e, Emitter<SettingsState> emit) async {
    await _service.updateFilterShortClips(e.value);
    emit(state.copyWith(filterShortClips: e.value));
  }

  Future<void> _onGaplessPlaybackChanged(
      SettingsGaplessPlaybackChanged e, Emitter<SettingsState> emit) async {
    await _service.updateGaplessPlayback(e.value);
    emit(state.copyWith(gaplessPlayback: e.value));
  }

  // ── Song Card ─────────────────────────────────────────────────

  Future<void> _onSongCardOpacityChanged(
      SettingsSongCardOpacityChanged e, Emitter<SettingsState> emit) async {
    await _service.updateSongCard(opacity: e.opacity);
    emit(state.copyWith(songCardOpacity: e.opacity));
  }

  Future<void> _onSongCardColorChanged(
      SettingsSongCardColorChanged e, Emitter<SettingsState> emit) async {
    await _service.updateSongCard(
      colorIndex: e.colorIndex,
      colorValue: e.customColorValue,
    );
    emit(state.copyWith(
      songCardColorIndex: e.colorIndex,
      songCardColorValue: e.customColorValue ?? state.songCardColorValue,
    ));
  }

  // ── Together Background ────────────────────────────────────────

  Future<void> _onTogetherBgImageSet(
      SettingsTogetherBgImageSet e, Emitter<SettingsState> emit) async {
    await _service.updateTogetherBackground(
      bgType: 1,
      bgImagePath: e.path,
      dimOpacity: e.dimOpacity,
    );
    emit(state.copyWith(
      togetherBgType: 1,
      togetherBgImagePath: e.path,
      togetherBgDimOpacity: e.dimOpacity,
    ));
  }

  Future<void> _onTogetherBgReset(
      SettingsTogetherBgReset e, Emitter<SettingsState> emit) async {
    await _service.updateTogetherBackground(bgType: 0, clearImage: true);
    emit(state.copyWith(togetherBgType: 0, clearTogetherBgImage: true));
  }

  Future<void> _onTogetherBgDimChanged(
      SettingsTogetherBgDimChanged e, Emitter<SettingsState> emit) async {
    await _service.updateTogetherBackground(dimOpacity: e.opacity);
    emit(state.copyWith(togetherBgDimOpacity: e.opacity));
  }

  Future<void> _onGroqKeyChanged(
      SettingsGroqKeyChanged e, Emitter<SettingsState> emit) async {
    await _service.updateGroqApiKey(e.key);
    // Also update GroqConfig so effectiveKey reflects immediately
    GroqConfig.instance.init(_service);
    emit(state.copyWith(groqApiKey: e.key));
  }
}
