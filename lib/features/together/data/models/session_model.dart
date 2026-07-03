import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/session_entity.dart';

class SessionModel {
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
  final Timestamp updatedAt;
  // BUG-S01 FIX: separate playback anchor (null = fall back to updatedAt)
  final Timestamp? playbackUpdatedAt;
  // BUG-T02 FIX: graceful session-end warning flag
  final bool isEnding;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> chatMessages;
  final Map<String, dynamic>? pendingHostRequest;
  final String? agoraChannel;
  final bool callActive;
  final bool isVideo;
  final List<Map<String, dynamic>> queue; // TASK-5: host queue snapshot
  final bool isPublic;
  final String country;

  SessionModel({
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
    this.playbackUpdatedAt,
    this.isEnding = false,
    required this.members,
    required this.chatMessages,
    this.pendingHostRequest,
    this.agoraChannel,
    this.callActive = false,
    this.isVideo = false,
    this.queue = const [],
    this.isPublic = false,
    this.country  = '',
  });

  factory SessionModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SessionModel(
      sessionId:         doc.id,
      sessionCode:       d['sessionCode']    as String? ?? '',
      ownerId:           d['ownerId']        as String? ?? '',
      ownerName:         d['ownerName']      as String? ?? '',
      songId:            d['songId']         as String? ?? '',
      songTitle:         d['songTitle']      as String? ?? '',
      songArtist:        d['songArtist']     as String? ?? '',
      songData:          d['songData']       as String? ?? '',
      streamUrl:         d['streamUrl']      as String? ?? '',
      songDurationMs:    d['songDurationMs'] as int?    ?? 0,
      positionMs:        d['positionMs']     as int?    ?? 0,
      isPlaying:         d['isPlaying']      as bool?   ?? false,
      updatedAt:         d['updatedAt']      as Timestamp? ?? Timestamp.now(),
      playbackUpdatedAt: d['playbackUpdatedAt'] as Timestamp?,
      isEnding:          d['isEnding']       as bool?   ?? false,
      members:           (d['members'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      chatMessages:      (d['chatMessages'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      pendingHostRequest: d['pendingHostRequest'] != null
          ? Map<String, dynamic>.from(d['pendingHostRequest'] as Map)
          : null,
      agoraChannel: d['agoraChannel'] as String?,
      callActive:   d['callActive']   as bool? ?? false,
      isVideo:   d['isVideo']   as bool?   ?? false,
      isPublic:  d['isPublic']  as bool?   ?? false,
      country:   d['country']   as String? ?? '',
      // TASK-5: parse queue; guard against malformed entries
      queue: (d['queue'] as List<dynamic>?)
              ?.map((e) {
                try {
                  return Map<String, dynamic>.from(e as Map);
                } catch (_) {
                  return <String, dynamic>{};
                }
              })
              .where((m) => m.isNotEmpty)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'sessionCode':    sessionCode,
        'ownerId':        ownerId,
        'ownerName':      ownerName,
        'songId':         songId,
        'songTitle':      songTitle,
        'songArtist':     songArtist,
        'songData':       songData,
        'streamUrl':      streamUrl,
        'songDurationMs': songDurationMs,
        'positionMs':     positionMs,
        'isPlaying':      isPlaying,
        'updatedAt':      updatedAt,
        if (playbackUpdatedAt != null) 'playbackUpdatedAt': playbackUpdatedAt,
        'isEnding':       isEnding,
        'members':        members,
        'chatMessages':   chatMessages,
        if (pendingHostRequest != null)
          'pendingHostRequest': pendingHostRequest,
        if (agoraChannel != null) 'agoraChannel': agoraChannel,
        'callActive': callActive,
        'isVideo':    isVideo,
        if (queue.isNotEmpty) 'queue': queue,
        'isPublic': isPublic,
        if (country.isNotEmpty) 'country': country,
      };

  SessionEntity toEntity() => SessionEntity(
        sessionId:         sessionId,
        sessionCode:       sessionCode,
        ownerId:           ownerId,
        ownerName:         ownerName,
        songId:            songId,
        songTitle:         songTitle,
        songArtist:        songArtist,
        songData:          songData,
        streamUrl:         streamUrl,
        songDurationMs:    songDurationMs,
        positionMs:        positionMs,
        isPlaying:         isPlaying,
        updatedAt:         updatedAt.toDate(),
        playbackUpdatedAt: playbackUpdatedAt?.toDate(),
        isEnding:          isEnding,
        members:           members.map(SessionMember.fromMap).toList(),
        chatMessages:      chatMessages.map(SessionChatMessage.fromMap).toList(),
        pendingHostRequest: pendingHostRequest != null
            ? HostChangeRequest.fromMap(pendingHostRequest!)
            : null,
        agoraChannel: agoraChannel,
        callActive:   callActive,
        isVideo:      isVideo,
        queue:        queue,
        isPublic:     isPublic,
        country:      country,
      );
}
