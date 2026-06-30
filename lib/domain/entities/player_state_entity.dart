import 'package:equatable/equatable.dart';
import 'song_entity.dart';

enum RepeatMode { off, all, one }

class PlayerStateEntity extends Equatable {
  final SongEntity? currentSong;
  final List<SongEntity> queue;
  final int currentIndex;
  final bool isPlaying;
  final bool isShuffled;
  final RepeatMode repeatMode;
  final Duration position;
  final Duration duration;
  final double speed;
  final bool isLoading;
  final String? error;
  final int? sleepTimerMinutes;

  const PlayerStateEntity({
    this.currentSong,
    this.queue = const [],
    this.currentIndex = 0,
    this.isPlaying = false,
    this.isShuffled = false,
    this.repeatMode = RepeatMode.off,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.isLoading = false,
    this.error,
    this.sleepTimerMinutes,
  });

  PlayerStateEntity copyWith({
    SongEntity? currentSong,
    List<SongEntity>? queue,
    int? currentIndex,
    bool? isPlaying,
    bool? isShuffled,
    RepeatMode? repeatMode,
    Duration? position,
    Duration? duration,
    double? speed,
    bool? isLoading,
    String? error,
    int? sleepTimerMinutes,
  }) {
    return PlayerStateEntity(
      currentSong: currentSong ?? this.currentSong,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isShuffled: isShuffled ?? this.isShuffled,
      repeatMode: repeatMode ?? this.repeatMode,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      sleepTimerMinutes: sleepTimerMinutes,
    );
  }

  double get progress {
    if (duration.inMilliseconds == 0) return 0;
    return position.inMilliseconds / duration.inMilliseconds;
  }

  bool get hasPrevious => currentIndex > 0;
  bool get hasNext => currentIndex < queue.length - 1;

  @override
  List<Object?> get props => [
        currentSong?.id,
        currentIndex,
        isPlaying,
        isShuffled,
        repeatMode,
        position,
        duration,
        speed,
        isLoading,
        error,
      ];
}
