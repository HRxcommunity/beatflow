import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../domain/entities/game_entity.dart';
import '../domain/entities/chess_ludo_ttt.dart';

class GameService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _uuid = Uuid();

  // ── Paths ─────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _rooms(String sessionId) =>
      _db.collection('together_sessions').doc(sessionId).collection('game_rooms');

  CollectionReference<Map<String, dynamic>> _invites(String sessionId) =>
      _db.collection('together_sessions').doc(sessionId).collection('game_invites');

  // ══ INVITES ══════════════════════════════════════════════════

  /// Send a game challenge to [toUid]
  Future<String?> sendInvite({
    required String sessionId,
    required String fromUid,
    required String fromName,
    required String toUid,
    required String toName,
    required GameType gameType,
  }) async {
    try {
      final id  = _uuid.v4();
      final doc = _invites(sessionId).doc(id);
      await doc.set({
        'inviteId':    id,
        'gameType':    gameType.index,
        'fromUid':     fromUid,
        'fromName':    fromName,
        'toUid':       toUid,
        'toName':      toName,
        'status':      'pending',
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      // Auto-expire old pending invites from same sender
      _cleanOldInvites(sessionId, fromUid);
      debugPrint('[Game] Invite sent: $id');
      return id;
    } catch (e) {
      debugPrint('[Game] sendInvite error: $e');
      return null;
    }
  }

  /// Update invite status
  Future<void> updateInviteStatus(
      String sessionId, String inviteId, String status) async {
    try {
      await _invites(sessionId).doc(inviteId).update({'status': status});
    } catch (e) {
      debugPrint('[Game] updateInviteStatus error: $e');
    }
  }

  /// Delete invite
  Future<void> deleteInvite(String sessionId, String inviteId) async {
    try {
      await _invites(sessionId).doc(inviteId).delete();
    } catch (e) {
      debugPrint('[Game] deleteInvite error: $e');
    }
  }

  void _cleanOldInvites(String sessionId, String fromUid) async {
    try {
      final snap = await _invites(sessionId)
          .where('fromUid', isEqualTo: fromUid)
          .where('status', isEqualTo: 'pending')
          .get();
      // Keep only the latest — delete older ones
      if (snap.docs.length > 2) {
        for (final d in snap.docs.take(snap.docs.length - 2)) {
          d.reference.delete();
        }
      }
    } catch (_) {}
  }

  /// Stream of invites for a specific user (incoming + outgoing)
  Stream<List<GameInvite>> invitesStream(String sessionId, String uid) {
    // Listen to docs where uid is sender or receiver
    return _invites(sessionId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => GameInvite.fromMap(d.data(), d.id))
            .where((inv) => inv.fromUid == uid || inv.toUid == uid)
            .toList());
  }

  // ══ GAME ROOMS ════════════════════════════════════════════════

  /// Create a game room when invite is accepted
  Future<GameRoom?> createGameRoom({
    required String    sessionId,
    required GamePlayer player1,
    required GamePlayer player2,
    required GameType  gameType,
  }) async {
    try {
      final id      = _uuid.v4();
      final now     = DateTime.now().millisecondsSinceEpoch;
      final initial = _initialGameState(gameType, player1.uid, player2.uid);
      final room    = GameRoom(
        gameRoomId:                gameType == GameType.chess   ? id : id,
        gameType:                  gameType,
        player1:                   player1,
        player2:                   player2,
        status:                    GameRoomStatus.active,
        currentTurnUid:            player1.uid,
        gameStateJson:             initial,
        pendingSpectatorRequests:  const [],
        approvedSpectatorUids:     const [],
        createdAtMs:               now,
        updatedAtMs:               now,
      );
      await _rooms(sessionId).doc(id).set(room.toMap());
      debugPrint('[Game] Room created: $id');
      return room.copyWith(); // return with id
    } catch (e) {
      debugPrint('[Game] createGameRoom error: $e');
      return null;
    }
  }

  String _initialGameState(GameType type, String p1uid, String p2uid) {
    switch (type) {
      case GameType.chess:
        return ChessLogic.toJson(ChessState.initial());
      case GameType.tictactoe:
        return TttLogic.toJson(TttState.initial('X'));
      case GameType.ludo:
        return LudoLogic.toJson(LudoState.initial());
    }
  }

  /// Update game state after a move
  Future<void> pushGameMove({
    required String sessionId,
    required String gameRoomId,
    required String gameStateJson,
    required String currentTurnUid,
    String?         winnerId,
    String?         winnerName,
    GameRoomStatus? status,
  }) async {
    try {
      final Map<String, dynamic> update = {
        'gameStateJson':  gameStateJson,
        'currentTurnUid': currentTurnUid,
        'updatedAtMs':    DateTime.now().millisecondsSinceEpoch,
      };
      if (winnerId != null)   update['winnerId']   = winnerId;
      if (winnerName != null) update['winnerName'] = winnerName;
      if (status != null)     update['status']     = status.index;
      await _rooms(sessionId).doc(gameRoomId).update(update);
    } catch (e) {
      debugPrint('[Game] pushGameMove error: $e');
    }
  }

  /// Forfeit — current player loses
  Future<void> forfeitGame({
    required String sessionId,
    required String gameRoomId,
    required String forfeitingUid,
    required String winnerUid,
    required String winnerName,
  }) async {
    try {
      await _rooms(sessionId).doc(gameRoomId).update({
        'status':      GameRoomStatus.finished.index,
        'winnerId':    winnerUid,
        'winnerName':  winnerName,
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[Game] forfeit error: $e');
    }
  }

  /// Request to spectate a game
  Future<void> requestSpectate({
    required String sessionId,
    required String gameRoomId,
    required SpectatorRequest request,
  }) async {
    try {
      await _rooms(sessionId).doc(gameRoomId).update({
        'pendingSpectatorRequests':
            FieldValue.arrayUnion([request.toMap()]),
      });
    } catch (e) {
      debugPrint('[Game] requestSpectate error: $e');
    }
  }

  /// Approve a spectator (either player can approve)
  Future<void> approveSpectator({
    required String sessionId,
    required String gameRoomId,
    required SpectatorRequest request,
  }) async {
    try {
      await _rooms(sessionId).doc(gameRoomId).update({
        'pendingSpectatorRequests':
            FieldValue.arrayRemove([request.toMap()]),
        'approvedSpectatorUids':
            FieldValue.arrayUnion([request.uid]),
      });
    } catch (e) {
      debugPrint('[Game] approveSpectator error: $e');
    }
  }

  /// Reject spectator request
  Future<void> rejectSpectator({
    required String sessionId,
    required String gameRoomId,
    required SpectatorRequest request,
  }) async {
    try {
      await _rooms(sessionId).doc(gameRoomId).update({
        'pendingSpectatorRequests':
            FieldValue.arrayRemove([request.toMap()]),
      });
    } catch (e) {
      debugPrint('[Game] rejectSpectator error: $e');
    }
  }

  /// Stream of ALL game rooms in a session (for the lobby panel)
  Stream<List<GameRoom>> gameRoomsStream(String sessionId) {
    return _rooms(sessionId)
        .orderBy('createdAtMs', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => GameRoom.fromMap(d.data(), d.id))
            .where((r) => r.status != GameRoomStatus.cancelled)
            .toList());
  }

  /// Stream of a single game room (for in-game updates)
  Stream<GameRoom?> gameRoomStream(String sessionId, String gameRoomId) {
    return _rooms(sessionId).doc(gameRoomId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return GameRoom.fromMap(snap.data()!, snap.id);
    });
  }

  /// Cancel/cleanup finished rooms older than 1 hour
  Future<void> cleanupOldRooms(String sessionId) async {
    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      final snap = await _rooms(sessionId)
          .where('status', isEqualTo: GameRoomStatus.finished.index)
          .where('updatedAtMs', isLessThan: cutoff)
          .limit(10)
          .get();
      for (final d in snap.docs) {
        d.reference.delete();
      }
    } catch (_) {}
  }

  /// Cleanup all rooms when session ends
  Future<void> cleanupAllRooms(String sessionId) async {
    try {
      final snap = await _rooms(sessionId).limit(20).get();
      for (final d in snap.docs) {
        d.reference.delete();
      }
    } catch (_) {}
  }
}
