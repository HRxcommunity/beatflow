import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:just_audio/just_audio.dart';
import '../../domain/entities/song_entity.dart';
import '../../domain/entities/player_state_entity.dart';
import '../../services/audio_handler.dart';
import '../../data/repositories/song_repository.dart';
import '../../services/settings_service.dart';

// ─── Events ──────────────────────────────────────────────────

abstract class PlayerEvent extends Equatable {
  const PlayerEvent();
  @override
  List<Object?> get props => [];
}

class PlayerPlay extends PlayerEvent {
  final List<SongEntity> queue;
  final int index;
  const PlayerPlay({required this.queue, required this.index});
  @override
  List<Object?> get props => [index, queue.length];
}

class PlayerPause extends PlayerEvent {}
class PlayerResume extends PlayerEvent {}
class PlayerStop extends PlayerEvent {}
class PlayerNext extends PlayerEvent {}
class PlayerPrevious extends PlayerEvent {}

class PlayerSeek extends PlayerEvent {
  final Duration position;
  const PlayerSeek(this.position);
  @override
  List<Object?> get props => [position];
}

class PlayerToggleShuffle extends PlayerEvent {}

class PlayerToggleFavorite extends PlayerEvent {
  final int songId;
  const PlayerToggleFavorite(this.songId);
  @override
  List<Object?> get props => [songId];
}

class PlayerSetRepeat extends PlayerEvent {
  final RepeatMode mode;
  const PlayerSetRepeat(this.mode);
  @override
  List<Object?> get props => [mode];
}

class PlayerSetSpeed extends PlayerEvent {
  final double speed;
  const PlayerSetSpeed(this.speed);
  @override
  List<Object?> get props => [speed];
}

class PlayerSetSleepTimer extends PlayerEvent {
  final int? minutes;
  const PlayerSetSleepTimer(this.minutes);
  @override
  List<Object?> get props => [minutes];
}

class PlayerReorderQueue extends PlayerEvent {
  final int oldIndex;
  final int newIndex;
  const PlayerReorderQueue(this.oldIndex, this.newIndex);
  @override
  List<Object?> get props => [oldIndex, newIndex];
}

class PlayerRemoveFromQueue extends PlayerEvent {
  final int index;
  const PlayerRemoveFromQueue(this.index);
  @override
  List<Object?> get props => [index];
}

class _PlayerStateUpdated extends PlayerEvent {
  final PlayerStateEntity state;
  const _PlayerStateUpdated(this.state);
}

// BUG-P01 FIX: synthetic event fired when the audio handler's mediaItem
// changes outside of a PlayerPlay event (e.g. YouTube track via Together).
class _PlayerMediaItemChanged extends PlayerEvent {
  const _PlayerMediaItemChanged();
}

// ─── BLoC ─────────────────────────────────────────────────────

class PlayerBloc extends Bloc<PlayerEvent, PlayerStateEntity> {
  final BeatFlowAudioHandler _handler;
  final SongRepository _repo;
  final SettingsService _settings;
  final List<StreamSubscription> _subs = [];
  Timer? _sleepTimer;

  PlayerBloc({required BeatFlowAudioHandler handler, required SongRepository repo, required SettingsService settings})
      : _handler = handler,
        _repo = repo,
        _settings = settings,
        super(const PlayerStateEntity()) {
    on<PlayerPlay>(_onPlay);
    on<PlayerPause>(_onPause);
    on<PlayerResume>(_onResume);
    on<PlayerStop>(_onStop);
    on<PlayerNext>(_onNext);
    on<PlayerPrevious>(_onPrevious);
    on<PlayerSeek>(_onSeek);
    on<PlayerToggleShuffle>(_onToggleShuffle);
    on<PlayerToggleFavorite>(_onToggleFavorite);
    on<PlayerSetRepeat>(_onSetRepeat);
    on<PlayerSetSpeed>(_onSetSpeed);
    on<PlayerSetSleepTimer>(_onSetSleepTimer);
    on<PlayerReorderQueue>(_onReorderQueue);
    on<PlayerRemoveFromQueue>(_onRemoveFromQueue);
    on<_PlayerStateUpdated>((e, emit) => emit(e.state));
    // BUG-P01 FIX: keep queue/currentSong in sync when YouTube plays
    on<_PlayerMediaItemChanged>((e, emit) => _syncMediaItem(emit));

    _listenToPlayer();
  }

  void _listenToPlayer() {
    final p = _handler.player;
    _subs.add(p.playingStream.listen((_) => _pushState()));
    _subs.add(p.positionStream.listen((_) => _pushState()));
    _subs.add(p.durationStream.listen((_) => _pushState()));
    _subs.add(p.currentIndexStream.listen((_) => _pushState()));
    _subs.add(p.processingStateStream.listen((_) => _pushState()));
    // BUG-P01 FIX: react to audioHandler mediaItem changes so the mini
    // player and NowPlaying screen show the YouTube track title/artist
    // instead of stale local library info after Together YouTube playback.
    _subs.add(_handler.mediaItem.stream.listen((_) => add(const _PlayerMediaItemChanged())));
  }

  void _pushState() {
    final p = _handler.player;
    final idx = p.currentIndex ?? 0;
    final queue = state.queue;
    add(_PlayerStateUpdated(state.copyWith(
      currentSong: idx < queue.length ? queue[idx] : null,
      currentIndex: idx,
      isPlaying: p.playing,
      position: p.position,
      duration: p.duration ?? Duration.zero,
      isLoading: p.processingState == ProcessingState.loading ||
          p.processingState == ProcessingState.buffering,
    )));
  }

  // BUG-P01 FIX: sync PlayerBloc currentSong from handler's mediaItem when
  // the local queue doesn't have a matching entry (YouTube / Together mode).
  void _syncMediaItem(Emitter<PlayerStateEntity> emit) {
    final mi = _handler.mediaItem.value;
    if (mi == null) return;
    final p   = _handler.player;
    final idx = p.currentIndex ?? 0;
    // Only override when local queue doesn't cover the current index
    if (idx < state.queue.length) return;
    // Build a synthetic SongEntity so the mini-player can display the
    // YouTube track info without a PlayerPlay event being dispatched.
    final ytSong = SongEntity(
      id:          0, // synthetic — not a local library ID
      title:       mi.title,
      artist:      mi.artist ?? '',
      album:       mi.album  ?? '',
      albumArtist: mi.artist ?? '',
      duration:    mi.duration?.inMilliseconds ?? 0,
      data:        mi.id, // stream URL
    );
    emit(state.copyWith(
      currentSong: ytSong,
      isPlaying:   p.playing,
      position:    p.position,
      duration:    p.duration ?? Duration.zero,
      isLoading:   p.processingState == ProcessingState.loading ||
                   p.processingState == ProcessingState.buffering,
    ));
  }

  Future<void> _onPlay(PlayerPlay e, Emitter<PlayerStateEntity> emit) async {
    emit(state.copyWith(
      queue: e.queue,
      currentIndex: e.index,
      currentSong: e.queue[e.index],
      isLoading: true,
    ));
    try {
      await _handler.playSongs(e.queue, e.index,
          gapless: _settings.settings.gaplessPlayback);
      await _repo.incrementPlayCount(e.queue[e.index].id);
    } catch (e) {
      // Catches Firebase Storage 404 (object-not-found), network errors, etc.
      // Emit idle state so guest doesn't get stuck in isLoading=true forever
      debugPrint('[PlayerBloc] _onPlay error: $e');
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> _onPause(PlayerPause e, Emitter<PlayerStateEntity> emit) async {
    await _handler.pause();
  }

  Future<void> _onStop(PlayerStop e, Emitter<PlayerStateEntity> emit) async {
    await _handler.stop();
  }

  Future<void> _onResume(PlayerResume e, Emitter<PlayerStateEntity> emit) async {
    await _handler.play();
  }

  Future<void> _onNext(PlayerNext e, Emitter<PlayerStateEntity> emit) async {
    await _handler.skipToNext();
    final idx = _handler.player.currentIndex ?? 0;
    if (idx < state.queue.length) {
      await _repo.incrementPlayCount(state.queue[idx].id);
    }
  }

  Future<void> _onPrevious(PlayerPrevious e, Emitter<PlayerStateEntity> emit) async {
    if (_handler.player.position.inSeconds > 3) {
      await _handler.seek(Duration.zero);
    } else {
      await _handler.skipToPrevious();
    }
  }

  Future<void> _onSeek(PlayerSeek e, Emitter<PlayerStateEntity> emit) async {
    await _handler.seek(e.position);
  }

  Future<void> _onToggleShuffle(
      PlayerToggleShuffle e, Emitter<PlayerStateEntity> emit) async {
    final newVal = !state.isShuffled;
    await _handler.setShuffleModeEnabled(newVal);
    emit(state.copyWith(isShuffled: newVal));
  }

  Future<void> _onToggleFavorite(
      PlayerToggleFavorite e, Emitter<PlayerStateEntity> emit) async {
    await _repo.toggleFavorite(e.songId);
    final current = state.currentSong;
    if (current != null && current.id == e.songId) {
      emit(state.copyWith(
        currentSong: current.copyWith(isFavorite: !current.isFavorite),
      ));
    }
  }

  Future<void> _onSetRepeat(
      PlayerSetRepeat e, Emitter<PlayerStateEntity> emit) async {
    final loopMode = {
      RepeatMode.off: LoopMode.off,
      RepeatMode.all: LoopMode.all,
      RepeatMode.one: LoopMode.one,
    }[e.mode]!;
    await _handler.setLoopMode(loopMode);
    emit(state.copyWith(repeatMode: e.mode));
  }

  Future<void> _onSetSpeed(
      PlayerSetSpeed e, Emitter<PlayerStateEntity> emit) async {
    await _handler.setSpeed(e.speed);
    emit(state.copyWith(speed: e.speed));
  }

  void _onReorderQueue(
      PlayerReorderQueue e, Emitter<PlayerStateEntity> emit) {
    final queue = List<SongEntity>.from(state.queue);
    // Adjust newIndex for removal
    final ni = e.newIndex > e.oldIndex ? e.newIndex - 1 : e.newIndex;
    final item = queue.removeAt(e.oldIndex);
    queue.insert(ni, item);
    // Recalculate current index after reorder
    final currentSong = state.currentSong;
    final newCurrent = currentSong == null
        ? state.currentIndex
        : queue.indexWhere((s) => s.id == currentSong.id);
    emit(state.copyWith(
      queue:        queue,
      currentIndex: newCurrent < 0 ? 0 : newCurrent,
    ));
    _handler.updateQueueFromSongs(queue, newCurrent < 0 ? 0 : newCurrent);
  }

  void _onRemoveFromQueue(
      PlayerRemoveFromQueue e, Emitter<PlayerStateEntity> emit) {
    final queue = List<SongEntity>.from(state.queue);
    if (e.index < 0 || e.index >= queue.length) return;
    queue.removeAt(e.index);
    final currentSong = state.currentSong;
    final newCurrent = currentSong == null
        ? state.currentIndex
        : queue.indexWhere((s) => s.id == currentSong.id);
    emit(state.copyWith(
      queue:        queue,
      currentIndex: newCurrent < 0 ? 0 : newCurrent,
    ));
    _handler.updateQueueFromSongs(queue, newCurrent < 0 ? 0 : newCurrent);
  }

  void _onSetSleepTimer(
      PlayerSetSleepTimer e, Emitter<PlayerStateEntity> emit) {
    _sleepTimer?.cancel();
    if (e.minutes != null) {
      _sleepTimer = Timer(Duration(minutes: e.minutes!), () {
        _handler.pause();
      });
    }
    emit(state.copyWith(sleepTimerMinutes: e.minutes));
  }

  @override
  Future<void> close() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _sleepTimer?.cancel();
    return super.close();
  }
}
