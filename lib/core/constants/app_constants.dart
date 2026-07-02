import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'BeatFlow';
  static const String appVersion = '1.0.1';

  // ── OTA Update (GitHub Releases) ────────────────────────────────────────
  // Yahan apna GitHub username aur repo name daalo.
  // Release workflow automatically ek APK GitHub Release pe upload karega.
  static const String githubOwner = 'HRxcommunity';
  static const String githubRepo  = 'beatflow';              // ← repo name

  // Hive box names
  static const String songsBox = 'songs';
  static const String playlistsBox = 'playlists';
  static const String settingsBox = 'settings';

  // Supported audio formats
  static const List<String> supportedFormats = [
    'mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wma',
  ];

  // Min song duration to include (30 seconds)
  static const int minSongDuration = 30000;

  // Accent colors
  static const List<Color> accentColors = [
    Color(0xFF6C63FF), // Purple (default)
    Color(0xFF00BCD4), // Cyan
    Color(0xFF4CAF50), // Green
    Color(0xFFFF5722), // Deep Orange
    Color(0xFFE91E63), // Pink
    Color(0xFFFFEB3B), // Yellow
    Color(0xFF2196F3), // Blue
    Color(0xFFFF9800), // Orange
  ];

  // EQ presets (5 bands: 60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz)
  static const Map<String, List<double>> eqPresets = {
    'Normal':       [0, 0, 0, 0, 0],
    'Rock':         [5, 3, -1, 3, 5],
    'Pop':          [-1, 2, 5, 2, -1],
    'Classical':    [5, 3, -1, 3, 4],
    'Jazz':         [4, 2, -1, 2, 4],
    'Dance':        [6, 0, 2, 4, 1],
    'Electronic':   [4, 3, 0, 3, 4],
    'Hip-Hop':      [5, 4, 1, 1, 2],
    'Custom':       [0, 0, 0, 0, 0],
  };

  // EQ band frequencies
  static const List<String> eqBandLabels = ['60Hz', '230Hz', '910Hz', '3.6k', '14k'];

  // Playback speeds
  static const List<double> playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  // Sleep timer options (minutes)
  static const List<int> sleepTimerOptions = [5, 10, 15, 20, 30, 45, 60, 90];
}
