import 'package:equatable/equatable.dart';

enum SessionRole { owner, listener }

// ── Chat message type ─────────────────────────────────────────
enum ChatMessageType { text, image, file, emoji, youtubeTrack }

class SessionMember extends Equatable {
  final String uid;
  final String displayName;
  final bool isOnline;
  final DateTime joinedAt;
  // BUG-016: TTL-based presence — epoch ms when this member's heartbeat expires.
  // 0 or null = explicitly offline. If > now, member is considered online.
  final int? presenceExpiresAt;

  const SessionMember({
    required this.uid,
    required this.displayName,
    required this.isOnline,
    required this.joinedAt,
    this.presenceExpiresAt,
  });

  /// BUG-016: True online check — isOnline flag AND TTL has not expired.
  bool get isActuallyOnline =>
      isOnline &&
      (presenceExpiresAt == null ||
          presenceExpiresAt == 0 ||
          presenceExpiresAt! > DateTime.now().millisecondsSinceEpoch);

  SessionMember copyWith({
    String? uid,
    String? displayName,
    bool? isOnline,
    DateTime? joinedAt,
    int? presenceExpiresAt,
  }) {
    return SessionMember(
      uid:               uid               ?? this.uid,
      displayName:       displayName       ?? this.displayName,
      isOnline:          isOnline          ?? this.isOnline,
      joinedAt:          joinedAt          ?? this.joinedAt,
      presenceExpiresAt: presenceExpiresAt ?? this.presenceExpiresAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid':               uid,
        'displayName':       displayName,
        'isOnline':          isOnline,
        'joinedAt':          joinedAt.millisecondsSinceEpoch,
        if (presenceExpiresAt != null)
          'presenceExpiresAt': presenceExpiresAt,
      };

  factory SessionMember.fromMap(Map<String, dynamic> map) => SessionMember(
        uid:               map['uid']               as String,
        displayName:       map['displayName']        as String? ?? 'Unknown',
        isOnline:          map['isOnline']           as bool?   ?? false,
        joinedAt:          DateTime.fromMillisecondsSinceEpoch(
          (map['joinedAt'] as int?) ?? 0,
        ),
        // BUG-016: parse TTL field that _setMemberOnline writes
        presenceExpiresAt: map['presenceExpiresAt'] as int?,
      );

  @override
  List<Object?> get props => [uid, displayName, isOnline, presenceExpiresAt];
}

/// A single chat message — supports text, emoji, image, file, YouTube track
class SessionChatMessage extends Equatable {
  final String uid;
  final String displayName;
  final String text;          // for text/emoji messages
  final int timestampMs;
  final ChatMessageType type;
  final String? mediaUrl;     // for image / file
  final String? fileName;     // for file messages
  final String? ytVideoId;    // for YouTube track cards
  final String? ytTitle;
  final String? ytThumbnail;
  final String? ytArtist;
  final int? ytDurationMs;

  const SessionChatMessage({
    required this.uid,
    required this.displayName,
    required this.text,
    required this.timestampMs,
    this.type = ChatMessageType.text,
    this.mediaUrl,
    this.fileName,
    this.ytVideoId,
    this.ytTitle,
    this.ytThumbnail,
    this.ytArtist,
    this.ytDurationMs,
  });

  Map<String, dynamic> toMap() => {
        'uid':          uid,
        'displayName':  displayName,
        'text':         text,
        'timestampMs':  timestampMs,
        'type':         type.index,
        if (mediaUrl   != null) 'mediaUrl':    mediaUrl,
        if (fileName   != null) 'fileName':    fileName,
        if (ytVideoId  != null) 'ytVideoId':   ytVideoId,
        if (ytTitle    != null) 'ytTitle':     ytTitle,
        if (ytThumbnail!= null) 'ytThumbnail': ytThumbnail,
        if (ytArtist   != null) 'ytArtist':    ytArtist,
        if (ytDurationMs!= null) 'ytDurationMs': ytDurationMs,
      };

  factory SessionChatMessage.fromMap(Map<String, dynamic> map) =>
      SessionChatMessage(
        uid:          map['uid']         as String? ?? '',
        displayName:  map['displayName'] as String? ?? 'Unknown',
        text:         map['text']        as String? ?? '',
        timestampMs:  map['timestampMs'] as int?    ?? 0,
        type:         ChatMessageType.values[
                        ((map['type'] as int?) ?? 0).clamp(0, ChatMessageType.values.length - 1)],
        mediaUrl:     map['mediaUrl']    as String?,
        fileName:     map['fileName']    as String?,
        ytVideoId:    map['ytVideoId']   as String?,
        ytTitle:      map['ytTitle']     as String?,
        ytThumbnail:  map['ytThumbnail'] as String?,
        ytArtist:     map['ytArtist']    as String?,
        ytDurationMs: map['ytDurationMs'] as int?,
      );

  @override
  List<Object?> get props => [uid, timestampMs, text, type, mediaUrl];
}

/// A host-change request sent by a listener
class HostChangeRequest extends Equatable {
  final String requesterUid;
  final String requesterName;
  final int requestedAtMs;
  final String status; // 'pending' | 'accepted' | 'rejected'

  const HostChangeRequest({
    required this.requesterUid,
    required this.requesterName,
    required this.requestedAtMs,
    required this.status,
  });

  Map<String, dynamic> toMap() => {
        'requesterUid':   requesterUid,
        'requesterName':  requesterName,
        'requestedAtMs':  requestedAtMs,
        'status':         status,
      };

  factory HostChangeRequest.fromMap(Map<String, dynamic> map) =>
      HostChangeRequest(
        requesterUid:  map['requesterUid']  as String? ?? '',
        requesterName: map['requesterName'] as String? ?? 'Unknown',
        requestedAtMs: map['requestedAtMs'] as int?    ?? 0,
        status:        map['status']        as String? ?? 'pending',
      );

  @override
  List<Object?> get props => [requesterUid, requestedAtMs, status];
}

class SessionEntity extends Equatable {
  final String sessionId;
  final String sessionCode;
  final String ownerId;
  final String ownerName;
  final String songId;
  final String songTitle;
  final String songArtist;
  final String songData;
  final String streamUrl;
  final int songDurationMs;
  final int positionMs;
  final bool isPlaying;
  final DateTime updatedAt;
  // BUG-S01 FIX: separate timestamp anchored only to playback events
  // (play/pause/seek/song change). NOT updated on member join/leave or
  // stream URL changes. Used for elapsed-time position calculation so that
  // a guest joining doesn't reset the sync anchor.
  final DateTime? playbackUpdatedAt;
  // BUG-T02 FIX: graceful session-end warning field.
  // Host writes isEnding=true before deleting, giving guests 2s to react.
  final bool isEnding;
  final List<SessionMember> members;
  final List<SessionChatMessage> chatMessages;
  final HostChangeRequest? pendingHostRequest;
  // ── Video call ───────────────────────────────────────────────
  final String? agoraChannel;   // non-null when call is live
  final bool callActive;
  // ── Video content ─────────────────────────────────────────────
  // true when shared content is a video file (local MP4 or YouTube video mode)
  final bool isVideo;

  const SessionEntity({
    required this.sessionId,
    required this.sessionCode,
    required this.ownerId,
    required this.ownerName,
    required this.songId,
    required this.songTitle,
    required this.songArtist,
    required this.songData,
    required this.streamUrl,
    required this.songDurationMs,
    required this.positionMs,
    required this.isPlaying,
    required this.updatedAt,
    this.playbackUpdatedAt,  // BUG-S01 FIX: nullable, falls back to updatedAt
    this.isEnding = false,   // BUG-T02 FIX
    required this.members,
    this.chatMessages = const [],
    this.pendingHostRequest,
    this.agoraChannel,
    this.callActive = false,
    this.isVideo = false,
  });

  bool get hasStreamUrl => streamUrl.isNotEmpty && streamUrl.startsWith('http');

  /// BUG-S01 FIX: use playbackUpdatedAt if available, otherwise fall back to
  /// updatedAt. This ensures guest joins (which update updatedAt) don't corrupt
  /// the elapsed-time position calculation used in _expectedPositionMs().
  DateTime get effectivePlaybackUpdatedAt => playbackUpdatedAt ?? updatedAt;

  SessionEntity copyWith({
    String? sessionId,
    String? sessionCode,
    String? ownerId,
    String? ownerName,
    String? songId,
    String? songTitle,
    String? songArtist,
    String? songData,
    String? streamUrl,
    int? songDurationMs,
    int? positionMs,
    bool? isPlaying,
    DateTime? updatedAt,
    DateTime? playbackUpdatedAt,  // BUG-S01 FIX
    bool? isEnding,               // BUG-T02 FIX
    List<SessionMember>? members,
    List<SessionChatMessage>? chatMessages,
    HostChangeRequest? pendingHostRequest,
    bool clearHostRequest = false,
    String? agoraChannel,
    bool? callActive,
    bool clearAgoraChannel = false,
    bool? isVideo,
  }) {
    return SessionEntity(
      sessionId:          sessionId       ?? this.sessionId,
      sessionCode:        sessionCode     ?? this.sessionCode,
      ownerId:            ownerId         ?? this.ownerId,
      ownerName:          ownerName       ?? this.ownerName,
      songId:             songId          ?? this.songId,
      songTitle:          songTitle       ?? this.songTitle,
      songArtist:         songArtist      ?? this.songArtist,
      songData:           songData        ?? this.songData,
      streamUrl:          streamUrl       ?? this.streamUrl,
      songDurationMs:     songDurationMs  ?? this.songDurationMs,
      positionMs:         positionMs      ?? this.positionMs,
      isPlaying:          isPlaying       ?? this.isPlaying,
      updatedAt:          updatedAt       ?? this.updatedAt,
      playbackUpdatedAt:  playbackUpdatedAt ?? this.playbackUpdatedAt, // BUG-S01 FIX
      isEnding:           isEnding        ?? this.isEnding,            // BUG-T02 FIX
      members:            members         ?? this.members,
      chatMessages:       chatMessages    ?? this.chatMessages,
      pendingHostRequest: clearHostRequest
          ? null
          : (pendingHostRequest ?? this.pendingHostRequest),
      agoraChannel:   clearAgoraChannel ? null : (agoraChannel ?? this.agoraChannel),
      callActive:     callActive ?? this.callActive,
      isVideo:        isVideo ?? this.isVideo,
    );
  }

  int get memberCount => members.length;
  int get onlineCount => members.where((m) => m.isOnline).length;

  @override
  List<Object?> get props => [
        sessionId, songId, streamUrl, positionMs, isPlaying,
        updatedAt, members.length, chatMessages.length,
        pendingHostRequest?.status, ownerId,
        agoraChannel, callActive, isEnding, isVideo,
      ];
}
