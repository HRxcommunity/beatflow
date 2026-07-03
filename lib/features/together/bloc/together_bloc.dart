import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../domain/entities/session_entity.dart';
import '../services/together_auth_service.dart';
import '../services/together_session_service.dart';
import '../services/together_storage_service.dart';
import '../services/together_chat_media_service.dart';
import '../../youtube/youtube_service.dart';
import '../../../domain/entities/song_entity.dart';
import '../../../services/audio_handler.dart';
import '../../../service_locator.dart';

// ══════════════════════════════════════════════════════════════
//  EVENTS
// ══════════════════════════════════════════════════════════════

abstract class TogetherEvent extends Equatable {
  const TogetherEvent();
  @override
  List<Object?> get props => [];
}

class TogetherSignIn extends TogetherEvent {
  final String displayName;
  const TogetherSignIn(this.displayName);
  @override
  List<Object?> get props => [displayName];
}

class TogetherCreateSession extends TogetherEvent {
  final SongEntity song;
  final int positionMs;
  final bool isPlaying;
  final bool isPublic;
  final String country;
  const TogetherCreateSession({
    required this.song,
    required this.positionMs,
    required this.isPlaying,
    this.isPublic = false,
    this.country  = '',
  });
  @override
  List<Object?> get props => [song.id, positionMs, isPlaying, isPublic];
}

class TogetherJoinSession extends TogetherEvent {
  final String code;
  const TogetherJoinSession(this.code);
  @override
  List<Object?> get props => [code];
}

class TogetherLeaveSession extends TogetherEvent {}

class _TogetherSessionUpdated extends TogetherEvent {
  final SessionEntity? session;
  const _TogetherSessionUpdated(this.session);
  @override
  List<Object?> get props => [session];
}

class TogetherPushPlayback extends TogetherEvent {
  final SongEntity song;
  final int positionMs;
  final bool isPlaying;
  // TASK-5: minimal queue snapshot for syncing "Up Next" to guests.
  // null = don't update queue in Firestore (seek-only or play/pause update).
  final List<SongEntity>? queue;
  final int queueIndex;
  const TogetherPushPlayback({
    required this.song,
    required this.positionMs,
    required this.isPlaying,
    this.queue,
    this.queueIndex = 0,
  });
  @override
  List<Object?> get props => [song.id, positionMs, isPlaying, queueIndex, queue?.length];
}

class TogetherPushSeek extends TogetherEvent {
  final int positionMs;
  const TogetherPushSeek(this.positionMs);
  @override
  List<Object?> get props => [positionMs];
}

class TogetherClearError extends TogetherEvent {}

class _TogetherUploadProgress extends TogetherEvent {
  final double progress;
  const _TogetherUploadProgress(this.progress);
  @override
  List<Object?> get props => [progress];
}

// ── Internal event to set streamUrl after upload completes ──
class _TogetherStreamUrlReady extends TogetherEvent {
  final String songId;
  final String streamUrl;
  const _TogetherStreamUrlReady(this.songId, this.streamUrl);
  @override
  List<Object?> get props => [songId, streamUrl];
}

// ── Internal event to safely set uploading status via add() ──
class _TogetherSetUploading extends TogetherEvent {
  const _TogetherSetUploading();
}

// ── Internal event to safely handle upload failure via add() ──
class _TogetherUploadFailed extends TogetherEvent {
  const _TogetherUploadFailed();
}

// ── [D] Internal event: guest seek guard resolved ────────────
class _TogetherGuestSeekSafe extends TogetherEvent {
  final String streamUrl;
  const _TogetherGuestSeekSafe(this.streamUrl);
  @override
  List<Object?> get props => [streamUrl];
}

// ── Chat ──────────────────────────────────────────────────────
class TogetherSendChat extends TogetherEvent {
  final String text;
  final ChatMessageType type;
  const TogetherSendChat(this.text, {this.type = ChatMessageType.text});
  @override
  List<Object?> get props => [text, type];
}

// ── Media chat ────────────────────────────────────────────────
class TogetherSendImage extends TogetherEvent {}
class TogetherSendFile  extends TogetherEvent {}

// ── YouTube in Together ───────────────────────────────────────
class TogetherSearchYoutube extends TogetherEvent {
  final String query;
  const TogetherSearchYoutube(this.query);
  @override
  List<Object?> get props => [query];
}

class TogetherPlayYoutube extends TogetherEvent {
  final YoutubeTrack track;
  const TogetherPlayYoutube(this.track);
  @override
  List<Object?> get props => [track.videoId];
}

/// Like TogetherPlayYoutube but opens a YouTube video player instead of audio.
/// Host and guests both see an embedded YouTube video player.
class TogetherPlayYoutubeVideo extends TogetherEvent {
  final YoutubeTrack track;
  const TogetherPlayYoutubeVideo(this.track);
  @override
  List<Object?> get props => [track.videoId];
}

class TogetherShareYoutubeTrack extends TogetherEvent {
  final YoutubeTrack track;
  const TogetherShareYoutubeTrack(this.track);
  @override
  List<Object?> get props => [track.videoId];
}

/// Fired by the WebView player when YouTube IFrame fires an embed error
/// (150/152 = embedding disabled, 101 = same, 100 = video not found).
/// The bloc marks this videoId as failed and auto-retries with the next
/// embeddable candidate from ytResults.
class TogetherYtEmbedError extends TogetherEvent {
  final String videoId;
  final String errorCode;
  const TogetherYtEmbedError(this.videoId, this.errorCode);
  @override
  List<Object?> get props => [videoId, errorCode];
}

class _YoutubeSearchDone extends TogetherEvent {
  final List<YoutubeTrack> results;
  const _YoutubeSearchDone(this.results);
  @override
  List<Object?> get props => [results.length];
}

/// Fired by host's YouTube WebView when onStateChange fires (play/pause/seek).
/// Pushes isPlaying + positionMs to Firestore so guests can sync.
class TogetherPushYtPlayState extends TogetherEvent {
  final bool isPlaying;
  final int positionMs;
  const TogetherPushYtPlayState(this.isPlaying, this.positionMs);
  @override
  List<Object?> get props => [isPlaying, positionMs];
}

// ── Video Call ────────────────────────────────────────────────
class TogetherStartVideoCall extends TogetherEvent {}
class TogetherEndVideoCall   extends TogetherEvent {}
class TogetherJoinVideoCall  extends TogetherEvent {}

// ── Host change request ───────────────────────────────────────
class TogetherRequestHostChange extends TogetherEvent {}
class TogetherAcceptHostChange  extends TogetherEvent {}
class TogetherRejectHostChange  extends TogetherEvent {}

// ── Online presence (app lifecycle) ──────────────────────────
class TogetherSetOnlineStatus extends TogetherEvent {
  final bool isOnline;
  const TogetherSetOnlineStatus(this.isOnline);
  @override
  List<Object?> get props => [isOnline];
}

// ── Internal: Firebase async auth restoration ─────────────────
// BUG-SOCIAL-AUTH FIX: Firebase Auth restores the user asynchronously
// after app restart. _restoreAuth() may run before currentUser is available,
// leaving TogetherBloc.uid = null. This event is fired by the authStateChanges
// stream listener so SocialScreen can auto-init without requiring Together tab.
class _TogetherAuthRestored extends TogetherEvent {
  final String uid;
  const _TogetherAuthRestored(this.uid);
  @override
  List<Object?> get props => [uid];
}

// ══════════════════════════════════════════════════════════════
//  STATE
// ══════════════════════════════════════════════════════════════

enum TogetherStatus { idle, loading, uploading, active, error }

class TogetherState extends Equatable {
  final TogetherStatus status;
  final SessionEntity? session;
  final bool isOwner;
  final String? uid;
  final String? displayName;
  final String? error;
  final double uploadProgress;
  final bool showChat;
  // ── YouTube ──────────────────────────────────────────────────
  final List<YoutubeTrack> ytResults;
  final bool ytSearching;
  final bool ytLoading;   // resolving stream URL
  // ── Media upload ─────────────────────────────────────────────
  final bool mediaUploading;
  // ── Video call ───────────────────────────────────────────────
  final bool inVideoCall;
  // ── YouTube embed failure tracking ───────────────────────────
  /// Video IDs that fired error 150/152 in the WebView player.
  /// Used to skip already-failed candidates on auto-retry.
  final Set<String> ytFailedIds;

  const TogetherState({
    this.status = TogetherStatus.idle,
    this.session,
    this.isOwner = false,
    this.uid,
    this.displayName,
    this.error,
    this.uploadProgress = 0.0,
    this.showChat = false,
    this.ytResults = const [],
    this.ytSearching = false,
    this.ytLoading = false,
    this.mediaUploading = false,
    this.inVideoCall = false,
    this.ytFailedIds = const {},
  });

  // TASK-1 FIX: was `status == active && session != null`.
  // When host's song changes → _uploadSongAudio fires _TogetherSetUploading →
  // status = uploading → isInSession was false → LandingScreen shown = "session left".
  // Fix: both active AND uploading are valid in-session states.
  bool get isInSession  => session != null &&
                           (status == TogetherStatus.active ||
                            status == TogetherStatus.uploading);
  // isLoading is now ONLY the initial create/join loading (not upload).
  // This prevents the Create Session button being disabled during uploads.
  bool get isLoading    => status == TogetherStatus.loading;
  bool get isUploading  => status == TogetherStatus.uploading;

  TogetherState copyWith({
    TogetherStatus? status,
    SessionEntity? session,
    bool? isOwner,
    String? uid,
    String? displayName,
    String? error,
    double? uploadProgress,
    bool? showChat,
    bool clearSession = false,
    bool clearError   = false,
    List<YoutubeTrack>? ytResults,
    bool? ytSearching,
    bool? ytLoading,
    bool? mediaUploading,
    bool? inVideoCall,
    Set<String>? ytFailedIds,
  }) {
    return TogetherState(
      status:         status         ?? this.status,
      session:        clearSession   ? null : (session ?? this.session),
      isOwner:        isOwner        ?? this.isOwner,
      uid:            uid            ?? this.uid,
      displayName:    displayName    ?? this.displayName,
      error:          clearError ? null : (error ?? this.error), // BUG-SM01 FIX: preserve existing error
      uploadProgress: uploadProgress ?? this.uploadProgress,
      showChat:       showChat       ?? this.showChat,
      ytResults:      ytResults      ?? this.ytResults,
      ytSearching:    ytSearching    ?? this.ytSearching,
      ytLoading:      ytLoading      ?? this.ytLoading,
      mediaUploading: mediaUploading ?? this.mediaUploading,
      inVideoCall:    inVideoCall    ?? this.inVideoCall,
      ytFailedIds:    ytFailedIds    ?? this.ytFailedIds,
    );
  }

  @override
  List<Object?> get props => [
        status,
        session?.sessionId,
        session?.positionMs,
        session?.isPlaying,
        session?.songId,
        session?.streamUrl,
        session?.memberCount,
        session?.chatMessages.length,
        session?.pendingHostRequest?.status,
        session?.ownerId,
        isOwner,
        uid,
        displayName,
        error,
        uploadProgress,
        showChat,
        // ── YouTube ── MUST be here or bloc never emits yt state changes
        ytResults.length,   // length so list identity doesn't block emit
        ytSearching,
        ytLoading,
        ytFailedIds.length, // track failed embed IDs
        // ── Media upload ──
        mediaUploading,
        inVideoCall,
      ];
}

// ══════════════════════════════════════════════════════════════
//  BLOC
// ══════════════════════════════════════════════════════════════

class TogetherBloc extends Bloc<TogetherEvent, TogetherState> {
  final TogetherAuthService       _auth;
  final TogetherSessionService    _sessionService;
  final TogetherStorageService    _storageService;
  final TogetherChatMediaService  _chatMediaService = TogetherChatMediaService();
  final YoutubeService            _youtubeService   = YoutubeService();

  // Uploaded URLs cache — persisted to Hive so same song is never re-uploaded
  final Map<String, String> _uploadedUrls = {};
  // Track in-progress uploads to avoid duplicate concurrent uploads
  final Set<String> _uploadingNow = {};

  // Hive box name for persistent URL cache
  static const _kUrlCacheBox = 'together_url_cache';

  // [D] Preview window: how close to end (ms) before we delay the full-URL switch
  static const _kSeekGuardMs = 10000; // 10 seconds

  StreamSubscription<SessionEntity?>? _sessionSub;
  StreamSubscription?                 _authSub;

  TogetherBloc({
    required TogetherAuthService    auth,
    required TogetherSessionService sessionService,
    required TogetherStorageService storageService,
  })  : _auth           = auth,
        _sessionService = sessionService,
        _storageService = storageService,
        super(const TogetherState()) {
    on<TogetherSignIn>            (_onSignIn);
    on<TogetherCreateSession>     (_onCreateSession);
    on<TogetherJoinSession>       (_onJoinSession);
    on<TogetherLeaveSession>      (_onLeaveSession);
    on<_TogetherSessionUpdated>   (_onSessionUpdated);
    on<TogetherPushPlayback>      (_onPushPlayback);
    on<TogetherPushSeek>          (_onPushSeek);
    on<TogetherClearError>        ((_, emit) => emit(state.copyWith(clearError: true)));
    on<_TogetherUploadProgress>   ((e, emit) => emit(state.copyWith(uploadProgress: e.progress)));
    on<_TogetherStreamUrlReady>   (_onStreamUrlReady);
    on<_TogetherSetUploading>     ((_, emit) => emit(state.copyWith(status: TogetherStatus.uploading, uploadProgress: 0.0)));
    on<_TogetherUploadFailed>     ((_, emit) => emit(state.copyWith(status: TogetherStatus.active, uploadProgress: 0.0, error: 'Audio upload failed. Check your storage rules and internet connection.')));
    on<_TogetherGuestSeekSafe>    (_onGuestSeekSafe);
    on<TogetherSendChat>          (_onSendChat);
    on<TogetherSendImage>         (_onSendImage);
    on<TogetherSendFile>          (_onSendFile);
    on<TogetherSearchYoutube>     (_onSearchYoutube);
    on<TogetherPlayYoutube>       (_onPlayYoutube);
    on<TogetherPlayYoutubeVideo>  (_onPlayYoutubeVideo);
    on<TogetherShareYoutubeTrack> (_onShareYoutubeTrack);
    on<TogetherYtEmbedError>      (_onYtEmbedError);
    // Reset failed IDs when new search results arrive (fresh query = fresh slate)
    on<_YoutubeSearchDone>        ((e, emit) => emit(state.copyWith(
      ytResults: e.results, ytSearching: false, ytFailedIds: const {},
    )));
    on<TogetherPushYtPlayState>   (_onPushYtPlayState);
    on<TogetherStartVideoCall>    (_onStartVideoCall);
    on<TogetherEndVideoCall>      (_onEndVideoCall);
    on<TogetherJoinVideoCall>     ((_, emit) => emit(state.copyWith(inVideoCall: true)));
    on<TogetherRequestHostChange> (_onRequestHostChange);
    on<TogetherAcceptHostChange>  (_onAcceptHostChange);
    on<TogetherRejectHostChange>  (_onRejectHostChange);
    on<TogetherSetOnlineStatus>   (_onSetOnlineStatus);
    // BUG-SOCIAL-AUTH FIX: async auth restoration from Firebase
    on<_TogetherAuthRestored>     ((e, emit) {
      if (state.uid == null) {
        emit(state.copyWith(uid: e.uid, displayName: _auth.displayName));
      }
    });

    _restoreAuth();
  }

  void _restoreAuth() {
    if (_auth.isSignedIn) {
      emit(state.copyWith(uid: _auth.uid, displayName: _auth.displayName));
    }
    // BUG-SOCIAL-AUTH FIX: Firebase Auth restores the signed-in user from disk
    // asynchronously — currentUser may be null on the first frame even if the
    // user was signed in during a previous session. Listen to authStateChanges
    // so we pick up the user the moment Firebase finishes restoring, without
    // requiring the user to open the Together tab first.
    _authSub = _auth.authStateChanges.listen((user) {
      if (user != null && state.uid == null) {
        add(_TogetherAuthRestored(user.uid));
      }
    });
    // Restore persisted upload URL cache so same song is never re-uploaded
    _loadUrlCache();
  }

  void _loadUrlCache() {
    try {
      if (Hive.isBoxOpen(_kUrlCacheBox)) {
        final box = Hive.box<String>(_kUrlCacheBox);
        for (final key in box.keys) {
          final val = box.get(key);
          if (val != null && val.isNotEmpty) {
            _uploadedUrls[key.toString()] = val;
          }
        }
        debugPrint('[Together] Restored ${_uploadedUrls.length} cached URLs from Hive');
      } else {
        Hive.openBox<String>(_kUrlCacheBox).then((box) {
          for (final key in box.keys) {
            final val = box.get(key);
            if (val != null && val.isNotEmpty) {
              _uploadedUrls[key.toString()] = val;
            }
          }
          debugPrint('[Together] Loaded ${_uploadedUrls.length} cached URLs from Hive');
        }).catchError((e) {
          debugPrint('[Together] Hive cache load error: $e');
        });
      }
    } catch (e) {
      debugPrint('[Together] _loadUrlCache error (non-critical): $e');
    }
  }

  void _saveUrlToCache(String songId, String url) {
    try {
      final box = Hive.isBoxOpen(_kUrlCacheBox)
          ? Hive.box<String>(_kUrlCacheBox)
          : null;
      box?.put(songId, url);
      debugPrint('[Together] Cached URL for songId $songId');
    } catch (e) {
      debugPrint('[Together] _saveUrlToCache error (non-critical): $e');
    }
  }

  // ── Sign in ────────────────────────────────────────────────
  Future<void> _onSignIn(
      TogetherSignIn event, Emitter<TogetherState> emit) async {
    emit(state.copyWith(status: TogetherStatus.loading, clearError: true));
    try {
      final user = await _auth.signInAnonymously(displayName: event.displayName);
      if (user == null) {
        emit(state.copyWith(
            status: TogetherStatus.error,
            error:  'Sign-in failed. Try again.'));
        return;
      }
      emit(state.copyWith(
        status:      TogetherStatus.idle,
        uid:         user.uid,
        displayName: _auth.displayName,
      ));
    } catch (e) {
      emit(state.copyWith(status: TogetherStatus.error, error: e.toString()));
    }
  }

  // ── Create ─────────────────────────────────────────────────
  Future<void> _onCreateSession(
      TogetherCreateSession event, Emitter<TogetherState> emit) async {
    final uid = _auth.uid;
    if (uid == null) {
      emit(state.copyWith(
          status: TogetherStatus.error, error: 'Please sign in first.'));
      return;
    }

    emit(state.copyWith(status: TogetherStatus.loading, clearError: true));

    final songId = event.song.id.toString();

    // Pass existing streamUrl if we already uploaded this song before
    final existingUrl = _uploadedUrls[songId];

    final session = await _sessionService.createSession(
      uid:            uid,
      ownerName:      _auth.displayName,
      songId:         songId,
      songTitle:      event.song.title,
      songArtist:     event.song.artist,
      songData:       event.song.data,
      streamUrl:      existingUrl,
      songDurationMs: event.song.duration,
      positionMs:     event.positionMs,
      isPlaying:      event.isPlaying,
      isVideo:        event.song.isVideo,
      isPublic:       event.isPublic,
      country:        event.country,
    );

    if (session == null) {
      emit(state.copyWith(
          status: TogetherStatus.error,
          error:  'Could not create session. Check connection.'));
      return;
    }

    _subscribeToSession(session.sessionId);
    emit(state.copyWith(
      status:  TogetherStatus.active,
      session: session,
      isOwner: true,
    ));
    // Fix 3: Start presence heartbeat for owner (crash-safe TTL)
    _sessionService.startPresenceHeartbeat(
      sessionId:   session.sessionId,
      uid:         state.uid ?? '',
      displayName: state.displayName ?? '',
    );

    // Only upload local files — YouTube/http songs already have streamUrl
    final isLocalFile = !event.song.data.startsWith('http');

    if (existingUrl == null && isLocalFile) {
      if (event.song.isVideo) {
        // MP4 video — use video upload pipeline
        _uploadSongVideo(
          sessionId:     session.sessionId,
          songId:        songId,
          filePath:      event.song.data,
          songDurationMs: event.song.duration,
        );
      } else {
        // Audio file — use existing audio upload pipeline
        _uploadSongAudio(
          sessionId:     session.sessionId,
          songId:        songId,
          filePath:      event.song.data,
          songDurationMs: event.song.duration,
        );
      }
      // BUG-021 FIX: Only auto-search if the host hasn't already searched for
      // something deliberately. Previously this unconditionally overwrote any
      // existing YouTube search results the host was browsing.
      // BUG-Y02 FIX: only auto-search once per session; checking ytResults.isEmpty
      // caused an infinite loop when the search returned no results and the
      // host changed songs — each song change re-triggered a failing search.
      if (!_ytAutoSearchDone && !event.song.isVideo) {
        _ytAutoSearchDone = true;
        unawaited(_autoSearchYoutube(event.song.title, event.song.artist));
      }
    } else if (!isLocalFile) {
      debugPrint('[Together] Song is already a stream URL, no upload needed');
    } else {
      debugPrint('[Together] Using cached streamUrl for $songId');
    }
  }

  /// Background YouTube search triggered automatically when host shares a
  /// local song — results appear in the YouTube tab so host can switch instantly.
  Future<void> _autoSearchYoutube(String title, String artist) async {
    try {
      final query = '$title $artist'.trim();
      debugPrint('[Together] Auto-searching YouTube for: $query');
      final results = await _youtubeService.search(query, limit: 5);
      if (!isClosed && results.isNotEmpty) {
        add(_YoutubeSearchDone(results));
        debugPrint('[Together] Auto-search found ${results.length} YouTube results');
      }
    } catch (e) {
      debugPrint('[Together] Auto-search failed (non-critical): $e');
    }
  }

  // ── Upload audio ────────────────────────────────────────────
  /// PROGRESSIVE UPLOAD:
  /// Phase 1 — Upload smart bitrate-aware chunk (≈20 sec) → guests start playing fast
  /// Phase 2 — Upload full file in background → guests auto-switch to full URL
  void _uploadSongAudio({
    required String sessionId,
    required String songId,
    required String filePath,
    int songDurationMs = 0,  // BUG-013: pass actual duration for accurate chunk sizing
  }) {
    if (_uploadingNow.contains(songId)) {
      debugPrint('[Together] Upload already in progress for $songId, skipping');
      return;
    }
    if (_uploadedUrls.containsKey(songId)) {
      final url = _uploadedUrls[songId]!;
      debugPrint('[Together] Reusing cached URL for $songId');
      _sessionService.updateStreamUrl(sessionId: sessionId, streamUrl: url);
      return;
    }

    _uploadingNow.add(songId);
    add(const _TogetherUploadProgress(0.05)); // Show 5% immediately so bar is visible
    add(const _TogetherSetUploading());

    unawaited(_progressiveUpload(
      sessionId:     sessionId,
      songId:        songId,
      filePath:      filePath,
      songDurationMs: songDurationMs,
    ));
  }

  /// Two-phase progressive upload:
  ///   Phase 1: smart bitrate-aware preview chunk → Firestore updated → guests play NOW
  ///   Phase 2: full file                         → Firestore updated → guests switch
  Future<void> _progressiveUpload({
    required String sessionId,
    required String songId,
    required String filePath,
    int songDurationMs = 0,  // BUG-013: forwarded to uploadPreview
  }) async {
    try {
      // ── Phase 1: Preview chunk ──────────────────────────────
      debugPrint('[Together] Phase 1: uploading preview chunk for $songId');
      // [A+C] previewBytes=null → smart bitrate detection; cancel via _cancelCompleter
      final previewUrl = await _storageService.uploadPreview(
        sessionId:     sessionId,
        filePath:      filePath,
        songDurationMs: songDurationMs, // BUG-013
        // previewBytes omitted → auto smart-chunk (~60 sec at detected bitrate)
      );

      if (isClosed) { _uploadingNow.remove(songId); return; }

      if (previewUrl != null) {
        debugPrint('[Together] Phase 1 done — guests can play preview now');
        add(const _TogetherUploadProgress(0.5)); // Phase 1 = 50%
        // _TogetherStreamUrlReady handler pushes to Firestore — no direct call needed
        add(_TogetherStreamUrlReady(songId, previewUrl));
      } else {
        debugPrint('[Together] Phase 1 failed or cancelled — continuing to full upload');
      }

      // ── Phase 2: Full file (background) ────────────────────
      debugPrint('[Together] Phase 2: uploading full file for $songId');
      final fullUrl = await _storageService.uploadAudio(
        sessionId: sessionId,
        filePath:  filePath,
        onProgress: (p) {
          // Phase 2 maps 0→1 to 50→100%
          if (!isClosed) add(_TogetherUploadProgress(0.5 + p * 0.5));
        },
      );

      _uploadingNow.remove(songId);
      if (isClosed) return;

      if (fullUrl != null) {
        debugPrint('[Together] Phase 2 done — full URL ready for $songId');
        _uploadedUrls[songId] = fullUrl;
        _saveUrlToCache(songId, fullUrl); // persist so same song never re-uploads
        // _TogetherStreamUrlReady handler pushes to Firestore — no direct call needed
        add(_TogetherStreamUrlReady(songId, fullUrl));
      } else if (previewUrl == null) {
        debugPrint('[Together] Both phases failed/cancelled for $songId');
        add(const _TogetherUploadFailed());
      } else {
        // Full failed but preview worked — keep serving preview
        debugPrint('[Together] Full upload failed, keeping preview for $songId');
        _uploadedUrls[songId] = previewUrl;
        _saveUrlToCache(songId, previewUrl);
      }

    } catch (e) {
      _uploadingNow.remove(songId);
      debugPrint('[Together] _progressiveUpload error: $e');
      if (!isClosed) add(const _TogetherUploadFailed());
    }
  }

  // ── Upload MP4 video (progressive, same 2-phase pattern) ────
  void _uploadSongVideo({
    required String sessionId,
    required String songId,
    required String filePath,
    int songDurationMs = 0,
  }) {
    if (_uploadingNow.contains(songId)) {
      debugPrint('[Together] Video upload already in progress for $songId');
      return;
    }
    if (_uploadedUrls.containsKey(songId)) {
      final url = _uploadedUrls[songId]!;
      debugPrint('[Together] Reusing cached video URL for $songId');
      _sessionService.updateStreamUrl(sessionId: sessionId, streamUrl: url);
      return;
    }

    _uploadingNow.add(songId);
    add(const _TogetherUploadProgress(0.05));
    add(const _TogetherSetUploading());

    unawaited(_progressiveVideoUpload(
      sessionId:      sessionId,
      songId:         songId,
      filePath:       filePath,
      songDurationMs: songDurationMs,
    ));
  }

  Future<void> _progressiveVideoUpload({
    required String sessionId,
    required String songId,
    required String filePath,
    int songDurationMs = 0,
  }) async {
    // BUG-VID-BUFF FIX: Removed phase-1 preview for video uploads.
    //
    // The old approach uploaded only the first N bytes of the MP4 as phase 1.
    // Most Android camera recordings write the moov atom (metadata header) at
    // the END of the file. Uploading just the beginning gives Cloudinary an
    // incomplete MP4 that lacks the moov atom. Even though Cloudinary attempts
    // to transcode the partial clip, ExoPlayer (video_player_android) would
    // stall in "buffering" because:
    //   1. The preview clip is only a few seconds long — it ends and stalls.
    //   2. The partial MP4 header may cause ExoPlayer to mis-detect the format.
    //
    // Fix: upload the full video first, then emit the stream URL once complete.
    // We add fl_progressive to the Cloudinary delivery URL so the moov atom is
    // served first (fast-start), allowing ExoPlayer to begin playback
    // immediately without waiting to download the entire file.
    //
    // Guests see "Video uploading..." until the upload completes, which is
    // better than an infinite buffering spinner on a broken partial stream.
    try {
      debugPrint('[Together] Video: uploading full MP4 for $songId (no partial preview)');
      add(const _TogetherUploadProgress(0.05));

      final fullUrl = await _storageService.uploadVideo(
        sessionId:  sessionId,
        filePath:   filePath,
        onProgress: (p) {
          if (!isClosed) add(_TogetherUploadProgress(0.05 + p * 0.95));
        },
      );

      _uploadingNow.remove(songId);
      if (isClosed) return;

      if (fullUrl != null) {
        // Insert fl_progressive transformation so Cloudinary delivers the moov
        // atom first — this lets ExoPlayer start buffering immediately without
        // needing to download the whole file before playing.
        final streamUrl = _makeVideoStreamable(fullUrl);
        debugPrint('[Together] Video upload done for $songId → $streamUrl');
        _uploadedUrls[songId] = streamUrl;
        _saveUrlToCache(songId, streamUrl);
        add(_TogetherStreamUrlReady(songId, streamUrl));
      } else {
        debugPrint('[Together] Video upload failed for $songId');
        add(const _TogetherUploadFailed());
      }
    } catch (e) {
      _uploadingNow.remove(songId);
      debugPrint('[Together] _progressiveVideoUpload error: $e');
      if (!isClosed) add(const _TogetherUploadFailed());
    }
  }

  /// Add fl_progressive to a Cloudinary video URL so the moov atom is served
  /// at the start of the response (HTTP fast-start / moov relocation).
  /// Input:  https://res.cloudinary.com/{cloud}/video/upload/together_video/...
  /// Output: https://res.cloudinary.com/{cloud}/video/upload/fl_progressive/together_video/...
  String _makeVideoStreamable(String url) {
    const kMarker = '/video/upload/';
    final idx = url.indexOf(kMarker);
    if (idx == -1) return url; // not a Cloudinary video URL — return as-is
    // Already has transformations after /video/upload/ — prepend fl_progressive
    final afterMarker = url.substring(idx + kMarker.length);
    if (afterMarker.startsWith('fl_progressive')) return url; // already added
    return '${url.substring(0, idx + kMarker.length)}fl_progressive/$afterMarker';
  }

  // ── Stream URL ready ────────────────────────────────────────
  Future<void> _onStreamUrlReady(
      _TogetherStreamUrlReady event, Emitter<TogetherState> emit) async {
    // Cache the URL
    _uploadedUrls[event.songId] = event.streamUrl;

    final session = state.session;
    if (session == null || !state.isOwner) {
      emit(state.copyWith(status: TogetherStatus.active, uploadProgress: 1.0));
      return;
    }

    // Only update Firestore if this URL belongs to the currently playing song
    if (session.songId == event.songId) {
      debugPrint('[Together] Pushing streamUrl to Firestore for session ${session.sessionId}');
      await _sessionService.updateStreamUrl(
        sessionId: session.sessionId,
        streamUrl: event.streamUrl,
      );
    } else {
      debugPrint('[Together] Upload finished but song changed, storing URL for later');
    }

    emit(state.copyWith(status: TogetherStatus.active, uploadProgress: 1.0));
  }

  // ── [D] Guest seek guard ────────────────────────────────────
  /// When a full URL arrives from Firestore, guests near the end of the preview
  /// could experience an abrupt cut if we switch immediately.
  /// Guard: if guest is in the last [_kSeekGuardMs] of preview, wait until
  /// they're past that window before switching to the full URL.
  ///
  /// Called from [_onSessionUpdated] when streamUrl changes and guest is NOT owner.
  void _guardedSwitchToFullUrl({
    required int currentPositionMs,
    required int previewDurationMs,
    required String fullUrl,
  }) {
    final remainingMs = previewDurationMs - currentPositionMs;
    if (remainingMs > _kSeekGuardMs) {
      // Safe — guest is not near the end of preview, switch immediately
      debugPrint('[Together][D] Guest seek guard: safe to switch now (${remainingMs}ms remaining)');
      if (!isClosed) add(_TogetherGuestSeekSafe(fullUrl));
      return;
    }

    // Guest is within last 10 seconds of preview — delay switch
    final delayMs = remainingMs.clamp(0, _kSeekGuardMs) + 500; // 500ms buffer
    debugPrint('[Together][D] Guest seek guard: delaying switch by ${delayMs}ms '
        '(guest is ${remainingMs}ms from preview end)');
    Future<void>.delayed(Duration(milliseconds: delayMs)).then((_) {
      if (!isClosed) add(_TogetherGuestSeekSafe(fullUrl));
    });
  }

  /// Handles the safe-to-switch signal from [_guardedSwitchToFullUrl].
  void _onGuestSeekSafe(
      _TogetherGuestSeekSafe event, Emitter<TogetherState> emit) {
    final session = state.session;
    if (session == null) return;
    // Update the session with the full stream URL — just_audio picks it up
    debugPrint('[Together][D] Guest seek guard resolved — switching to full URL');
    emit(state.copyWith(
      session: session.copyWith(streamUrl: event.streamUrl),
    ));
  }

  // ── Join ───────────────────────────────────────────────────
  Future<void> _onJoinSession(
      TogetherJoinSession event, Emitter<TogetherState> emit) async {
    if (_auth.uid == null) {
      debugPrint('[Together] Guest not signed in — auto signing in anonymously');
      final user = await _auth.signInAnonymously(
        displayName: state.displayName?.isNotEmpty == true
            ? state.displayName!
            : 'Guest',
      );
      if (user == null) {
        emit(state.copyWith(
            status: TogetherStatus.error,
            error:  'Sign-in failed. Please try again.'));
        return;
      }
      emit(state.copyWith(uid: user.uid, displayName: _auth.displayName));
    }

    final uid = _auth.uid!;
    emit(state.copyWith(status: TogetherStatus.loading, clearError: true));
    try {
      final session = await _sessionService.joinSession(
        code:        event.code,
        uid:         uid,
        displayName: _auth.displayName,
      );
      if (session == null) {
        emit(state.copyWith(
            status: TogetherStatus.error,
            error:  'Session not found. Double-check the 6-character code.'));
        return;
      }
      final isOwner = session.ownerId == uid;
      _subscribeToSession(session.sessionId);
      emit(state.copyWith(
        status:  TogetherStatus.active,
        session: session,
        isOwner: isOwner,
      ));
      // Fix 3: Start presence heartbeat (crash-safe TTL)
      _sessionService.startPresenceHeartbeat(
        sessionId:   session.sessionId,
        uid:         uid,
        displayName: _auth.displayName,
      );
    } catch (e) {
      final errStr = e.toString();
      final String friendlyError;
      if (errStr.contains('Too many join')) {
        friendlyError = 'Too many join attempts. Please wait a minute.';
      } else if (errStr.contains('permission-denied') || errStr.contains('permission')) {
        friendlyError = 'Access denied. Check Firestore security rules.';
      } else if (errStr.contains('failed-precondition') || errStr.contains('index')) {
        friendlyError = 'Database index missing. See SETUP.md for Firestore index setup.';
      } else if (errStr.contains('unavailable') || errStr.contains('network')) {
        friendlyError = 'Network error. Check your internet connection.';
      } else {
        friendlyError = 'Join failed: $errStr';
      }
      debugPrint('[Together] _onJoinSession error: $errStr');
      emit(state.copyWith(status: TogetherStatus.error, error: friendlyError));
    }
  }

  // ── Leave ──────────────────────────────────────────────────
  Future<void> _onLeaveSession(
      TogetherLeaveSession event, Emitter<TogetherState> emit) async {
    final session = state.session;
    final uid     = _auth.uid;

    if (session == null || uid == null) {
      emit(state.copyWith(status: TogetherStatus.idle, clearSession: true));
      return;
    }

    await _sessionSub?.cancel();
    _sessionSub = null;

    // BUG-H02 FIX: stop presence heartbeat for ALL roles on leave.
    // Previously only guests stopped the heartbeat; the host's timer kept
    // firing every 30s against a deleted Firestore document.
    _sessionService.stopPresenceHeartbeat(
      sessionId:   session.sessionId,
      uid:         uid,
      displayName: _auth.displayName,
    );

    if (state.isOwner) {
      // [C] Cancel any active upload before leaving
      _storageService.cancelActiveUpload();
      debugPrint('[Together] Cancelled active upload on session leave');

      // Delete Cloudinary files via Vercel function (fire-and-forget)
      unawaited(_storageService.deleteSessionAudio(session.sessionId));
      // Clear in-memory tracking (but keep Hive cache — avoids re-upload next time)
      _uploadingNow.clear();
    }

    await _sessionService.leaveSession(
      sessionId: session.sessionId,
      uid:       uid,
      isOwner:   state.isOwner,
    );
    _ytAutoSearchDone = false; // BUG-Y02 FIX: reset for next session
    emit(state.copyWith(
      status:         TogetherStatus.idle,
      clearSession:   true,
      isOwner:        false,
      uploadProgress: 0.0,
      showChat:       false,
    ));
  }

  // ── Session stream update ──────────────────────────────────
  void _onSessionUpdated(
      _TogetherSessionUpdated event, Emitter<TogetherState> emit) {
    if (event.session == null) {
      _sessionSub?.cancel();
      _sessionSub = null;
      emit(state.copyWith(
        status:       TogetherStatus.idle,
        clearSession: true,
        isOwner:      false,
        error:        state.isOwner ? null : 'Host ended the session.',
      ));
      return;
    }

    // Dynamically re-evaluate isOwner (host may have transferred)
    final newIsOwner     = event.session!.ownerId == _auth.uid;
    final oldIsOwner     = state.isOwner;
    final oldStreamUrl   = state.session?.streamUrl;
    final newStreamUrl   = event.session!.streamUrl;
    final streamUrlChanged = newStreamUrl != null &&
                             newStreamUrl.isNotEmpty &&
                             newStreamUrl != oldStreamUrl;

    // FIX (Bug 1): Old host just lost ownership (host transfer accepted).
    // We emit isOwner=false cleanly here. The sync listener will reset
    // guest state on this transition, preventing the repeat-song loop.
    // We also cancel any in-progress upload since we're no longer host.
    if (oldIsOwner && !newIsOwner) {
      debugPrint('[Together] Host transfer detected — old host is now a guest. Resetting owner state.');
      _storageService.cancelActiveUpload();
      _uploadingNow.clear();
      emit(state.copyWith(
        session: event.session,
        isOwner: false,
      ));
      return;
    }

    // [D] Guest seek guard: if full URL just arrived and we're a guest,
    // check if guest is near the end of preview before switching.
    if (!newIsOwner && streamUrlChanged) {
      // BUG-003 FIX: state.session?.positionMs is what the HOST wrote to
      // Firestore — it could be 30-60 seconds behind the guest's actual
      // position due to elapsed-time playback. Use the player's live position.
      final audioHandler   = ServiceLocator.instance.audioHandler;
      final currentPosMs   = audioHandler.player.position.inMilliseconds;
      final songDurationMs = state.session?.songDurationMs ?? 0;

      // We only apply the guard when the old URL was a preview (shorter content).
      // Heuristic: if there was already a URL and the new one is different, it's
      // the full-file upgrade. songDurationMs is the full song length from Firestore.
      final isUpgrade = oldStreamUrl != null && oldStreamUrl.isNotEmpty;
      if (isUpgrade && songDurationMs > 0) {
        // BUG-017 FIX: use songDurationMs to cap the estimate for short songs.
        // If the full song is <= 60s, the whole song IS the preview.
        // For longer songs, 60s is still our best estimate without storing
        // the actual preview chunk duration alongside the URL in Firestore.
        final estimatedPreviewMs = songDurationMs < 60000 ? songDurationMs : 60000;
        _guardedSwitchToFullUrl(
          currentPositionMs: currentPosMs,
          previewDurationMs: estimatedPreviewMs,
          fullUrl:           newStreamUrl,
        );
        // Emit session without the new streamUrl for now — guard will emit it later
        emit(state.copyWith(
          session: event.session!.copyWith(streamUrl: oldStreamUrl),
          isOwner: newIsOwner,
        ));
        return;
      }
    }

    emit(state.copyWith(
      session: event.session,
      isOwner: newIsOwner,
    ));
  }

  // ── Push playback ──────────────────────────────────────────
  Future<void> _onPushPlayback(
      TogetherPushPlayback event, Emitter<TogetherState> emit) async {
    final session = state.session;
    if (session == null || !state.isOwner) return;

    final newSongId = event.song.id.toString();

    // [C] If song changed and upload is in progress, cancel it first
    if (newSongId != session.songId && _uploadingNow.isNotEmpty) {
      debugPrint('[Together][C] Song changed — cancelling active upload for old song');
      _storageService.cancelActiveUpload();
      _uploadingNow.clear(); // old song upload is aborted
    }

    // If song changed, trigger upload ONLY if no cached URL and it's a local file.
    // BUG-VID02 FIX: use video upload pipeline for MP4 files so guests receive
    // the video stream (not a broken audio-only chunk).
    if (newSongId != session.songId) {
      final isLocalFile = !event.song.data.startsWith('http');
      if (isLocalFile && !_uploadedUrls.containsKey(newSongId) && !_uploadingNow.contains(newSongId)) {
        if (event.song.isVideo) {
          _uploadSongVideo(
            sessionId:      session.sessionId,
            songId:         newSongId,
            filePath:       event.song.data,
            songDurationMs: event.song.duration,
          );
        } else {
          _uploadSongAudio(
            sessionId:     session.sessionId,
            songId:        newSongId,
            filePath:      event.song.data,
            songDurationMs: event.song.duration,
          );
        }
      }
    }

    // Always use cached URL — never send null when we have a URL
    final streamUrl = _uploadedUrls[newSongId];

    // TASK-5: Serialize queue for Firestore sync (display-only, no file paths)
    final queueJson = event.queue != null
        ? _serializeQueue(event.queue!, event.queueIndex)
        : null;

    try {
      await _sessionService.pushPlaybackState(
        sessionId:      session.sessionId,
        songId:         newSongId,
        songTitle:      event.song.title,
        songArtist:     event.song.artist,
        songData:       event.song.data,
        streamUrl:      streamUrl,
        songDurationMs: event.song.duration,
        positionMs:     event.positionMs,
        isPlaying:      event.isPlaying,
        // BUG-VID03 FIX: pass isVideo so guests see the video card
        // (was always defaulting to false, hiding the video player card)
        isVideo:        event.song.isVideo,
        queue:          queueJson, // TASK-5
      );
    } catch (e) {
      debugPrint('[Together] pushPlayback error: $e');
    }
  }

  // TASK-5: Build minimal queue JSON — title/artist/duration only.
  // NO file paths (guests can't use local paths).
  // Capped at 200 items to stay well within Firestore 1MB doc limit.
  List<Map<String, dynamic>> _serializeQueue(
      List<SongEntity> queue, int currentIndex) {
    final capped = queue.length > 200 ? queue.sublist(0, 200) : queue;
    return capped.asMap().entries.map((e) => {
      'idx':        e.key,
      'id':         e.value.id,
      'title':      e.value.title,
      'artist':     e.value.artist,
      'durationMs': e.value.duration,
      'isVideo':    e.value.isVideo,
      'isCurrent':  e.key == currentIndex,
    }).toList();
  }

  // ── Push seek ──────────────────────────────────────────────
  Future<void> _onPushSeek(
      TogetherPushSeek event, Emitter<TogetherState> emit) async {
    final session = state.session;
    if (session == null || !state.isOwner) return;
    try {
      await _sessionService.pushSeek(
        sessionId:  session.sessionId,
        positionMs: event.positionMs,
      );
    } catch (e) {
      debugPrint('[Together] pushSeek error: $e');
    }
  }

  // ── Send chat ──────────────────────────────────────────────
  Future<void> _onSendChat(
      TogetherSendChat event, Emitter<TogetherState> emit) async {
    final session = state.session;
    final uid     = _auth.uid;
    final name    = _auth.displayName;
    if (session == null || uid == null) return;
    try {
      await _sessionService.sendChatMessage(
        sessionId:   session.sessionId,
        uid:         uid,
        displayName: name,
        text:        event.text,
        type:        event.type,  // FIX: pass type (emoji, text, etc.)
      );
    } catch (e) {
      debugPrint('[Together] sendChat error: $e');
    }
  }

  // ── Request host change ────────────────────────────────────
  Future<void> _onRequestHostChange(
      TogetherRequestHostChange event, Emitter<TogetherState> emit) async {
    final session = state.session;
    final uid     = _auth.uid;
    final name    = _auth.displayName;
    if (session == null || uid == null || state.isOwner) return;
    try {
      await _sessionService.requestHostChange(
        sessionId:     session.sessionId,
        requesterUid:  uid,
        requesterName: name,
      );
    } catch (e) {
      debugPrint('[Together] requestHostChange error: $e');
    }
  }

  // ── Accept host change ─────────────────────────────────────
  Future<void> _onAcceptHostChange(
      TogetherAcceptHostChange event, Emitter<TogetherState> emit) async {
    final session = state.session;
    if (session == null || !state.isOwner) return;
    final req = session.pendingHostRequest;
    if (req == null) return;
    try {
      await _sessionService.acceptHostChange(
        sessionId:    session.sessionId,
        newOwnerUid:  req.requesterUid,
        newOwnerName: req.requesterName,
      );
      // isOwner will update via stream
    } catch (e) {
      debugPrint('[Together] acceptHostChange error: $e');
    }
  }

  // ── Reject host change ─────────────────────────────────────
  Future<void> _onRejectHostChange(
      TogetherRejectHostChange event, Emitter<TogetherState> emit) async {
    final session = state.session;
    if (session == null || !state.isOwner) return;
    try {
      await _sessionService.rejectHostChange(sessionId: session.sessionId);
    } catch (e) {
      debugPrint('[Together] rejectHostChange error: $e');
    }
  }

  // ── Subscription helper ────────────────────────────────────
  void _subscribeToSession(String sessionId) {
    _sessionSub?.cancel();
    _sessionSub = _sessionService
        .sessionStream(sessionId)
        .listen((s) => add(_TogetherSessionUpdated(s)));
  }

  // ── Send image in chat ──────────────────────────────────────
  Future<void> _onSendImage(
      TogetherSendImage event, Emitter<TogetherState> emit) async {
    final session = state.session;
    final uid     = _auth.uid;
    if (session == null || uid == null) return;

    emit(state.copyWith(mediaUploading: true, error: null));
    try {
      final result = await _chatMediaService.pickAndUploadImage(
        sessionId:  session.sessionId,
        onProgress: (_) {},
      );
      if (result == null) {
        emit(state.copyWith(mediaUploading: false));
        return;
      }
      await _sessionService.sendMediaMessage(
        sessionId:   session.sessionId,
        uid:         uid,
        displayName: _auth.displayName,
        mediaUrl:    result.url,
        isImage:     result.isImage,
        fileName:    result.fileName,
      );
    } catch (e) {
      debugPrint('[Together] sendImage error: $e');
      final msg = e.toString().contains('permission-denied')
          ? 'Storage permission denied. Check Firebase Storage rules for together_sessions/ path.'
          : e.toString().contains('object-not-found')
              ? 'Storage bucket not found. Verify Firebase bucket name in chat media service.'
              : 'Image upload failed. Check internet and try again.';
      emit(state.copyWith(error: msg));
    } finally {
      emit(state.copyWith(mediaUploading: false));
    }
  }

  // ── Send file in chat ─────────────────────────────────────
  Future<void> _onSendFile(
      TogetherSendFile event, Emitter<TogetherState> emit) async {
    final session = state.session;
    final uid     = _auth.uid;
    if (session == null || uid == null) return;

    emit(state.copyWith(mediaUploading: true, error: null));
    try {
      final result = await _chatMediaService.pickAndUploadFile(
        sessionId:  session.sessionId,
        onProgress: (_) {},
      );
      if (result == null) {
        emit(state.copyWith(mediaUploading: false));
        return;
      }
      await _sessionService.sendMediaMessage(
        sessionId:   session.sessionId,
        uid:         uid,
        displayName: _auth.displayName,
        mediaUrl:    result.url,
        isImage:     result.isImage,
        fileName:    result.fileName,
      );
    } catch (e) {
      debugPrint('[Together] sendFile error: $e');
      final msg = e.toString().contains('permission-denied')
          ? 'Storage permission denied. Check Firebase Storage rules for together_sessions/ path.'
          : e.toString().contains('object-not-found')
              ? 'Storage bucket not found. Verify Firebase bucket name in chat media service.'
              : 'File upload failed. Check internet and try again.';
      emit(state.copyWith(error: msg));
    } finally {
      emit(state.copyWith(mediaUploading: false));
    }
  }

  // Debounce guard for YouTube search — prevents stacked searches from rapid taps
  String? _lastSearchQuery;

  // BUG-Y02 FIX: prevents auto-search from re-firing on song change when
  // previous auto-search already ran (even if it returned empty results).
  bool _ytAutoSearchDone = false;

  // ── YouTube search ────────────────────────────────────────
  Future<void> _onSearchYoutube(
      TogetherSearchYoutube event, Emitter<TogetherState> emit) async {
    final query = event.query.trim();
    if (query.isEmpty) return;
    // If same query is already in-flight, skip — prevents search spam when
    // user taps search button repeatedly because loading indicator wasn't visible
    if (_lastSearchQuery == query && state.ytSearching) return;
    _lastSearchQuery = query;

    // Clear previous error and results, show loading
    emit(state.copyWith(ytSearching: true, ytResults: [], clearError: true));
    try {
      final results = await _youtubeService.search(query, limit: 20);
      if (isClosed) return;
      emit(state.copyWith(ytResults: results, ytSearching: false, clearError: true));
      if (results.isEmpty) {
        emit(state.copyWith(
          error: 'No results for "$query". Try different keywords.',
        ));
      }
      // BUG-SM02 FIX: do NOT clear _lastSearchQuery on success.
      // Keeping it set prevents an accidental double-tap from firing a second
      // identical search within milliseconds of the first completing.
      // It resets to null only on error (below) so the user can retry.
    } catch (e) {
      debugPrint('[Together] ytSearch error: $e');
      _lastSearchQuery = null; // BUG-SM02 FIX: allow retry after error
      if (isClosed) return;
      emit(state.copyWith(
        ytResults:   const [],
        ytSearching: false,
        error: 'YouTube search failed. Check internet and try again.',
      ));
    }
  }

  // ── YouTube play (host streams to session) ────────────────
  Future<void> _onPlayYoutube(
      TogetherPlayYoutube event, Emitter<TogetherState> emit) async {
    final session = state.session;
    if (session == null || !state.isOwner) return;

    emit(state.copyWith(ytLoading: true));
    try {
      final track = await _youtubeService.resolveTrack(event.track.videoId);
      if (track == null || track.streamUrl == null) {
        emit(state.copyWith(
          ytLoading: false,
          error: 'Could not load YouTube audio. Try another track.',
        ));
        return;
      }

      // ── Host plays YouTube locally — with retry on Source error ──
      // If local play fails (e.g. IP-lock / Source error), we retry once
      // with a fresh stream URL. Only push to Firestore when play succeeds —
      // pushing a broken URL would also break playback for all guests.
      final audioHandler = ServiceLocator.instance.audioHandler;
      bool   hostPlaySuccess = false;
      String activeStreamUrl = track.streamUrl!;

      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          await audioHandler.playYouTubeTrack(
            streamUrl:    activeStreamUrl,
            title:        track.title,
            artist:       track.artist,
            thumbnailUrl: track.thumbnailUrl,
            duration:     track.duration,
          );
          hostPlaySuccess = true;
          break;
        } catch (playErr) {
          debugPrint('[Together] Host YouTube local play error (attempt ${attempt + 1}): $playErr');
          if (attempt == 0) {
            // First failure → fetch a fresh stream URL and retry
            debugPrint('[Together] Retrying with fresh stream URL...');
            try {
              final freshUrl =
                  await _youtubeService.getAudioStreamUrl(event.track.videoId);
              if (freshUrl != null &&
                  freshUrl.isNotEmpty &&
                  freshUrl != activeStreamUrl) {
                activeStreamUrl = freshUrl;
                debugPrint('[Together] Got fresh URL, retrying play...');
              } else {
                debugPrint('[Together] No new URL available, giving up');
                break;
              }
            } catch (e) {
              debugPrint('[Together] Fresh URL fetch failed: $e');
              break;
            }
          }
        }
      }

      if (!hostPlaySuccess) {
        // Don't push broken URL — guests would also fail
        emit(state.copyWith(
          ytLoading: false,
          error: 'YouTube audio unavailable on this network.\nTry another track or check internet.',
        ));
        return;
      }

      // ── Push to Firestore so guests sync ──
      await _sessionService.pushPlaybackState(
        sessionId:      session.sessionId,
        songId:         track.videoId,
        songTitle:      track.title,
        songArtist:     track.artist,
        // BUG-010 FIX: store stable videoId as songData (prefixed 'yt:') instead
        // of the CDN URL. CDN URLs expire in ~6 hours — guests who join late get
        // a 403. Guests detect 'yt:' prefix and re-resolve a fresh stream URL.
        songData:       'yt:${track.videoId}',
        streamUrl:      activeStreamUrl,   // temporary CDN URL for current guests
        songDurationMs: track.duration.inMilliseconds,
        positionMs:     0,
        isPlaying:      true,
      );
      debugPrint('[Together] YouTube track pushed: ${track.title}');
    } catch (e) {
      debugPrint('[Together] playYoutube error: $e');
      // BUG-031 FIX: raw Dart exceptions like "PlayerException: (803) Source error"
      // were shown directly to users. Map common errors to friendly messages.
      final errStr = e.toString();
      final friendlyError = errStr.contains('803') || errStr.contains('Source error')
          ? 'YouTube audio unavailable. Try another track.'
          : errStr.contains('network') || errStr.contains('SocketException')
              ? 'Network error. Check your internet connection.'
              : 'YouTube play failed. Please try again.';
      emit(state.copyWith(error: friendlyError));
    } finally {
      emit(state.copyWith(ytLoading: false));
    }
  }

  // ── YouTube VIDEO play (Together — host shares video to session) ──────
  /// Pushes videoId + isVideo=true to Firestore so all guests also see the
  /// YouTube video player for this track (no audio stream needed).
  Future<void> _onPlayYoutubeVideo(
      TogetherPlayYoutubeVideo event, Emitter<TogetherState> emit) async {
    final session = state.session;
    if (session == null) return;

    final track = event.track;
    emit(state.copyWith(ytLoading: true, clearError: true));

    try {
      // Pre-validate embed availability via oEmbed API (uses _isEmbeddable helper).
      final embedCheck = await _checkEmbedAndEmitError(track, emit);
      if (!embedCheck) return; // error already emitted

      // Push isVideo=true to Firestore — guests detect this and open
      // a YouTube WebView player with the same videoId.
      // No audio stream URL needed: each guest's WebView plays YouTube directly.
      await _sessionService.pushPlaybackState(
        sessionId:      session.sessionId,
        songId:         'yt:${track.videoId}',
        songTitle:      track.title,
        songArtist:     track.artist,
        songData:       'yt:${track.videoId}',
        streamUrl:      'yt:${track.videoId}',
        songDurationMs: track.duration.inMilliseconds,
        positionMs:     0,
        isPlaying:      true,
        isVideo:        true,
      );

      debugPrint('[Together] YouTube video pushed: ${track.title} (${track.videoId})');
    } catch (e) {
      debugPrint('[Together] YouTube video push error: $e');
      emit(state.copyWith(
          error: 'Could not share YouTube video. Check connection.'));
    } finally {
      emit(state.copyWith(ytLoading: false));
    }
  }

  // ── YouTube embed error → auto-retry with next VALIDATED candidate ──────
  /// Called when the WebView YouTube IFrame fires onError (code 150/152/101).
  /// BUG-YT-RETRY FIX: previously dispatched the next candidate without
  /// pre-validating it via oEmbed, causing repeat embed-error loops when
  /// several consecutive search results are non-embeddable. Now each candidate
  /// is oEmbed-checked before dispatch; failed ones are marked and skipped.
  Future<void> _onYtEmbedError(
      TogetherYtEmbedError event, Emitter<TogetherState> emit) async {
    // Record this videoId as failed
    var failed = <String>{...state.ytFailedIds, event.videoId};
    emit(state.copyWith(ytFailedIds: failed));

    // Only auto-retry for embedding-disabled errors (not e.g. network errors)
    const embedErrCodes = {'150', '152', '101'};
    if (!embedErrCodes.contains(event.errorCode)) {
      debugPrint('[Together] YT error ${event.errorCode} on ${event.videoId} — '
          'not an embed error, skipping auto-retry.');
      return;
    }

    // Walk through remaining candidates, oEmbed-check each before retrying
    final candidates = state.ytResults.where((t) => !failed.contains(t.videoId)).toList();
    YoutubeTrack? embeddable;

    for (final candidate in candidates) {
      final ok = await _isEmbeddable(candidate.videoId);
      if (ok) {
        embeddable = candidate;
        break;
      }
      // Pre-failed via oEmbed — mark and continue
      failed = {...failed, candidate.videoId};
      debugPrint('[Together] oEmbed pre-check failed for "${candidate.title}" '
          '(${candidate.videoId}) — skipping in retry chain.');
    }

    emit(state.copyWith(ytFailedIds: failed));

    if (embeddable != null) {
      debugPrint('[Together] Embed error ${event.errorCode} on ${event.videoId}. '
          'Auto-retrying with validated: "${embeddable.title}" (${embeddable.videoId})');
      add(TogetherPlayYoutubeVideo(embeddable));
    } else {
      debugPrint('[Together] Embed error ${event.errorCode} on ${event.videoId}. '
          'No embeddable candidates remain — showing Watch on YouTube fallback.');
      // All candidates exhausted; the error overlay + "Watch on YouTube" button
      // is already visible in the WebView layer — nothing more to emit.
    }
  }

  // ── oEmbed embeddability check ────────────────────────────────
  /// Returns true if the video is embeddable (oEmbed 200), false if not
  /// (401/403/404). Returns true on timeout/network error to avoid blocking
  /// playback for a momentary connectivity issue.
  Future<bool> _isEmbeddable(String videoId) async {
    try {
      final uri = Uri.parse('https://www.youtube.com/oembed').replace(
        queryParameters: {
          'url':    'https://www.youtube.com/watch?v=$videoId',
          'format': 'json',
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return true; // network/timeout → optimistically allow
    }
  }

  // ── oEmbed check with error emit (used by _onPlayYoutubeVideo) ───────────
  /// Runs _isEmbeddable and emits a user-visible error if the video is blocked.
  /// Returns true if embeddable (caller should proceed), false if blocked
  /// (error already emitted, caller should return).
  Future<bool> _checkEmbedAndEmitError(
      YoutubeTrack track, Emitter<TogetherState> emit) async {
    try {
      final uri = Uri.parse('https://www.youtube.com/oembed').replace(
        queryParameters: {
          'url':    'https://www.youtube.com/watch?v=${track.videoId}',
          'format': 'json',
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        emit(state.copyWith(
          ytLoading: false,
          error: '❌ "${track.title}" cannot be embedded '
                 '(embedding disabled by the video owner). '
                 'Try a different video.',
        ));
        return false;
      }
      if (resp.statusCode == 404) {
        emit(state.copyWith(
          ytLoading: false,
          error: '❌ Video not found or has been deleted.',
        ));
        return false;
      }
      return true; // 200 OK or other status → proceed
    } catch (_) {
      // Timeout / network error — allow through optimistically
      debugPrint('[Together] oEmbed check failed (network), allowing through');
      return true;
    }
  }

  // ── Share YouTube track as chat card ─────────────────────
  Future<void> _onShareYoutubeTrack(
      TogetherShareYoutubeTrack event, Emitter<TogetherState> emit) async {
    final session = state.session;
    final uid     = _auth.uid;
    if (session == null || uid == null) return;
    try {
      // Stream URL is intentionally NOT fetched here — avoids the 10–15 sec
      // delay before the card appears. The URL will be resolved fresh when
      // the host taps "Play for everyone" (via _onPlayYoutube → resolveTrack).
      await _sessionService.sendYoutubeTrackMessage(
        sessionId:    session.sessionId,
        uid:          uid,
        displayName:  _auth.displayName,
        ytVideoId:    event.track.videoId,
        ytTitle:      event.track.title,
        ytArtist:     event.track.artist,
        ytThumbnail:  event.track.thumbnailUrl,
        ytDurationMs: event.track.duration.inMilliseconds,
        streamUrl:    '', // deferred — resolved at play time
      );
    } catch (e) {
      debugPrint('[Together] shareYoutubeTrack error: $e');
    }
  }

  // ── YouTube video state sync (host WebView → Firestore) ───────
  Future<void> _onPushYtPlayState(
      TogetherPushYtPlayState event, Emitter<TogetherState> emit) async {
    final session = state.session;
    if (session == null || !state.isOwner) return;
    try {
      await _sessionService.pushYtState(
        sessionId:  session.sessionId,
        isPlaying:  event.isPlaying,
        positionMs: event.positionMs,
      );
    } catch (e) {
      debugPrint('[Together] _onPushYtPlayState error: $e');
    }
  }

  // ── Video call: start ─────────────────────────────────────
  Future<void> _onStartVideoCall(
      TogetherStartVideoCall event, Emitter<TogetherState> emit) async {
    final session = state.session;
    if (session == null || !state.isOwner) return;
    final channelId = 'beatflow_${session.sessionId.substring(0, 8)}';
    try {
      await _sessionService.startVideoCall(
        sessionId: session.sessionId,
        channelId: channelId,
      );
      emit(state.copyWith(inVideoCall: true));
    } catch (e) {
      debugPrint('[Together] startVideoCall error: $e');
    }
  }

  // ── Video call: end ───────────────────────────────────────
  Future<void> _onEndVideoCall(
      TogetherEndVideoCall event, Emitter<TogetherState> emit) async {
    final session = state.session;
    if (session == null) return;
    try {
      await _sessionService.endVideoCall(session.sessionId);
      emit(state.copyWith(inVideoCall: false));
    } catch (e) {
      debugPrint('[Together] endVideoCall error: $e');
    }
  }

  // ── Online presence ───────────────────────────────────────────
  /// Called when app goes background/foreground via WidgetsBindingObserver.
  /// Marks the current user as online or offline in Firestore.
  Future<void> _onSetOnlineStatus(
      TogetherSetOnlineStatus event, Emitter<TogetherState> emit) async {
    final session = state.session;
    final uid     = _auth.uid;
    final name    = _auth.displayName;
    if (session == null || uid == null) return;
    try {
      await _sessionService.setOnlineStatus(
        sessionId:   session.sessionId,
        uid:         uid,
        displayName: name,
        isOnline:    event.isOnline,
      );
      debugPrint('[Together] setOnlineStatus → ${event.isOnline}');
    } catch (e) {
      debugPrint('[Together] setOnlineStatus error: $e');
    }
  }

  @override
  Future<void> close() async {
    // [C] Cancel any active upload when bloc is disposed
    _storageService.cancelActiveUpload();
    await _sessionSub?.cancel();
    await _authSub?.cancel();
    _youtubeService.dispose();
    // BUG-H02 FIX: stop heartbeat if still in session (e.g. hot-restart / crash)
    final session = state.session;
    final uid     = _auth.uid;
    if (session != null && uid != null) {
      _sessionService.stopPresenceHeartbeat(
        sessionId:   session.sessionId,
        uid:         uid,
        displayName: _auth.displayName,
      );
    }
    return super.close();
  }
}
