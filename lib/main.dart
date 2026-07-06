import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'data/models/song_model.dart';
import 'data/models/playlist_model.dart';
import 'data/models/settings_model.dart';
import 'data/repositories/song_repository.dart';
import 'service_locator.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'presentation/player/player_bloc.dart';
import 'presentation/songs/library_bloc.dart';
import 'presentation/settings/settings_bloc.dart';
import 'features/together/bloc/together_bloc.dart';
import 'features/together/bloc/game_bloc.dart';
import 'features/together/presentation/together_sync_listener.dart';
import 'features/ai_vocab/vocab_notif_service.dart';
import 'features/downloader/download_history_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'features/social/bloc/social_bloc.dart';
import 'features/social/services/social_service.dart';
import 'widgets/common/app_background.dart';
import 'features/update/ota_download_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init Hive
  try {
    await Hive.initFlutter();
    Hive.registerAdapter(SongModelAdapter());
    Hive.registerAdapter(PlaylistModelAdapter());
    Hive.registerAdapter(SettingsModelAdapter());
    await Hive.openBox<String>('together_url_cache');
  } catch (e) {
    debugPrint('[BeatFlow] Hive init failed: $e');
  }

  // Init Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('[BeatFlow] Firebase init failed: $e');
  }

  // Init services
  try {
    await ServiceLocator.instance.init();
  } catch (e) {
    debugPrint('[BeatFlow] ServiceLocator init failed: $e');
  }

  // Init download history — Hive box for persisting download records
  try {
    await DownloadHistoryService.instance.init();
  } catch (e) {
    debugPrint('[BeatFlow] DownloadHistoryService init failed: $e');
  }

  // Init vocab notification service
  // BUG-VN01 FIX: VocabNotifService.init() was never called, so:
  //   • flutter_local_notifications plugin was never initialized
  //   • Hive box 'vocab_notif_data' was never opened → word bank & settings lost
  //   • Notification channel 'vocab_learning' was never created
  // All scheduleNext() / sendTestNotification() calls silently failed as a result.
  try {
    await VocabNotifService.instance.init();
  } catch (e) {
    debugPrint('[BeatFlow] VocabNotifService init failed: $e');
  }

  // Register 'downloader' notification channel alongside 'vocab_learning'
  // VocabNotifService.init() above has already called plugin.initialize(),
  // so we only need to create the channel here.
  try {
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
      'downloader',
      'Downloads',
      description: 'BeatFlow download complete notifications',
      importance : Importance.high,
    ));
  } catch (e) {
    debugPrint('[BeatFlow] Downloader notif channel init failed: $e');
  }

  // Register 'ota_download' notification channel for in-app update progress
  try {
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
      'ota_download',
      'OTA Updates',
      description: 'BeatFlow update download progress',
      importance: Importance.low, // low = no sound, shows in shade
    ));
  } catch (e) {
    debugPrint('[BeatFlow] OTA notif channel init failed: $e');
  }

  runApp(const BeatFlowApp());
}

class BeatFlowApp extends StatelessWidget {
  const BeatFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    final sl = ServiceLocator.instance;

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => LibraryBloc(repo: sl.songRepository, settings: sl.settingsService),
        ),
        BlocProvider(
          create: (_) => PlayerBloc(
            handler: sl.audioHandler,
            repo: sl.songRepository,
            settings: sl.settingsService,
          ),
        ),
        BlocProvider(
          create: (_) => SettingsBloc(service: sl.settingsService)
            ..add(SettingsLoad()),
        ),
        BlocProvider(
          create: (_) => TogetherBloc(
            auth:           sl.togetherAuthService,
            sessionService: sl.togetherSessionService,
            storageService: sl.togetherStorageService,
          ),
        ),
        // BUG-G01 FIX: GameBloc at root so _TogetherNotificationOverlay can
        // listen to game invites even when user is on a non-Together screen.
        BlocProvider(
          create: (_) => GameBloc(),
        ),
        // Social Hub — friends, public rooms, activity feed
        BlocProvider(
          create: (_) => SocialBloc(
            socialService:  sl.socialService,
            sessionService: sl.togetherSessionService,
          ),
        ),
        RepositoryProvider<SongRepository>.value(value: sl.songRepository),
      ],
      child: BlocBuilder<SettingsBloc, SettingsState>(
        buildWhen: (prev, curr) =>
            prev.themeMode != curr.themeMode ||
            prev.accentColorIndex != curr.accentColorIndex,
        builder: (context, settings) {
          final accent = AppTheme.accentColor(settings.accentColorIndex);
          return TogetherSyncListener(
            child: _TogetherNotificationOverlay(
              child: MaterialApp.router(
                title: AppConstants.appName,
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light(accent),
                darkTheme: AppTheme.dark(accent),
                themeMode: settings.themeMode,
                routerConfig: AppRouter.router,
                // AppBackground wraps every route via builder
                builder: (context, child) => AppBackground(
                  child: child ?? const SizedBox(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Together in-app notification overlay ─────────────────────────────────────
// Shows a banner for:
//   BUG-T02 FIX  – host is ending session (isEnding = true)
//   Original     – session ended by host
//   Original     – host-change request arrived
//   BUG-H01 FIX  – guest just became the new host
//   BUG-T01 FIX  – host switched to a new song
//   BUG-H03 FIX  – host declined the guest's host-change request
//   BUG-G01 FIX  – game invite arrived (even on non-Together screens)
class _TogetherNotificationOverlay extends StatefulWidget {
  final Widget child;
  const _TogetherNotificationOverlay({required this.child});

  @override
  State<_TogetherNotificationOverlay> createState() =>
      _TogetherNotificationOverlayState();
}

class _TogetherNotificationOverlayState
    extends State<_TogetherNotificationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<Offset> _slide;

  String? _message;
  IconData _icon = Icons.info_outline_rounded;
  Color _color = const Color(0xFF7C3AED);
  bool _visible = false;

  bool    _wasInSession          = false;
  bool    _wasOwner              = false;
  String? _lastPendingRequestUid;
  String? _lastSongTitle;   // BUG-T01 FIX
  bool    _hadPendingRequest = false; // BUG-H03 FIX

  // BUG-U01 FIX: store the auto-hide timer so it can be cancelled when a new
  // banner appears or when the user dismisses manually, preventing the old
  // delayed _hide() from closing a freshly-shown banner.
  Timer? _autoHideTimer;

  // BUG-G01 FIX: track invite count so we notify on new arrivals
  int _lastInviteCount = 0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel(); // BUG-U01 FIX
    _anim.dispose();
    super.dispose();
  }

  void _show(String msg,
      {IconData icon = Icons.info_outline_rounded, Color? color}) {
    if (!mounted) return;
    // BUG-U01 FIX: cancel any in-flight hide timer before showing new banner,
    // so it doesn't prematurely close this new notification.
    _autoHideTimer?.cancel();
    setState(() {
      _message = msg;
      _icon    = icon;
      _color   = color ?? const Color(0xFF7C3AED);
      _visible = true;
    });
    _anim.forward(from: 0);
    _autoHideTimer = Timer(const Duration(seconds: 4), _hide); // BUG-U01 FIX
  }

  void _hide() {
    _autoHideTimer?.cancel(); // BUG-U01 FIX: prevent double-fire
    if (!mounted) return;
    _anim.reverse().then((_) {
      if (mounted) setState(() => _visible = false);
    });
  }

  // ── TogetherBloc notification handler ────────────────────────
  void _onTogetherStateChanged(TogetherState curr) {
    final inSession = curr.isInSession;
    final isOwner   = curr.isOwner;

    // BUG-T02 FIX: host is gracefully ending — show warning BEFORE deletion
    if (inSession && !isOwner && (curr.session?.isEnding ?? false)) {
      _show(
        '⏳ Session is ending...',
        icon:  Icons.hourglass_bottom_rounded,
        color: const Color(0xFF7C3AED),
      );
    }

    // Guest: host ended session
    if (_wasInSession && !_wasOwner && !inSession) {
      _show(
        'Session ended by host ❤️',
        icon:  Icons.heart_broken_rounded,
        color: const Color(0xFFEC4899),
      );
    }

    // BUG-H01 FIX: guest just became the new host
    if (_wasInSession && !_wasOwner && inSession && isOwner) {
      _show(
        '🎤 You are now the host!',
        icon:  Icons.mic_rounded,
        color: const Color(0xFF7C3AED),
      );
    }

    // BUG-H03 FIX: host rejected the guest's host-change request
    // The request disappears (pendingHostRequest → null) and the user is
    // still a guest (not owner). Compare against _hadPendingRequest to detect.
    final hasPendingRequest =
        curr.session?.pendingHostRequest != null && !isOwner && inSession;
    if (_hadPendingRequest && !hasPendingRequest && !isOwner && _wasInSession) {
      _show(
        'Host declined your request',
        icon:  Icons.cancel_rounded,
        color: const Color(0xFFEF4444),
      );
    }
    _hadPendingRequest = hasPendingRequest;

    // Host: new host-change request arrived
    if (inSession && isOwner) {
      final reqUid  = curr.session?.pendingHostRequest?.requesterUid;
      final reqName = curr.session?.pendingHostRequest?.requesterName ?? 'Someone';
      if (reqUid != null && reqUid != _lastPendingRequestUid) {
        _lastPendingRequestUid = reqUid;
        _show(
          '$reqName wants to become host',
          icon:  Icons.swap_horiz_rounded,
          color: const Color(0xFF06B6D4),
        );
      } else if (reqUid == null) {
        _lastPendingRequestUid = null;
      }
    }

    // BUG-T01 FIX: show "🎵 Now Playing" when host switches song
    if (inSession && !isOwner) {
      final currTitle = curr.session?.songTitle;
      if (currTitle != null &&
          currTitle.isNotEmpty &&
          currTitle != _lastSongTitle) {
        final prevTitle = _lastSongTitle;
        _lastSongTitle = currTitle;
        // Skip on first join (prevTitle == null) — that's just the join event
        if (prevTitle != null && _wasInSession) {
          _show(
            '🎵 Now Playing: $currTitle',
            icon:  Icons.music_note_rounded,
            color: const Color(0xFF7C3AED),
          );
        }
      }
    }

    // Reset song-title tracker when leaving session
    if (!inSession) _lastSongTitle = null;

    _wasInSession = inSession;
    _wasOwner     = isOwner;
  }

  // BUG-G01 FIX: game invite handler ───────────────────────────
  void _onGameStateChanged(GameState gameState) {
    final count = gameState.pendingInvites.length;
    if (count > _lastInviteCount && gameState.pendingInvites.isNotEmpty) {
      final invite = gameState.pendingInvites.last;
      _show(
        '🎮 ${invite.fromName} challenged you!',
        icon:  Icons.sports_esports_rounded,
        color: const Color(0xFF7C3AED),
      );
    }
    _lastInviteCount = count;
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<TogetherBloc, TogetherState>(
          listenWhen: (prev, curr) =>
              prev.isInSession != curr.isInSession ||
              prev.isOwner     != curr.isOwner     ||
              prev.session?.pendingHostRequest?.requesterUid !=
                  curr.session?.pendingHostRequest?.requesterUid ||
              // BUG-T01 FIX: song title changes
              (curr.isInSession && !curr.isOwner &&
                  prev.session?.songTitle != curr.session?.songTitle) ||
              // BUG-T02 FIX: isEnding changes
              (curr.isInSession && !curr.isOwner &&
                  (prev.session?.isEnding ?? false) !=
                      (curr.session?.isEnding ?? false)),
          listener: (_, state) => _onTogetherStateChanged(state),
        ),
        // BUG-G01 FIX: listen to GameBloc for game invites from any screen
        BlocListener<GameBloc, GameState>(
          listenWhen: (prev, curr) =>
              curr.pendingInvites.length != prev.pendingInvites.length,
          listener: (_, state) => _onGameStateChanged(state),
        ),
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            OtaDownloadOverlay(child: widget.child),  // floating OTA bubble
            if (_visible)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SlideTransition(
                  position: _slide,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: _color.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _color.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(_icon, color: Colors.white, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _message ?? '',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _hide,
                                child: const Icon(Icons.close_rounded,
                                    color: Colors.white70, size: 18),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
