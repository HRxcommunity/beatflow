import 'package:equatable/equatable.dart';

// ════════════════════════════════════════════
//  ENUMS
// ════════════════════════════════════════════

enum GameType { chess, ludo, tictactoe }
enum GameRoomStatus { waiting, active, finished, cancelled }

extension GameTypeExt on GameType {
  String get displayName => switch (this) {
        GameType.chess     => 'Chess',
        GameType.ludo      => 'Ludo',
        GameType.tictactoe => 'Tic-Tac-Toe',
      };
  String get emoji => switch (this) {
        GameType.chess     => '♟️',
        GameType.ludo      => '🎲',
        GameType.tictactoe => '⭕',
      };
  String get description => switch (this) {
        GameType.chess     => '2 players · Strategy',
        GameType.ludo      => '2 players · Dice & Race',
        GameType.tictactoe => '2 players · Quick fun',
      };
}

// ════════════════════════════════════════════
//  GAME PLAYER
// ════════════════════════════════════════════

class GamePlayer extends Equatable {
  final String uid;
  final String name;

  const GamePlayer({required this.uid, required this.name});

  Map<String, dynamic> toMap() => {'uid': uid, 'name': name};

  factory GamePlayer.fromMap(Map<String, dynamic> m) => GamePlayer(
        uid:  m['uid']  as String? ?? '',
        name: m['name'] as String? ?? 'Unknown',
      );

  @override
  List<Object?> get props => [uid];
}

// ════════════════════════════════════════════
//  SPECTATOR REQUEST
// ════════════════════════════════════════════

class SpectatorRequest extends Equatable {
  final String uid;
  final String name;
  final int requestedAtMs;

  const SpectatorRequest({
    required this.uid,
    required this.name,
    required this.requestedAtMs,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'requestedAtMs': requestedAtMs,
      };

  factory SpectatorRequest.fromMap(Map<String, dynamic> m) => SpectatorRequest(
        uid:           m['uid']           as String? ?? '',
        name:          m['name']          as String? ?? 'Unknown',
        requestedAtMs: m['requestedAtMs'] as int?    ?? 0,
      );

  @override
  List<Object?> get props => [uid];
}

// ════════════════════════════════════════════
//  GAME INVITE
// ════════════════════════════════════════════

class GameInvite extends Equatable {
  final String   inviteId;
  final GameType gameType;
  final String   fromUid;
  final String   fromName;
  final String   toUid;
  final String   toName;
  final String   status;       // 'pending' | 'accepted' | 'declined'
  final int      createdAtMs;

  const GameInvite({
    required this.inviteId,
    required this.gameType,
    required this.fromUid,
    required this.fromName,
    required this.toUid,
    required this.toName,
    required this.status,
    required this.createdAtMs,
  });

  bool get isPending  => status == 'pending';
  bool get isAccepted => status == 'accepted';
  // BUG-G02 FIX: invites older than 5 minutes from a crashed/gone sender
  // are considered stale and filtered out of the pending list.
  bool get isExpired  =>
      DateTime.now().millisecondsSinceEpoch - createdAtMs > 5 * 60 * 1000;

  Map<String, dynamic> toMap() => {
        'inviteId':    inviteId,
        'gameType':    gameType.index,
        'fromUid':     fromUid,
        'fromName':    fromName,
        'toUid':       toUid,
        'toName':      toName,
        'status':      status,
        'createdAtMs': createdAtMs,
      };

  factory GameInvite.fromMap(Map<String, dynamic> m, String id) => GameInvite(
        inviteId:    id,
        gameType:    GameType.values[
          ((m['gameType'] as int?) ?? 2).clamp(0, GameType.values.length - 1)],
        fromUid:     m['fromUid']     as String? ?? '',
        fromName:    m['fromName']    as String? ?? 'Unknown',
        toUid:       m['toUid']       as String? ?? '',
        toName:      m['toName']      as String? ?? 'Unknown',
        status:      m['status']      as String? ?? 'pending',
        createdAtMs: m['createdAtMs'] as int?    ?? 0,
      );

  @override
  List<Object?> get props => [inviteId, status];
}

// ════════════════════════════════════════════
//  SPECTATE STATUS  (BUG-G03 FIX)
// ════════════════════════════════════════════

/// Tracks where a spectate request stands from the requester's perspective.
enum SpectateStatus { none, pending, approved, rejected }

// ════════════════════════════════════════════
//  GAME ROOM
// ════════════════════════════════════════════

class GameRoom extends Equatable {
  final String         gameRoomId;
  final GameType       gameType;
  final GamePlayer     player1;
  final GamePlayer     player2;
  final GameRoomStatus status;
  final String         currentTurnUid;
  final String         gameStateJson;
  final String?        winnerId;
  final String?        winnerName;
  final List<SpectatorRequest> pendingSpectatorRequests;
  final List<String>   approvedSpectatorUids;
  final int            createdAtMs;
  final int            updatedAtMs;

  const GameRoom({
    required this.gameRoomId,
    required this.gameType,
    required this.player1,
    required this.player2,
    required this.status,
    required this.currentTurnUid,
    required this.gameStateJson,
    this.winnerId,
    this.winnerName,
    required this.pendingSpectatorRequests,
    required this.approvedSpectatorUids,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  bool get isActive   => status == GameRoomStatus.active;
  bool get isFinished => status == GameRoomStatus.finished;
  bool get isWaiting  => status == GameRoomStatus.waiting;

  bool isPlayer(String uid)   => player1.uid == uid || player2.uid == uid;
  bool isSpectator(String uid) => approvedSpectatorUids.contains(uid);
  bool hasPendingSpectateRequest(String uid) =>
      pendingSpectatorRequests.any((r) => r.uid == uid);

  String opponentName(String myUid) =>
      player1.uid == myUid ? player2.name : player1.name;

  Map<String, dynamic> toMap() => {
        'gameType':       gameType.index,
        'player1':        player1.toMap(),
        'player2':        player2.toMap(),
        'status':         status.index,
        'currentTurnUid': currentTurnUid,
        'gameStateJson':  gameStateJson,
        if (winnerId   != null) 'winnerId':   winnerId,
        if (winnerName != null) 'winnerName': winnerName,
        'pendingSpectatorRequests':
            pendingSpectatorRequests.map((r) => r.toMap()).toList(),
        'approvedSpectatorUids': approvedSpectatorUids,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
      };

  factory GameRoom.fromMap(Map<String, dynamic> m, String id) => GameRoom(
        gameRoomId:   id,
        gameType:     GameType.values[
          ((m['gameType'] as int?) ?? 2).clamp(0, GameType.values.length - 1)],
        player1: GamePlayer.fromMap(
            m['player1'] as Map<String, dynamic>? ?? {}),
        player2: GamePlayer.fromMap(
            m['player2'] as Map<String, dynamic>? ?? {}),
        status: GameRoomStatus.values[
          ((m['status'] as int?) ?? 0).clamp(0, GameRoomStatus.values.length - 1)],
        currentTurnUid: m['currentTurnUid'] as String? ?? '',
        gameStateJson:  m['gameStateJson']  as String? ?? '',
        winnerId:       m['winnerId']       as String?,
        winnerName:     m['winnerName']     as String?,
        pendingSpectatorRequests: (m['pendingSpectatorRequests'] as List<dynamic>? ?? [])
            .map((r) => SpectatorRequest.fromMap(r as Map<String, dynamic>))
            .toList(),
        approvedSpectatorUids:
            (m['approvedSpectatorUids'] as List<dynamic>? ?? [])
                .map((u) => u as String)
                .toList(),
        createdAtMs: m['createdAtMs'] as int? ?? 0,
        updatedAtMs: m['updatedAtMs'] as int? ?? 0,
      );

  GameRoom copyWith({
    GameRoomStatus?       status,
    String?               currentTurnUid,
    String?               gameStateJson,
    String?               winnerId,
    String?               winnerName,
    List<SpectatorRequest>? pendingSpectatorRequests,
    List<String>?         approvedSpectatorUids,
    int?                  updatedAtMs,
  }) =>
      GameRoom(
        gameRoomId:               gameRoomId,
        gameType:                 gameType,
        player1:                  player1,
        player2:                  player2,
        status:                   status               ?? this.status,
        currentTurnUid:           currentTurnUid       ?? this.currentTurnUid,
        gameStateJson:            gameStateJson        ?? this.gameStateJson,
        winnerId:                 winnerId             ?? this.winnerId,
        winnerName:               winnerName           ?? this.winnerName,
        pendingSpectatorRequests: pendingSpectatorRequests ??
                                  this.pendingSpectatorRequests,
        approvedSpectatorUids:    approvedSpectatorUids ??
                                  this.approvedSpectatorUids,
        createdAtMs:              createdAtMs,
        updatedAtMs:              updatedAtMs ?? this.updatedAtMs,
      );

  @override
  List<Object?> get props => [
        gameRoomId, status.index, currentTurnUid,
        gameStateJson, updatedAtMs,
      ];
}
