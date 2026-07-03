import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/together_bloc.dart';
import '../domain/entities/session_entity.dart';
import '../../../presentation/player/player_bloc.dart';
import '../../../domain/entities/player_state_entity.dart';
import '../../../domain/entities/song_entity.dart';
import '../../../data/repositories/song_repository.dart';
import '../../../service_locator.dart';
import '../../youtube/youtube_service.dart';

/// Invisible widget mounted at the app root.
///
/// Owner  → listens to PlayerBloc changes and pushes to Firestore on
///           song change / play / pause ONLY (no periodic 2s writes).
/// Guest  → receives Firestore updates and syncs local player.
///           Uses elapsed-time calculation for accurate position sync.
class TogetherSyncListener extends StatefulWidget {
  final Widget child;
  const TogetherSyncListener({super.key, required this.child});

  @override
  State<TogetherSyncListener> createState() => _TogetherSyncListenerState();
}

class _TogetherSyncListenerState extends State<TogetherSyncListener>
    with WidgetsBindingObserver {

  // ── Owner push state ─────────────────────────────────────────
  String? _lastPushedSongId;
  bool?   _lastPushedIsPlaying;
  // BUG-023: track position to detect host seeks (position jumps > 5s)
  int?    _lastPushedPositionMs;
  // TASK-5: track queue length + index to detect queue changes
  int?    _lastPushedQueueLength;
  int?    _lastPushedQueueIndex;
  bool    _ownerPushDelayActive = false;
  bool    _wasOwner = false;
  // BUG-T03/Y01 FIX: re-resolve expired YouTube CDN URLs for guests
  final YoutubeService _youtubeService = YoutubeService();
  static const _ownerPushDelayDuration = Duration(seconds: 3);

  // PlayerBloc subscription — so we can react to player changes
  StreamSubscription<PlayerStateEntity>? _playerSub;

  // ── Guest sync state ─────────────────────────────────────────
  String? _lastSyncedSongId;
  String? _lastSyncedStreamUrl;
  bool?   _lastSyncedIsPlaying;

  bool    _songLoadPending = false;
  String? _loadingSongId;
  SessionEntity? _pendingSessionSnapshot;

  // FIX Bug3: tracks the songId that was SUCCESSFULLY loaded (from any source).
  // Prevents re-loading the same song just because a new/different streamUrl
  // arrives (e.g. preview URL → full googlevideo URL switch).
  String? _loadedSongId;

  // ── Guest audio watchdog ──────────────────────────────────────
  // BUG-S03 FIX: set true while _loadAndSync is running so the watchdog
  // doesn't fire PlayerResume() before the player is actually ready.
  bool   _isBuffering = false;
  int    _unexpectedPauseCount = 0;
  Timer? _audioWatchdog;
  static const _watchdogInterval   = Duration(seconds: 3);
  static const _unexpectedPauseThreshold = 2;

  // ── Sync config ───────────────────────────────────────────────
  static const _syncToleranceMs  = 1500; // BUG-S02 FIX: 4000ms was audibly too loose
  static const _readyTimeoutMs   = 6000;
  static const _postLoadSettleMs = 300;

  // ── Reset helpers ─────────────────────────────────────────────
  void _resetSyncState() {
    _lastSyncedSongId       = null;
    _lastSyncedStreamUrl    = null;
    _lastSyncedIsPlaying    = null;
    _songLoadPending        = false;
    _loadingSongId          = null;
    _pendingSessionSnapshot = null;
    _unexpectedPauseCount   = 0;
    _loadedSongId           = null; // FIX Bug3: clear on full reset
    _isBuffering            = false; // BUG-S03 FIX
    _audioWatchdog?.cancel();
    _audioWatchdog = null;
  }

  void _resetOwnerPushState() {
    _lastPushedSongId     = null;
    _lastPushedIsPlaying  = null;
    _lastPushedPositionMs = null; // BUG-023: reset seek tracking
    _lastPushedQueueLength = null; // TASK-5
    _lastPushedQueueIndex  = null; // TASK-5
  }

  // ── Init / Dispose ────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playerSub?.cancel();
    _audioWatchdog?.cancel();
    // BUG-032: if bloc is disposed mid-session (hot restart / crash),
    // BlocListener never fires the "session ended" path, so isGuestSession
    // could stay true and permanently disable auto-advance. Reset here.
    ServiceLocator.instance.audioHandler.isGuestSession = false;
    _youtubeService.dispose();
    super.dispose();
  }

  // ── App lifecycle ─────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (!mounted) return;
    final ts = context.read<TogetherBloc>().state;
    if (!ts.isInSession || ts.session == null) return;

    switch (appState) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        context.read<TogetherBloc>().add(TogetherSetOnlineStatus(false));
        break;
      case AppLifecycleState.resumed:
        context.read<TogetherBloc>().add(TogetherSetOnlineStatus(true));
        // Guest: re-sync after coming back from background
        if (!ts.isOwner && ts.session != null) {
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (!mounted) return;
            _lastSyncedIsPlaying = null; // force re-check
            final pb = context.read<PlayerBloc>();
            final r  = context.read<SongRepository>();
            _syncPlayerToSession(ts.session!, pb, r);
          });
        }
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  // ════════════════════════════════════════════════════════════
  //  OWNER — subscribe to PlayerBloc and push on real changes
  // ════════════════════════════════════════════════════════════

  /// Start listening to PlayerBloc changes when user becomes owner.
  ///
  /// FIX Bug2: Seeds _lastPushedSongId/_lastPushedIsPlaying from the
  /// current PlayerBloc state BEFORE subscribing to the stream.
  /// Without this, the first emission always sees songId != null (because
  /// _lastPushedSongId was reset to null in _resetOwnerPushState), so it
  /// pushes the old local song to Firestore, overwriting the YouTube track.
  void _startOwnerPlayerListener() {
    _playerSub?.cancel();

    // ── FIX Bug2: seed push state from current player snapshot ──
    final currentPs = context.read<PlayerBloc>().state;
    if (currentPs.currentSong != null) {
      _lastPushedSongId      = currentPs.currentSong!.id.toString();
      _lastPushedIsPlaying   = currentPs.isPlaying;
      _lastPushedPositionMs  = currentPs.position.inMilliseconds; // BUG-023
      _lastPushedQueueLength = currentPs.queue.length;            // TASK-5
      _lastPushedQueueIndex  = currentPs.currentIndex;            // TASK-5
      debugPrint('[Together] Owner: seeded push state — '
          'song=$_lastPushedSongId, playing=$_lastPushedIsPlaying, '
          'queue=${currentPs.queue.length} songs @ ${currentPs.currentIndex}');
    }
    // ────────────────────────────────────────────────────────────

    _playerSub = context.read<PlayerBloc>().stream.listen(_onPlayerStateChanged);
    debugPrint('[Together] Owner: PlayerBloc listener started');
  }

  void _stopOwnerPlayerListener() {
    _playerSub?.cancel();
    _playerSub = null;
    debugPrint('[Together] Owner: PlayerBloc listener stopped');
  }

  /// Called on every PlayerBloc state change while owner.
  void _onPlayerStateChanged(PlayerStateEntity ps) {
    if (!mounted) return;
    final ts = context.read<TogetherBloc>().state;
    if (!ts.isInSession || !ts.isOwner) return;
    if (_ownerPushDelayActive) return;

    final song = ps.currentSong;
    if (song == null) return;

    final songId      = song.id.toString();
    final posMs       = ps.position.inMilliseconds;
    final songChanged = songId != _lastPushedSongId;
    final playChanged = ps.isPlaying != _lastPushedIsPlaying;

    // BUG-023: detect significant position jumps (host seeks)
    // Only treat as seek if: same song, no play-state change, jump > 5s
    final isSeeked = !songChanged &&
        !playChanged &&
        _lastPushedPositionMs != null &&
        (posMs - _lastPushedPositionMs!).abs() > 5000;

    // TASK-5: detect queue change (new song added, removed, or reordered)
    final queueChanged = ps.queue.length != _lastPushedQueueLength ||
        ps.currentIndex != _lastPushedQueueIndex;

    // Keep tracking position even when we don't push
    _lastPushedPositionMs = posMs;

    if (!songChanged && !playChanged && !isSeeked && !queueChanged) return;

    _lastPushedSongId    = songId;
    _lastPushedIsPlaying = ps.isPlaying;
    if (queueChanged || songChanged) {
      _lastPushedQueueLength = ps.queue.length; // TASK-5
      _lastPushedQueueIndex  = ps.currentIndex; // TASK-5
    }

    if (isSeeked) {
      // Host seek — only push new position to Firestore
      debugPrint('[Together] Owner seek detected: pos=${posMs}ms → pushing seek');
      context.read<TogetherBloc>().add(TogetherPushSeek(posMs));
      return;
    }

    debugPrint('[Together] Owner push: songChanged=$songChanged '
        'playChanged=$playChanged queueChanged=$queueChanged pos=${posMs}ms isPlaying=${ps.isPlaying}');

    context.read<TogetherBloc>().add(TogetherPushPlayback(
          song:       song,
          positionMs: songChanged ? 0 : posMs,
          isPlaying:  ps.isPlaying,
          // TASK-5: include queue on song change or queue change
          queue:      (songChanged || queueChanged) ? ps.queue : null,
          queueIndex: ps.currentIndex,
        ));
  }

  // ════════════════════════════════════════════════════════════
  //  GUEST AUDIO WATCHDOG
  // ════════════════════════════════════════════════════════════

  void _startAudioWatchdog() {
    _audioWatchdog?.cancel();
    _audioWatchdog = Timer.periodic(_watchdogInterval, (_) {
      if (!mounted) return;
      final ts = context.read<TogetherBloc>().state;
      if (!ts.isInSession || ts.isOwner || ts.session == null) {
        _audioWatchdog?.cancel();
        return;
      }
      final session    = ts.session!;
      final playerBloc = context.read<PlayerBloc>();
      final ps         = playerBloc.state;

      if (session.isPlaying && !ps.isPlaying && !ps.isLoading && !_songLoadPending && !_isBuffering) { // BUG-S03 FIX
        _unexpectedPauseCount++;
        debugPrint('[Together] Watchdog: unexpected pause #$_unexpectedPauseCount');
        if (_unexpectedPauseCount >= _unexpectedPauseThreshold) {
          _unexpectedPauseCount = 0;
          debugPrint('[Together] Watchdog: force-resuming guest audio');
          playerBloc.add(PlayerResume());
        }
      } else {
        _unexpectedPauseCount = 0;
      }
    });
  }

  // ════════════════════════════════════════════════════════════
  //  GUEST — sync player to Firestore session
  // ════════════════════════════════════════════════════════════

  /// Calculate the expected current position using Firestore data + elapsed time.
  int _expectedPositionMs(SessionEntity session) {
    if (!session.isPlaying) return session.positionMs;
    // BUG-009: when songDurationMs=0 (YouTube track whose duration wasn't set,
    // or local file with unknown duration), elapsed time is uncapped and can
    // reach millions of ms if the host was paused for a long time. Seeking to
    // that position throws a PlayerException. Return the stored positionMs as-is.
    if (session.songDurationMs <= 0) return session.positionMs;
    // BUG-S01 FIX: use effectivePlaybackUpdatedAt instead of updatedAt.
    // updatedAt resets on member join/leave and streamUrl updates, which
    // corrupts the elapsed-time calculation and causes sync gaps.
    final elapsedSinceUpdate = DateTime.now()
        .difference(session.effectivePlaybackUpdatedAt)
        .inMilliseconds;
    final capped = elapsedSinceUpdate.clamp(0, session.songDurationMs);
    return (session.positionMs + capped).clamp(0, session.songDurationMs);
  }

  Future<void> _syncPlayerToSession(
    SessionEntity session,
    PlayerBloc playerBloc,
    SongRepository repo,
  ) async {
    final sessionSongId = session.songId;
    if (sessionSongId.isEmpty) return;

    // BUG-YT-05 FIX: YouTube video mode is handled entirely by the WebView
    // inside _TogetherUnifiedPlayer. PlayerBloc has nothing to play here —
    // the audio player is not used for YouTube video sessions. Calling
    // PlayerResume() / PlayerPause() on an empty player causes silent errors.
    if (session.isVideo && session.songData.startsWith('yt:')) return;

    final streamUrlChanged = session.hasStreamUrl &&
        session.streamUrl != _lastSyncedStreamUrl;
    final songIdChanged = sessionSongId != _lastSyncedSongId;

    // FIX Bug3: once a song is successfully loaded (_loadedSongId == songId),
    // don't reload it merely because a different streamUrl arrived
    // (e.g. Cloudinary preview → googlevideo full URL switch).
    // Only reload if songId truly changes OR the song was never loaded yet.
    final needLoad = songIdChanged ||
        (streamUrlChanged &&
            sessionSongId == _lastSyncedSongId &&
            _loadedSongId != sessionSongId);

    if (needLoad) {
      _pendingSessionSnapshot = session;

      if (_songLoadPending) {
        // Song changed while loading — mark for re-sync after current load
        if (_loadingSongId != sessionSongId) {
          debugPrint('[Together] Guest: song changed during load, will re-sync');
          _lastSyncedSongId = null;
        }
        return;
      }

      _songLoadPending = true;
      _loadingSongId   = sessionSongId;

      if (songIdChanged) {
        _lastSyncedSongId    = sessionSongId;
        _lastSyncedStreamUrl = null;
        _loadedSongId        = null; // FIX Bug3: new song → clear loaded marker
        debugPrint('[Together] Guest: loading new song "$sessionSongId"');
      } else {
        debugPrint('[Together] Guest: streamUrl arrived for "$sessionSongId"');
      }

      // Try local library first
      SongEntity? target = await _findLocalSong(repo, session);
      if (!mounted) { _songLoadPending = false; _loadingSongId = null; return; }

      if (target != null) {
        debugPrint('[Together] Guest: found local song "${target.title}"');
        try {
          await _loadAndSync(playerBloc, target);
          // FIX Bug3: mark as successfully loaded so future streamUrl changes
          // don't trigger a needless reload of this song
          _loadedSongId = sessionSongId;
          // Also stamp streamUrl so the streamUrlChanged guard stays false
          _lastSyncedStreamUrl = session.streamUrl.isNotEmpty
              ? session.streamUrl
              : null;
        } catch (e) {
          debugPrint('[Together] Guest: local load failed: $e');
          _lastSyncedSongId = null;
          _loadedSongId     = null;
        }
      } else if (session.hasStreamUrl) {
        // BUG-T03/Y01 FIX: if songData has 'yt:' prefix, the stored streamUrl
        // is a CDN URL that expires in ~6h. Re-resolve a fresh URL for this
        // guest's IP — prevents 403 errors for late-joining or reconnecting guests.
        SessionEntity effectiveSession = session;
        if (session.songData.startsWith('yt:')) {
          final videoId = session.songData.substring(3);
          try {
            final freshUrl = await _youtubeService.getAudioStreamUrl(videoId);
            if (freshUrl != null && freshUrl.isNotEmpty) {
              debugPrint('[Together] Guest: re-resolved fresh YouTube URL for $videoId');
              effectiveSession = session.copyWith(streamUrl: freshUrl);
            }
          } catch (e) {
            debugPrint('[Together] Guest: YouTube re-resolve failed, using stored CDN URL: $e');
          }
          if (!mounted) { _songLoadPending = false; _loadingSongId = null; return; }
        }

        final url = effectiveSession.streamUrl;
        if (url.isEmpty || !url.startsWith('http')) {
          debugPrint('[Together] Guest: invalid streamUrl, skipping');
          _lastSyncedSongId = null;
          _songLoadPending  = false;
          _loadingSongId    = null;
          return;
        }
        debugPrint('[Together] Guest: streaming from URL $url');
        _lastSyncedStreamUrl = url;
        final streamSong = _makeSongFromUrl(effectiveSession);
        try {
          await _loadAndSync(playerBloc, streamSong);
          // BUG-001 FIX: Do NOT set _loadedSongId for stream-URL loads.
          // _loadedSongId is the "local file already loaded" guard — setting it
          // here would block the preview → full URL upgrade because the next
          // streamUrl update sees _loadedSongId == sessionSongId → needLoad=false.
          // _lastSyncedStreamUrl (set above) is sufficient dedup for stream loads.
        } catch (e) {
          debugPrint('[Together] Guest: stream load failed: $e');
          _lastSyncedSongId    = null;
          _lastSyncedStreamUrl = null;
          _loadedSongId        = null;
        }
      } else {
        debugPrint('[Together] Guest: no local match + no streamUrl yet, waiting...');
        _lastSyncedSongId = null;
        _songLoadPending  = false;
        _loadingSongId    = null;
        return;
      }

      _songLoadPending = false;
      _loadingSongId   = null;

      // BUG-012 FIX: re-sync if pending snapshot is a different song OR if it
      // has a new/different streamUrl for the same song (URL upgrade case).
      // Old check `pendingSnapshot.songId != _lastSyncedSongId` missed the case
      // where host rapidly went A→B→A: after loading A, lastSyncedSongId=A and
      // pending is also A (same songId) but with different state — no re-sync.
      if (mounted && _pendingSessionSnapshot != null) {
        final latest = _pendingSessionSnapshot!;
        _pendingSessionSnapshot = null;
        final needResync = latest.songId != _lastSyncedSongId ||
            (latest.streamUrl.isNotEmpty &&
                latest.streamUrl != _lastSyncedStreamUrl);
        if (needResync) {
          debugPrint('[Together] Guest: re-syncing to latest "${latest.songId}"');
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _syncPlayerToSession(latest, context.read<PlayerBloc>(),
                  context.read<SongRepository>());
            }
          });
        }
      }
      return;
    }

    // ── Play / Pause ─────────────────────────────────────────────
    if (session.isPlaying != _lastSyncedIsPlaying) {
      _lastSyncedIsPlaying = session.isPlaying;
      if (session.isPlaying) {
        _unexpectedPauseCount = 0;
        playerBloc.add(PlayerResume());
      } else {
        playerBloc.add(PlayerPause());
      }
    }

    // ── Drift correction using elapsed time ──────────────────────
    if (!_songLoadPending && session.isPlaying) {
      final expectedMs = _expectedPositionMs(session);
      final playerMs   = playerBloc.state.position.inMilliseconds;
      final drift      = (expectedMs - playerMs).abs();

      if (drift > _syncToleranceMs) {
        debugPrint('[Together] Guest: drift ${drift}ms — correcting to ${expectedMs}ms '
            '(session=${session.positionMs}ms + elapsed)');
        playerBloc.add(PlayerSeek(Duration(milliseconds: expectedMs)));
      }
    }
  }

  /// Load song into player, wait until buffered, then seek to elapsed-corrected position.
  ///
  /// FIX Bug1: After add(PlayerPlay), the BLoC event is queued asynchronously.
  /// Without a delay, isLoading is still false (old state) on the first poll
  /// → the while-loop exits instantly → seek fires at 00:00 before audio starts.
  /// A 200 ms settle gives the BLoC time to process PlayerPlay and emit
  /// isLoading=true before we start polling.
  Future<void> _loadAndSync(PlayerBloc playerBloc, SongEntity song) async {
    if (song.data.isEmpty) {
      debugPrint('[Together] Guest: empty data path for "${song.title}"');
      return;
    }

    _isBuffering = true; // BUG-S03 FIX: prevent watchdog from firing during load
    playerBloc.add(PlayerPlay(queue: [song], index: 0));

    // FIX Bug1: yield to BLoC event queue so PlayerPlay is processed and
    // isLoading=true is emitted before we start polling for isLoading=false.
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    // Wait for buffering to complete
    final deadline = DateTime.now().add(const Duration(milliseconds: _readyTimeoutMs));
    while (true) {
      if (!mounted) return;
      if (!playerBloc.state.isLoading) break;
      if (DateTime.now().isAfter(deadline)) {
        debugPrint('[Together] Guest: buffer wait timed out, seeking anyway');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 80));
    }
    if (!mounted) return;

    await Future.delayed(const Duration(milliseconds: _postLoadSettleMs));
    _isBuffering = false; // BUG-S03 FIX: buffer settle complete
    if (!mounted) return;

    // Use latest snapshot (updated while we were loading) with elapsed-time correction
    final latestSession = _pendingSessionSnapshot;
    final targetMs      = latestSession != null
        ? _expectedPositionMs(latestSession)
        : 0;
    final shouldPlay    = latestSession?.isPlaying ?? true;

    debugPrint('[Together] Guest: seeking to ${targetMs}ms (elapsed-corrected), '
        'shouldPlay=$shouldPlay');
    playerBloc.add(PlayerSeek(Duration(milliseconds: targetMs)));

    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    if (shouldPlay) {
      playerBloc.add(PlayerResume());
      _unexpectedPauseCount = 0;
    } else {
      playerBloc.add(PlayerPause());
    }
    _lastSyncedIsPlaying = shouldPlay;

    debugPrint('[Together] Guest: sync done — "${song.title}", '
        'isPlaying=$shouldPlay, pos=${targetMs}ms');
  }

  // ── Helpers ───────────────────────────────────────────────────

  /// BUG-030: String.hashCode is documented as implementation-defined and may
  /// differ across Dart versions or platforms. Use a stable FNV-1a 32-bit hash
  /// so YouTube track IDs (e.g. "dQw4w9WgXcQ") map to the same int everywhere.
  int _stableHash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    // Force into positive range and set a high bit to avoid colliding with
    // local song IDs (which are MediaStore integers typically below 2^31).
    return (h & 0x7FFFFFFF) | 0x40000000;
  }

  SongEntity _makeSongFromUrl(SessionEntity session) => SongEntity(
        id:          int.tryParse(session.songId) ?? _stableHash(session.songId),
        title:       session.songTitle,
        artist:      session.songArtist,
        album:       '',
        albumArtist: '',
        duration:    session.songDurationMs,
        data:        session.streamUrl,
        // BUG-VID-GUEST FIX: was always false → guest PlayerBloc didn't know
        // it was playing video. Now correctly mirrors session.isVideo so the
        // player screen and routing logic see the right media type.
        isVideo:     session.isVideo,
      );

  Future<SongEntity?> _findLocalSong(SongRepository repo, SessionEntity session) async {
    try {
      final songs = await repo.getAllSongs();
      if (songs.isEmpty) return null;
      // Exact path match
      for (final s in songs) {
        if (s.data == session.songData) return s;
      }
      // Title + artist match
      final tNorm = _norm(session.songTitle);
      final aNorm = _norm(session.songArtist);
      for (final s in songs) {
        if (_norm(s.title) == tNorm && _norm(s.artist) == aNorm) return s;
      }
      // Title-only fuzzy match
      for (final s in songs) {
        final st = _norm(s.title);
        if (st == tNorm || st.contains(tNorm) || tNorm.contains(st)) return s;
      }
      return null;
    } catch (e) {
      debugPrint('[Together] _findLocalSong error: $e');
      return null;
    }
  }

  String _norm(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();

  // ════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return BlocListener<TogetherBloc, TogetherState>(
      listenWhen: (prev, curr) {
        if (prev.isInSession != curr.isInSession) return true;
        if (prev.isOwner     != curr.isOwner)     return true;
        if (!curr.isInSession) return false;
        if (!curr.isOwner) {
          final p = prev.session;
          final c = curr.session;
          if (c == null) return false;
          return p?.songId     != c.songId     ||
                 p?.streamUrl  != c.streamUrl  ||
                 p?.isPlaying  != c.isPlaying  ||
                 p?.positionMs != c.positionMs ||
                 p?.updatedAt  != c.updatedAt  ||
                 p?.sessionId  != c.sessionId;
        }
        return false;
      },
      listener: (ctx, curr) {
        // ── Session ended ──────────────────────────────────────
        if (!curr.isInSession) {
          _resetSyncState();
          _stopOwnerPlayerListener();
          _wasOwner = false;
          ServiceLocator.instance.audioHandler.isGuestSession = false;
          ServiceLocator.instance.audioHandler.restorePreYoutubeQueue(); // BUG-A01 FIX
          if (!curr.isOwner) {
            ctx.read<PlayerBloc>().add(PlayerPause());
            debugPrint('[Together] Guest left — pausing playback');
          }
          return;
        }

        final justBecameOwner   = curr.isOwner  && !_wasOwner;
        final justLostOwnership = !curr.isOwner && _wasOwner;
        _wasOwner = curr.isOwner;

        // ── Became owner ───────────────────────────────────────
        if (justBecameOwner) {
          debugPrint('[Together] Became host — starting push listener');
          _resetSyncState();
          _resetOwnerPushState();
          ServiceLocator.instance.audioHandler.isGuestSession = false;

          // Delay before first push to let audio stabilize.
          // _startOwnerPlayerListener() seeds _lastPushedSongId from the
          // current PlayerBloc state (FIX Bug2), so no stale push on first emit.
          _ownerPushDelayActive = true;
          Future.delayed(_ownerPushDelayDuration, () {
            if (mounted) {
              _ownerPushDelayActive = false;
              debugPrint('[Together] Owner push delay lifted');
              _startOwnerPlayerListener();
              // BUG-014: Force-push current player state immediately after the
              // delay lifts. If the song ended naturally during the 3-second
              // window, _onPlayerStateChanged returned early (delay was active)
              // and the song-end event was lost. Guests stay stuck on a
              // "completed" track with no auto-advance.
              SchedulerBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final ps = context.read<PlayerBloc>().state;
                final ts = context.read<TogetherBloc>().state;
                if (ps.currentSong != null && ts.isInSession && ts.isOwner) {
                  context.read<TogetherBloc>().add(TogetherPushPlayback(
                    song:       ps.currentSong!,
                    positionMs: ps.position.inMilliseconds,
                    isPlaying:  ps.isPlaying,
                  ));
                }
              });
            }
          });
          return;
        }

        // ── Lost ownership (became guest) ──────────────────────
        if (justLostOwnership) {
          debugPrint('[Together] Lost host role — switching to guest sync');
          _stopOwnerPlayerListener();
          _resetSyncState();
          ServiceLocator.instance.audioHandler.isGuestSession = true;
          _startAudioWatchdog();
          return;
        }

        // ── Owner ongoing — no listener action needed ──────────
        if (curr.isOwner) return;

        // ── Guest: first join setup ────────────────────────────
        ServiceLocator.instance.audioHandler.isGuestSession = true;
        if (_audioWatchdog == null || !_audioWatchdog!.isActive) {
          _startAudioWatchdog();
        }

        final session = curr.session;
        if (session == null) return;

        _syncPlayerToSession(
          session,
          ctx.read<PlayerBloc>(),
          ctx.read<SongRepository>(),
        );
      },
      child: widget.child,
    );
  }
}
