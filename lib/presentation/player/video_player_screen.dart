import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';
import '../../domain/entities/song_entity.dart';
import '../../core/theme/app_theme.dart';
import 'player_bloc.dart';

// ╔══════════════════════════════════════════════════════════════╗
// ║  VIDEO PLAYER SCREEN                                         ║
// ║  Full-screen video player for local MP4 files.               ║
// ║  BUG-VID01 FIX: Now integrates with PlayerBloc so the audio  ║
// ║  track is handled by just_audio (background play, lock screen ║
// ║  notification). VideoPlayerController handles visuals only;   ║
// ║  seeks/play/pause mirror to PlayerBloc for sync.             ║
// ╚══════════════════════════════════════════════════════════════╝

class VideoPlayerScreen extends StatefulWidget {
  final SongEntity song;

  const VideoPlayerScreen({super.key, required this.song});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  // Sync: keep VideoPlayerController position aligned with PlayerBloc
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    // Allow landscape for video watching
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final file = File(widget.song.data);
    // BUG-VID-AUDIOFOCUS FIX: mixWithOthers=true prevents ExoPlayer from
    // requesting AUDIOFOCUS_GAIN during initialize() and play(). Without this,
    // VideoPlayerController steals audio focus from just_audio the moment it
    // initialises → just_audio pauses → no audio ("voice nhi aati").
    // Audio stays in just_audio (background play, lock screen); this
    // controller only renders the video frames (setVolume(0) below).
    _controller = VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    await _controller.initialize();
    // Muted: audio comes from just_audio (registered via PlayerBloc).
    await _controller.setVolume(0.0);

    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() => _initialized = true);

    // Seek video visuals to match current PlayerBloc position (player may
    // already be a few seconds in if just_audio started slightly before us).
    final playerPos = context.read<PlayerBloc>().state.position;
    if (playerPos > Duration.zero) {
      await _controller.seekTo(playerPos);
    }
    _controller.play();
    _scheduleHide();
    _startSyncTimer();
  }

  // ── Periodic sync: keep video visuals aligned with audio ──────
  // BUG-VID-BUFF FIX: was 500ms/1000ms — too aggressive.
  // VideoPlayerController.seekTo() triggers buffering; if the sync timer
  // fires again while still buffering, it seeks again → infinite loading loop.
  // Fix: slower 2s cadence, wider 3s tolerance, skip entirely while buffering.
  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      if (!mounted || !_initialized) return;
      // Don't touch controller while it's already buffering — seeking during
      // buffering causes another seek → endless buffer → 1-second-play loop.
      if (_controller.value.isBuffering) return;
      final playerState = context.read<PlayerBloc>().state;
      final audioPos = playerState.position;
      final videoPos = _controller.value.position;
      final drift = (audioPos - videoPos).inMilliseconds.abs();
      // 3-second tolerance: tight enough to be invisible, loose enough to not
      // constantly seek (which re-triggers buffering every time).
      if (drift > 3000) {
        _controller.seekTo(audioPos);
      }
      // Mirror play/pause state (only when not buffering)
      if (playerState.isPlaying && !_controller.value.isPlaying &&
          !_controller.value.isBuffering) {
        _controller.play();
      } else if (!playerState.isPlaying && _controller.value.isPlaying) {
        _controller.pause();
      }
    });
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  // Play/Pause — mirrors to PlayerBloc so audio_service stays in sync
  void _togglePlay() {
    final pb = context.read<PlayerBloc>();
    if (_controller.value.isPlaying) {
      pb.add(PlayerPause());
      _controller.pause();
      _controlsVisible = true;
      _hideTimer?.cancel();
    } else {
      pb.add(PlayerResume());
      _controller.play();
      _scheduleHide();
    }
    setState(() {});
  }

  // Seek — mirrors to PlayerBloc so lock-screen and Together stay in sync
  void _seekRelative(Duration offset) {
    final current = _controller.value.position;
    final total = _controller.value.duration;
    var newPos = current + offset;
    if (newPos < Duration.zero) newPos = Duration.zero;
    if (newPos > total) newPos = total;
    _controller.seekTo(newPos);
    context.read<PlayerBloc>().add(PlayerSeek(newPos));
    _scheduleHide();
  }

  void _seekTo(Duration pos) {
    _controller.seekTo(pos);
    context.read<PlayerBloc>().add(PlayerSeek(pos));
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _syncTimer?.cancel();
    _controller.dispose();
    // Restore portrait
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // ── Video visuals ──────────────────────────────────────
            Center(
              child: _initialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(color: AppTheme.accentViolet),
            ),

            // ── Controls overlay ──────────────────────────────────
            if (_controlsVisible && _initialized)
              AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withOpacity(0.8),
                      ],
                      stops: const [0, 0.2, 0.7, 1],
                    ),
                  ),
                  child: Column(
                    children: [
                      // ── Top bar ─────────────────────────────────
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_rounded,
                                    color: Colors.white),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.song.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      widget.song.artist,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Center controls ─────────────────────────
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Rewind 10s
                            IconButton(
                              onPressed: () =>
                                  _seekRelative(const Duration(seconds: -10)),
                              icon: const Icon(Icons.replay_10_rounded,
                                  color: Colors.white, size: 42),
                            ),
                            const SizedBox(width: 24),
                            // Play/Pause
                            GestureDetector(
                              onTap: _togglePlay,
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.5),
                                      width: 2),
                                ),
                                child: Icon(
                                  _controller.value.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 36,
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            // Forward 10s
                            IconButton(
                              onPressed: () =>
                                  _seekRelative(const Duration(seconds: 10)),
                              icon: const Icon(Icons.forward_10_rounded,
                                  color: Colors.white, size: 42),
                            ),
                          ],
                        ),
                      ),

                      // ── Bottom bar: seek ────────────────────────
                      Padding(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          bottom:
                              MediaQuery.of(context).padding.bottom + 16,
                        ),
                        child: Column(
                          children: [
                            // Progress bar
                            ValueListenableBuilder<VideoPlayerValue>(
                              valueListenable: _controller,
                              builder: (_, value, __) {
                                final pos = value.position;
                                final total = value.duration;
                                final progress = total.inMilliseconds == 0
                                    ? 0.0
                                    : pos.inMilliseconds /
                                        total.inMilliseconds;
                                return Column(
                                  children: [
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        thumbShape: const RoundSliderThumbShape(
                                            enabledThumbRadius: 6),
                                        trackHeight: 3,
                                        activeTrackColor: AppTheme.accentViolet,
                                        inactiveTrackColor:
                                            Colors.white.withOpacity(0.3),
                                        thumbColor: AppTheme.accentViolet,
                                        overlayShape:
                                            SliderComponentShape.noOverlay,
                                      ),
                                      child: Slider(
                                        value: progress.clamp(0.0, 1.0),
                                        onChanged: (v) {
                                          final seek = Duration(
                                            milliseconds:
                                                (v * total.inMilliseconds)
                                                    .round(),
                                          );
                                          _seekTo(seek);
                                        },
                                        onChangeEnd: (_) => _scheduleHide(),
                                      ),
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDuration(pos),
                                          style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.8),
                                              fontSize: 11),
                                        ),
                                        Text(
                                          _formatDuration(total),
                                          style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.8),
                                              fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Buffering indicator ───────────────────────────────
            if (_initialized && _controller.value.isBuffering)
              const Center(
                child: CircularProgressIndicator(color: AppTheme.accentViolet),
              ),
          ],
        ),
      ),
    );
  }
}
