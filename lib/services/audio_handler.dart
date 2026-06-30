import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../domain/entities/song_entity.dart';

class BeatFlowAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  /// When true (guest in Together session), auto-advance on completion is
  /// suppressed. Host controls the queue — guest must not skip independently.
  bool isGuestSession = false;

  // BUG-A01 FIX: snapshot the queue before playYouTubeTrack() replaces it,
  // so the host's local music queue can be restored when the session ends.
  List<MediaItem> _savedQueue = [];

  BeatFlowAudioHandler() {
    // Pipe just_audio events → audio_service playback state
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Update media item when track changes
    _player.currentIndexStream.listen((index) {
      if (index != null &&
          queue.value.isNotEmpty &&
          index < queue.value.length) {
        mediaItem.add(queue.value[index]);
      }
    });

    // Auto-advance on completion — blocked for guests in Together session.
    // BUG-A02 FIX: only call skipToNext() on ConcatenatingAudioSource (local
    // music queue). Single-source YouTube tracks use a bare AudioSource —
    // calling seekToNext() on them is a no-op that leaves audio silently stuck
    // in the "completed" state for all guests.
    _player.processingStateStream.listen((processingState) {
      if (processingState == ProcessingState.completed && !isGuestSession) {
        if (_player.audioSource is ConcatenatingAudioSource) {
          skipToNext();
        }
        // For single-source (YouTube) the track simply ends.
        // Host must manually pick next track.
      }
    });
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle:      AudioProcessingState.idle,
        ProcessingState.loading:   AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready:     AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing:          _player.playing,
      updatePosition:   _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed:            _player.speed,
      queueIndex:       event.currentIndex,
    );
  }

  // ── Play local or http songs ──────────────────────────────────

  Future<void> playSongs(List<SongEntity> songs, int initialIndex,
      {bool gapless = true}) async {
    final items = songs.map(_songToMediaItem).toList();
    queue.add(items);

    final sources = songs.map((s) {
      final uri = Uri.tryParse(s.data);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        return AudioSource.uri(uri, tag: _songToMediaItem(s));
      }
      return AudioSource.uri(Uri.file(s.data), tag: _songToMediaItem(s));
    }).toList();

    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: sources,
          useLazyPreparation: !gapless,
        ),
        initialIndex: initialIndex,
      );
      await _player.setShuffleModeEnabled(false);
      await _player.play();
    } on PlayerException catch (e) {
      debugPrint(
          '[AudioHandler] PlayerException: ${e.message} (${e.code})');
      rethrow;
    } catch (e) {
      debugPrint('[AudioHandler] setAudioSource error: $e');
      rethrow;
    }
  }

  // ── Play a single YouTube / HTTP stream ──────────────────────
  //  Used by Together when host plays a YouTube track.
  //  Works with HLS (.m3u8) and direct audio URLs.
  //  Background notification shows title, artist, and thumbnail.

  Future<void> playYouTubeTrack({
    required String streamUrl,
    required String title,
    required String artist,
    required String thumbnailUrl,
    required Duration duration,
  }) async {
    // BUG-A01 FIX: save the current queue before we replace it with a single
    // YouTube item, so the host can recover their local music queue on session end.
    _savedQueue = List.from(queue.value);

    final item = MediaItem(
      id:       streamUrl,
      title:    title,
      artist:   artist,
      duration: duration,
      artUri:   Uri.tryParse(thumbnailUrl),
      // Shows in notification and lock screen
      displayTitle:    title,
      displaySubtitle: artist,
    );

    mediaItem.add(item);
    queue.add([item]);

    try {
      final uri    = Uri.parse(streamUrl);
      final source = streamUrl.contains('.m3u8')
          ? HlsAudioSource(uri, tag: item)
          : AudioSource.uri(uri, tag: item);

      await _player.setAudioSource(source);
      await _player.play();
      debugPrint('[AudioHandler] YouTube stream started: $title');
    } on PlayerException catch (e) {
      debugPrint('[AudioHandler] YouTube PlayerException: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[AudioHandler] YouTube play error: $e');
      rethrow;
    }
  }

  /// BUG-A01 FIX: Restore the pre-YouTube queue saved in [playYouTubeTrack].
  /// Call this when the host leaves a Together session so the music app
  /// recovers the library queue that was active before the session started.
  void restorePreYoutubeQueue() {
    if (_savedQueue.isNotEmpty) {
      queue.add(_savedQueue);
      debugPrint('[AudioHandler] Pre-YouTube queue restored '
          '(${_savedQueue.length} items)');
      _savedQueue = [];
    }
  }

  MediaItem _songToMediaItem(SongEntity s) => MediaItem(
        id:       s.data,
        title:    s.title,
        artist:   s.artist,
        album:    s.album,
        duration: Duration(milliseconds: s.duration),
        displayTitle:    s.title,
        displaySubtitle: s.artist,
      );

  // ── Core controls ─────────────────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) async {
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  // Keep foreground service alive when task removed from recents
  @override
  Future<void> onTaskRemoved() async {
    // Do NOT stop — keep playing in background
  }

  // ── Extras ───────────────────────────────────────────────────

  AudioPlayer get player => _player;

  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> updateQueueFromSongs(
      List<SongEntity> songs, int currentIndex) async {
    try {
      final items = songs.map(_songToMediaItem).toList();
      queue.add(items);
      final src = _player.audioSource;
      if (src is ConcatenatingAudioSource) {
        final newSources = songs.map((s) {
          final uri = Uri.tryParse(s.data);
          if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
            return AudioSource.uri(uri, tag: _songToMediaItem(s));
          }
          return AudioSource.uri(Uri.file(s.data), tag: _songToMediaItem(s));
        }).toList();
        await src.clear();
        await src.addAll(newSources);
        if (currentIndex >= 0 && currentIndex < songs.length) {
          await _player.seek(Duration.zero, index: currentIndex);
        }
      }
    } catch (e) {
      debugPrint('[AudioHandler] updateQueue error: $e');
    }
  }

  Future<void> setLoopMode(LoopMode mode) => _player.setLoopMode(mode);

  Future<void> setShuffleModeEnabled(bool enabled) =>
      _player.setShuffleModeEnabled(enabled);
}
