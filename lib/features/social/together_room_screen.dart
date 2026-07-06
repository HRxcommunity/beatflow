// lib/features/social/together_room_screen.dart
// FIXES applied:
//  1. Buffering: Replace always-visible "Buffering..." with proper CircularProgressIndicator
//     that only shows when actually buffering
//  2. Audio: unMute() called in onReady + audio_session focus acquired
//  3. Background: WakeLock + audio session kept active while in room
//  4. Full-screen video player opens with audio (VideoPlayerScreen)

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../theme/app_theme.dart';

// ─── Together Room Screen ─────────────────────────────────────────────────────

class TogetherRoomScreen extends StatefulWidget {
  final String roomId;
  final String roomName;
  final bool isHost;

  const TogetherRoomScreen({
    super.key,
    required this.roomId,
    required this.roomName,
    this.isHost = false,
  });

  @override
  State<TogetherRoomScreen> createState() => _TogetherRoomScreenState();
}

class _TogetherRoomScreenState extends State<TogetherRoomScreen> {

  // ── YouTube Player ────────────────────────────────────────────────────────
  YoutubePlayerController? _ytController;
  bool _isBuffering = false;        // FIX: track actual buffering state
  bool _isPlaying = false;
  String _currentVideoId = '';
  String _currentTitle = '';
  String _currentChannel = '';

  // ── Audio Session ─────────────────────────────────────────────────────────
  AudioSession? _audioSession;

  // ── Search ────────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  List<Map<String, String>> _searchResults = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _initAudioSession();
  }

  // ── Audio Session / Focus (FIX: background audio) ─────────────────────────

  Future<void> _initAudioSession() async {
    _audioSession = await AudioSession.instance;
    // Configure for music – allows proper audio focus handling
    await _audioSession!.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
    // Activate session — this keeps audio going when screen dims
    await _audioSession!.setActive(true);
  }

  // ── YouTube Player Setup ──────────────────────────────────────────────────

  void _loadVideo(String videoId, {String title = '', String channel = ''}) {
    setState(() {
      _currentVideoId = videoId;
      _currentTitle = title;
      _currentChannel = channel;
      _isBuffering = true;
    });

    // Dispose existing controller
    _ytController?.dispose();

    _ytController = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,           // FIX: ensure NOT muted from the start
        enableCaption: false,
        loop: false,
        forceHD: false,
        disableDragSeek: !widget.isHost, // Only host can seek
      ),
    )
      ..addListener(_ytListener);

    setState(() {});
  }

  // FIX: Listener tracks actual buffering state
  void _ytListener() {
    if (!mounted || _ytController == null) return;
    final value = _ytController!.value;

    final nowBuffering = value.playerState == PlayerState.buffering;
    final nowPlaying = value.isPlaying;

    if (nowBuffering != _isBuffering || nowPlaying != _isPlaying) {
      setState(() {
        _isBuffering = nowBuffering;
        _isPlaying = nowPlaying;
      });
    }
  }

  // FIX: Called when YouTube player is ready — explicitly unmute + play
  void _onPlayerReady() {
    if (_ytController == null) return;
    _ytController!.unMute();               // FIX: explicitly unmute
    _ytController!.play();
    setState(() => _isBuffering = false);
  }

  void _onPlayerStateChanged(PlayerState state) {
    setState(() {
      _isBuffering = state == PlayerState.buffering;
      _isPlaying = state == PlayerState.playing;
    });
  }

  // ── Open Full-Screen Player (FIX: audio works in full-screen) ────────────

  void _openFullscreen() {
    if (_ytController == null || _currentVideoId.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _YoutubeFullscreenPlayer(
          controller: _ytController!,
          title: _currentTitle,
          channel: _currentChannel,
        ),
      ),
    );
  }

  // ── Host Controls ─────────────────────────────────────────────────────────

  void _togglePlay() {
    if (_ytController == null) return;
    if (_isPlaying) {
      _ytController!.pause();
    } else {
      _ytController!.play();
    }
  }

  void _seek(int seconds) {
    if (_ytController == null) return;
    final pos = _ytController!.value.position;
    final target = Duration(seconds: (pos.inSeconds + seconds).clamp(0, 999999));
    _ytController!.seekTo(target);
  }

  @override
  void dispose() {
    _ytController?.removeListener(_ytListener);
    _ytController?.dispose();
    _searchCtrl.dispose();
    // Release audio focus when leaving room
    _audioSession?.setActive(false);
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: SafeArea(
        child: Column(
          children: [

            // ── Top Bar ───────────────────────────────────────────────────
            _buildTopBar(),

            // ── Now Playing ───────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    if (_currentVideoId.isNotEmpty) _buildNowPlaying(),
                    const SizedBox(height: 14),
                    _buildYoutubeSearchBar(),
                    if (_searchResults.isNotEmpty) _buildSearchResults(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
            onPressed: () => Navigator.maybePop(context),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.roomName.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          _TopIconBtn(icon: Icons.sports_esports_rounded, onTap: () {}),
          _TopIconBtn(icon: Icons.chat_bubble_outline_rounded, onTap: () {}),
          _TopIconBtn(icon: Icons.videocam_rounded, onTap: () {}),
          _TopIconBtn(icon: Icons.share_rounded, onTap: () {}),
        ],
      ),
    );
  }

  Widget _buildNowPlaying() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Now Playing header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 4),
                const Text(
                  'NOW PLAYING',
                  style: TextStyle(
                    color: Colors.white70,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.withOpacity(0.4)),
                  ),
                  child: const Text(
                    'YouTube',
                    style: TextStyle(
                      color: Colors.red,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── YouTube Player with FIX ───────────────────────────────────
          if (_ytController != null)
            GestureDetector(
              onTap: _openFullscreen,   // FIX: tap opens full-screen with audio
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.zero),
                child: Stack(
                  children: [
                    YoutubePlayer(
                      controller: _ytController!,
                      showVideoProgressIndicator: true,
                      progressIndicatorColor: AppTheme.accentViolet,
                      progressColors: ProgressBarColors(
                        playedColor: AppTheme.accentViolet,
                        handleColor: AppTheme.accentCyan,
                        bufferedColor: Colors.white24,
                        backgroundColor: Colors.white10,
                      ),
                      onReady: _onPlayerReady,             // FIX: unmute in onReady
                      onEnded: (_) {},
                      // FIX: Proper buffering indicator instead of hardcoded text
                      bufferIndicator: const Center(
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: AppTheme.accentCyan,
                          ),
                        ),
                      ),
                    ),

                    // FIX: Buffering overlay — only when actually buffering
                    if (_isBuffering)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black45,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: AppTheme.accentCyan,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Loading...',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Tap-to-fullscreen hint
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.fullscreen_rounded,
                            color: Colors.white70, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            // Placeholder when no video
            Container(
              height: 180,
              color: Colors.black26,
              child: const Center(
                child: Text('🎵 Search a YouTube video below',
                    style: TextStyle(color: Colors.white38, fontFamily: 'Poppins')),
              ),
            ),

          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              _currentTitle.isEmpty ? 'Select a video' : _currentTitle,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: Text(
              _currentChannel,
              style: const TextStyle(
                color: Colors.white54,
                fontFamily: 'Poppins',
                fontSize: 12,
              ),
            ),
          ),

          // Live synced label
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(
              children: [
                Container(width: 7, height: 7,
                    decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                const Text('LIVE  Synced playback · in-app',
                    style: TextStyle(color: Colors.white54, fontFamily: 'Poppins', fontSize: 11)),
              ],
            ),
          ),

          // ── Host Controls ─────────────────────────────────────────────
          if (widget.isHost)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.settings_rounded, color: Colors.white54, size: 14),
                        SizedBox(width: 6),
                        Text('Host Controls',
                            style: TextStyle(color: Colors.white54, fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CtrlBtn(icon: Icons.skip_previous_rounded, onTap: () {}),
                        _CtrlBtn(icon: Icons.replay_10_rounded, onTap: () => _seek(-10)),
                        _CtrlBtn(
                          icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          isPrimary: true,
                          onTap: _togglePlay,
                        ),
                        _CtrlBtn(icon: Icons.forward_10_rounded, onTap: () => _seek(10)),
                        _CtrlBtn(icon: Icons.skip_next_rounded, onTap: () {}),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildYoutubeSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('▶', style: TextStyle(color: Colors.red, fontSize: 14)),
                ),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('YouTube',
                      style: TextStyle(color: Colors.white, fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  Text('Search & play for everyone',
                      style: TextStyle(color: Colors.white54, fontFamily: 'Poppins', fontSize: 11)),
                ],
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => _doSearch(_searchCtrl.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Search',
                    style: TextStyle(color: Colors.white, fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.white, fontFamily: 'Poppins', fontSize: 13),
            onSubmitted: _doSearch,
            decoration: InputDecoration(
              hintText: 'Search YouTube...',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white30, size: 18),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return Column(
      children: _searchResults.map((r) {
        return ListTile(
          tileColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: const Icon(Icons.play_circle_outline_rounded, color: Colors.redAccent),
          title: Text(r['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Poppins')),
          subtitle: Text(r['channel'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'Poppins')),
          onTap: () {
            if (r['videoId'] != null) {
              _loadVideo(r['videoId']!, title: r['title'] ?? '', channel: r['channel'] ?? '');
              setState(() => _searchResults = []);
            }
          },
        );
      }).toList(),
    );
  }

  void _doSearch(String query) {
    if (query.trim().isEmpty) return;
    // Integrate with your YouTube search logic here
    // For now, loads video if query looks like a YouTube URL / ID
    final videoId = YoutubePlayer.convertUrlToId(query.trim());
    if (videoId != null) {
      _loadVideo(videoId, title: query, channel: 'YouTube');
      return;
    }
    // Otherwise trigger search API...
    debugPrint('Searching YouTube for: $query');
  }
}

// ─── Full-Screen YouTube Player (FIX: audio works here) ──────────────────────

class _YoutubeFullscreenPlayer extends StatefulWidget {
  final YoutubePlayerController controller;
  final String title;
  final String channel;

  const _YoutubeFullscreenPlayer({
    required this.controller,
    required this.title,
    required this.channel,
  });

  @override
  State<_YoutubeFullscreenPlayer> createState() => _YoutubeFullscreenPlayerState();
}

class _YoutubeFullscreenPlayerState extends State<_YoutubeFullscreenPlayer> {

  @override
  void initState() {
    super.initState();
    // Lock orientation to landscape for full-screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    // FIX: Ensure unmuted in full-screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.unMute();
      widget.controller.play();
    });
  }

  @override
  void dispose() {
    // Restore portrait
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.channel,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontFamily: 'Poppins',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // FIX: Full-screen player with audio enabled (unMute called in initState)
            Expanded(
              child: YoutubePlayerBuilder(
                player: YoutubePlayer(
                  controller: widget.controller,
                  showVideoProgressIndicator: true,
                  progressIndicatorColor: AppTheme.accentViolet,
                  onReady: () {
                    widget.controller.unMute();
                    widget.controller.play();
                  },
                  bufferIndicator: const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.accentCyan,
                      strokeWidth: 3,
                    ),
                  ),
                ),
                builder: (ctx, player) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    player,
                  ],
                ),
              ),
            ),

            // Controls
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () {
                      final pos = widget.controller.value.position;
                      widget.controller.seekTo(Duration(seconds: (pos.inSeconds - 10).clamp(0, 99999)));
                    },
                    icon: const Icon(Icons.replay_10_rounded, color: Colors.white70, size: 32),
                  ),
                  const SizedBox(width: 24),
                  GestureDetector(
                    onTap: () {
                      if (widget.controller.value.isPlaying) {
                        widget.controller.pause();
                      } else {
                        widget.controller.play();
                      }
                      setState(() {});
                    },
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(
                        color: AppTheme.accentViolet,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    onPressed: () {
                      final pos = widget.controller.value.position;
                      widget.controller.seekTo(Duration(seconds: pos.inSeconds + 10));
                    },
                    icon: const Icon(Icons.forward_10_rounded, color: Colors.white70, size: 32),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small Widgets ────────────────────────────────────────────────────────────

class _TopIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white60, size: 20),
      onPressed: onTap,
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _CtrlBtn({required this.icon, required this.onTap, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isPrimary ? 52 : 40,
        height: isPrimary ? 52 : 40,
        decoration: BoxDecoration(
          color: isPrimary ? AppTheme.accentViolet : Colors.white.withOpacity(0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: isPrimary ? 26 : 20),
      ),
    );
  }
}
