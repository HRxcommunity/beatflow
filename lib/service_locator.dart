import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'data/repositories/song_repository.dart';
import 'services/audio_handler.dart';
import 'services/music_scanner_service.dart';
import 'services/settings_service.dart';
import 'features/together/services/together_auth_service.dart';
import 'features/together/services/together_session_service.dart';
import 'features/together/services/together_storage_service.dart';
import 'features/social/services/social_service.dart';

class ServiceLocator {
  ServiceLocator._();
  static final instance = ServiceLocator._();

  late BeatFlowAudioHandler    audioHandler;
  late SongRepository          songRepository;
  late MusicScannerService     scannerService;
  late SettingsService         settingsService;
  late TogetherAuthService     togetherAuthService;
  late TogetherSessionService  togetherSessionService;
  late TogetherStorageService  togetherStorageService;
  late SocialService           socialService;

  Future<void> init() async {
    scannerService = MusicScannerService();
    songRepository = SongRepository(scanner: scannerService);
    await songRepository.init();

    settingsService = SettingsService();
    await settingsService.init();

    togetherAuthService    = TogetherAuthService();
    togetherSessionService = TogetherSessionService();
    togetherStorageService = TogetherStorageService();
    socialService          = SocialService();

    final handler = BeatFlowAudioHandler();
    try {
      await AudioService.init(
        builder: () => handler,
        // FIX: newer audio_service 0.18.18 assertion:
        //   androidNotificationOngoing=true requires androidStopForegroundOnPause=true
        //   OR set androidNotificationOngoing=false with androidStopForegroundOnPause=false
        // We want music to keep playing in background, so we use:
        //   ongoing=false  (notification dismissible) + stopForeground=false (service stays alive)
        config: const AudioServiceConfig(
          androidNotificationChannelId:   'com.beatflow.app.channel.audio',
          androidNotificationChannelName: 'BeatFlow',
          androidNotificationOngoing:     false,
          androidStopForegroundOnPause:   false,
          notificationColor:              Color(0xFF0A0A1A),
          artDownscaleWidth:              300,
          artDownscaleHeight:             300,
        ),
      );
      debugPrint('[BeatFlow] AudioService initialized ✓');
    } catch (e) {
      debugPrint('[BeatFlow] AudioService.init skipped (already running): $e');
    }
    audioHandler = handler;
    // BUG-032: ensure isGuestSession is always false on app start.
    // If the app crashed mid-session, isGuestSession could stay true in memory
    // (a new ServiceLocator instance creates a fresh handler so this is actually
    // fine, but being explicit guards against future singleton changes).
    audioHandler.isGuestSession = false;
  }
}
