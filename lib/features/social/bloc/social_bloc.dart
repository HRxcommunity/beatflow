import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import '../services/social_service.dart';
import '../../together/domain/entities/session_entity.dart';
import '../../together/services/together_session_service.dart';

// ══════════════════════════════════════════════════════════════
//  EVENTS
// ══════════════════════════════════════════════════════════════

abstract class SocialEvent extends Equatable {
  const SocialEvent();
  @override List<Object?> get props => [];
}

class SocialInitialize extends SocialEvent {
  final String uid;
  final String displayName;
  const SocialInitialize(this.uid, this.displayName);
  @override List<Object?> get props => [uid, displayName];
}

class SocialFollowUser extends SocialEvent {
  final String targetUid;
  final String targetName;
  const SocialFollowUser(this.targetUid, this.targetName);
  @override List<Object?> get props => [targetUid];
}

class SocialUnfollowUser extends SocialEvent {
  final String targetUid;
  const SocialUnfollowUser(this.targetUid);
  @override List<Object?> get props => [targetUid];
}

class SocialSearchUsers extends SocialEvent {
  final String query;
  const SocialSearchUsers(this.query);
  @override List<Object?> get props => [query];
}

class SocialUpdateMyActivity extends SocialEvent {
  final String songTitle;
  final String songArtist;
  final bool isInSession;
  final String? sessionCode;
  const SocialUpdateMyActivity({
    required this.songTitle,
    required this.songArtist,
    this.isInSession = false,
    this.sessionCode,
  });
  @override List<Object?> get props => [songTitle, songArtist, isInSession, sessionCode];
}

class SocialClearActivity extends SocialEvent {}
class SocialClearError    extends SocialEvent {}

// Private stream-update events
class _PublicRoomsUpdated extends SocialEvent {
  final List<SessionEntity> rooms;
  const _PublicRoomsUpdated(this.rooms);
  @override List<Object?> get props => [rooms.length];
}

class _FriendsUpdated extends SocialEvent {
  final List<SocialUser> friends;
  const _FriendsUpdated(this.friends);
  @override List<Object?> get props => [friends.length];
}

class _ActivityUpdated extends SocialEvent {
  final List<SocialActivity> activity;
  const _ActivityUpdated(this.activity);
  @override List<Object?> get props => [activity.length];
}

// ══════════════════════════════════════════════════════════════
//  STATE
// ══════════════════════════════════════════════════════════════

class SocialState extends Equatable {
  final List<SessionEntity> publicRooms;
  final List<SocialUser>    friends;
  final List<SocialActivity> activityFeed;
  final List<SocialUser>    searchResults;
  final Set<String>         myFollowing;
  final bool    isLoading;
  final bool    isInitialized;
  final bool    searchLoading;
  final String? error;
  final String? myUid;
  final String? myDisplayName;

  const SocialState({
    this.publicRooms   = const [],
    this.friends       = const [],
    this.activityFeed  = const [],
    this.searchResults = const [],
    this.myFollowing   = const {},
    this.isLoading     = false,
    this.isInitialized = false,
    this.searchLoading = false,
    this.error,
    this.myUid,
    this.myDisplayName,
  });

  bool isFollowing(String uid) => myFollowing.contains(uid);

  /// Trending rooms = public rooms sorted by member count desc
  List<SessionEntity> get trendingRooms {
    final sorted = [...publicRooms];
    sorted.sort((a, b) => b.memberCount.compareTo(a.memberCount));
    return sorted;
  }

  SocialState copyWith({
    List<SessionEntity>?  publicRooms,
    List<SocialUser>?     friends,
    List<SocialActivity>? activityFeed,
    List<SocialUser>?     searchResults,
    Set<String>?          myFollowing,
    bool?   isLoading,
    bool?   isInitialized,
    bool?   searchLoading,
    String? error,
    bool    clearError    = false,
    String? myUid,
    String? myDisplayName,
  }) => SocialState(
        publicRooms:    publicRooms    ?? this.publicRooms,
        friends:        friends        ?? this.friends,
        activityFeed:   activityFeed   ?? this.activityFeed,
        searchResults:  searchResults  ?? this.searchResults,
        myFollowing:    myFollowing    ?? this.myFollowing,
        isLoading:      isLoading      ?? this.isLoading,
        isInitialized:  isInitialized  ?? this.isInitialized,
        searchLoading:  searchLoading  ?? this.searchLoading,
        error:          clearError     ? null : (error ?? this.error),
        myUid:          myUid          ?? this.myUid,
        myDisplayName:  myDisplayName  ?? this.myDisplayName,
      );

  @override
  List<Object?> get props => [
        publicRooms.length, friends.length,
        activityFeed.length, searchResults.length,
        myFollowing.length, isLoading, isInitialized,
        searchLoading, error, myUid,
      ];
}

// ══════════════════════════════════════════════════════════════
//  BLOC
// ══════════════════════════════════════════════════════════════

class SocialBloc extends Bloc<SocialEvent, SocialState> {
  final SocialService           _social;
  final TogetherSessionService  _sessions;

  StreamSubscription? _roomsSub;
  StreamSubscription? _friendsSub;
  StreamSubscription? _activitySub;

  SocialBloc({
    required SocialService          socialService,
    required TogetherSessionService sessionService,
  })  : _social   = socialService,
        _sessions = sessionService,
        super(const SocialState()) {
    on<SocialInitialize>        (_onInitialize);
    on<SocialFollowUser>        (_onFollow);
    on<SocialUnfollowUser>      (_onUnfollow);
    on<SocialSearchUsers>       (_onSearch);
    on<SocialUpdateMyActivity>  (_onUpdateActivity);
    on<SocialClearActivity>     (_onClearActivity);
    on<SocialClearError>((_, emit) => emit(state.copyWith(clearError: true)));
    on<_PublicRoomsUpdated>((e, emit) => emit(state.copyWith(publicRooms: e.rooms)));
    on<_FriendsUpdated>    ((e, emit) => emit(state.copyWith(friends: e.friends)));
    on<_ActivityUpdated>   ((e, emit) => emit(state.copyWith(activityFeed: e.activity)));
  }

  // ── Initialize ────────────────────────────────────────────────
  Future<void> _onInitialize(SocialInitialize event, Emitter<SocialState> emit) async {
    if (state.isInitialized && state.myUid == event.uid) return;

    emit(state.copyWith(
      isLoading:     true,
      myUid:         event.uid,
      myDisplayName: event.displayName,
    ));
    try {
      await _social.upsertProfile(uid: event.uid, displayName: event.displayName);
      final followingUids = await _social.getFollowingUids(event.uid);
      emit(state.copyWith(myFollowing: followingUids, isLoading: false, isInitialized: true));

      _roomsSub?.cancel();
      _roomsSub = _sessions.watchPublicRooms().listen((rooms) {
        if (!isClosed) add(_PublicRoomsUpdated(rooms));
      });

      _friendsSub?.cancel();
      _friendsSub = _social.watchFollowing(event.uid).listen((friends) {
        if (!isClosed) add(_FriendsUpdated(friends));
      });

      _activitySub?.cancel();
      _activitySub = _social.watchFriendActivity(event.uid).listen((activity) {
        if (!isClosed) add(_ActivityUpdated(activity));
      });
    } catch (e) {
      debugPrint('[SocialBloc] init error: $e');
      emit(state.copyWith(isLoading: false, error: 'Initialization failed: $e'));
    }
  }

  // ── Follow ────────────────────────────────────────────────────
  Future<void> _onFollow(SocialFollowUser event, Emitter<SocialState> emit) async {
    final uid  = state.myUid;
    final name = state.myDisplayName;
    if (uid == null || name == null) return;

    final updated = Set<String>.from(state.myFollowing)..add(event.targetUid);
    emit(state.copyWith(myFollowing: updated));

    try {
      await _social.followUser(
        myUid: uid, myName: name,
        targetUid: event.targetUid, targetName: event.targetName,
      );
    } catch (_) {
      final reverted = Set<String>.from(state.myFollowing)..remove(event.targetUid);
      emit(state.copyWith(myFollowing: reverted, error: 'Could not follow user'));
    }
  }

  // ── Unfollow ──────────────────────────────────────────────────
  Future<void> _onUnfollow(SocialUnfollowUser event, Emitter<SocialState> emit) async {
    final uid = state.myUid;
    if (uid == null) return;

    final updated = Set<String>.from(state.myFollowing)..remove(event.targetUid);
    emit(state.copyWith(myFollowing: updated));

    try {
      await _social.unfollowUser(myUid: uid, targetUid: event.targetUid);
    } catch (_) {
      final reverted = Set<String>.from(state.myFollowing)..add(event.targetUid);
      emit(state.copyWith(myFollowing: reverted, error: 'Could not unfollow'));
    }
  }

  // ── Search ────────────────────────────────────────────────────
  Future<void> _onSearch(SocialSearchUsers event, Emitter<SocialState> emit) async {
    if (event.query.trim().isEmpty) {
      emit(state.copyWith(searchResults: []));
      return;
    }
    emit(state.copyWith(searchLoading: true));
    try {
      final results = await _social.searchUsers(
        query: event.query.trim(),
        myUid: state.myUid ?? '',
      );
      emit(state.copyWith(searchResults: results, searchLoading: false));
    } catch (e) {
      emit(state.copyWith(searchLoading: false, error: 'Search failed'));
    }
  }

  // ── Activity ──────────────────────────────────────────────────
  Future<void> _onUpdateActivity(SocialUpdateMyActivity event, Emitter<SocialState> emit) async {
    final uid  = state.myUid;
    final name = state.myDisplayName;
    if (uid == null || name == null) return;
    try {
      await _social.updateActivity(
        uid:         uid,
        displayName: name,
        songTitle:   event.songTitle,
        songArtist:  event.songArtist,
        isInSession: event.isInSession,
        sessionCode: event.sessionCode,
      );
    } catch (e) {
      debugPrint('[SocialBloc] updateActivity error: $e');
    }
  }

  Future<void> _onClearActivity(SocialClearActivity event, Emitter<SocialState> emit) async {
    final uid = state.myUid;
    if (uid == null) return;
    try {
      await _social.clearActivity(uid);
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _roomsSub?.cancel();
    _friendsSub?.cancel();
    _activitySub?.cancel();
    return super.close();
  }
}
