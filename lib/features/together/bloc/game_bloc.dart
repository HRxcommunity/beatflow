import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import '../domain/entities/game_entity.dart';
import '../domain/entities/chess_ludo_ttt.dart';
import '../services/game_service.dart';

// ════════════════════════════════════════════
//  EVENTS
// ════════════════════════════════════════════

abstract class GameEvent extends Equatable {
  const GameEvent();
  @override
  List<Object?> get props => [];
}

class GameInitialize extends GameEvent {
  final String sessionId;
  final String myUid;
  final String myName;
  const GameInitialize(this.sessionId, this.myUid, this.myName);
  @override List<Object?> get props => [sessionId, myUid];
}

class GameSendInvite extends GameEvent {
  final GameType gameType;
  final String   toUid;
  final String   toName;
  const GameSendInvite({required this.gameType, required this.toUid, required this.toName});
  @override List<Object?> get props => [gameType, toUid];
}

class GameAcceptInvite extends GameEvent {
  final GameInvite invite;
  const GameAcceptInvite(this.invite);
  @override List<Object?> get props => [invite.inviteId];
}

class GameDeclineInvite extends GameEvent {
  final GameInvite invite;
  const GameDeclineInvite(this.invite);
  @override List<Object?> get props => [invite.inviteId];
}

class GameMakeChessMove extends GameEvent {
  final int from;
  final int to;
  const GameMakeChessMove(this.from, this.to);
  @override List<Object?> get props => [from, to];
}

class GameSelectChessSquare extends GameEvent {
  final int square;
  const GameSelectChessSquare(this.square);
  @override List<Object?> get props => [square];
}

class GameMakeTttMove extends GameEvent {
  final int cell;
  const GameMakeTttMove(this.cell);
  @override List<Object?> get props => [cell];
}

class GameRollLudoDice extends GameEvent {}

class GameMoveLudoPiece extends GameEvent {
  final int pieceIndex;
  const GameMoveLudoPiece(this.pieceIndex);
  @override List<Object?> get props => [pieceIndex];
}

class GameRequestSpectate extends GameEvent {
  final String gameRoomId;
  const GameRequestSpectate(this.gameRoomId);
  @override List<Object?> get props => [gameRoomId];
}

class GameApproveSpectator extends GameEvent {
  final SpectatorRequest request;
  const GameApproveSpectator(this.request);
  @override List<Object?> get props => [request.uid];
}

class GameRejectSpectator extends GameEvent {
  final SpectatorRequest request;
  const GameRejectSpectator(this.request);
  @override List<Object?> get props => [request.uid];
}

class GameEnterRoom extends GameEvent {
  final String gameRoomId;
  const GameEnterRoom(this.gameRoomId);
  @override List<Object?> get props => [gameRoomId];
}

class GameLeaveRoom extends GameEvent {}

class GameForfeit extends GameEvent {}

class GameClearError extends GameEvent {}

// BUG-U03 FIX: resets all state and subscriptions between sessions
class GameReset extends GameEvent {}

// Internal
class _RoomsUpdated extends GameEvent {
  final List<GameRoom> rooms;
  const _RoomsUpdated(this.rooms);
  @override List<Object?> get props => [rooms.length];
}

class _InvitesUpdated extends GameEvent {
  final List<GameInvite> invites;
  const _InvitesUpdated(this.invites);
  @override List<Object?> get props => [invites.length];
}

class _CurrentRoomUpdated extends GameEvent {
  final GameRoom? room;
  const _CurrentRoomUpdated(this.room);
  @override List<Object?> get props => [room?.updatedAtMs];
}

// ════════════════════════════════════════════
//  STATE
// ════════════════════════════════════════════

class GameState extends Equatable {
  final List<GameRoom>   allRooms;
  final List<GameInvite> pendingInvites; // invites for me (toUid == myUid)
  final List<GameInvite> sentInvites;    // invites sent by me
  final GameRoom?        currentRoom;    // room user is currently playing/watching
  final bool             isInRoom;
  final ChessState?      chessState;     // local chess state (UI only, server is source)
  final String?          error;
  final bool             loading;
  // BUG-G03 FIX: track spectate request outcome for the requester
  final SpectateStatus   spectateStatus;

  const GameState({
    this.allRooms       = const [],
    this.pendingInvites = const [],
    this.sentInvites    = const [],
    this.currentRoom,
    this.isInRoom       = false,
    this.chessState,
    this.error,
    this.loading        = false,
    this.spectateStatus = SpectateStatus.none, // BUG-G03 FIX
  });

  bool get hasInvites => pendingInvites.isNotEmpty;
  int get activeGamesCount => allRooms.where((r) => r.isActive).length;

  GameState copyWith({
    List<GameRoom>?   allRooms,
    List<GameInvite>? pendingInvites,
    List<GameInvite>? sentInvites,
    GameRoom?         currentRoom,
    bool?             isInRoom,
    ChessState?       chessState,
    String?           error,
    bool?             loading,
    SpectateStatus?   spectateStatus, // BUG-G03 FIX
    bool              clearError  = false,
    bool              clearRoom   = false,
    bool              clearChess  = false,
  }) =>
      GameState(
        allRooms:       allRooms       ?? this.allRooms,
        pendingInvites: pendingInvites  ?? this.pendingInvites,
        sentInvites:    sentInvites    ?? this.sentInvites,
        currentRoom:    clearRoom      ? null : (currentRoom ?? this.currentRoom),
        isInRoom:       isInRoom       ?? this.isInRoom,
        chessState:     clearChess     ? null : (chessState ?? this.chessState),
        error:          clearError     ? null : (error ?? this.error),
        loading:        loading        ?? this.loading,
        spectateStatus: spectateStatus ?? this.spectateStatus, // BUG-G03 FIX
      );

  @override
  List<Object?> get props => [
        allRooms.length,
        pendingInvites.length,
        sentInvites.length,
        currentRoom?.updatedAtMs,
        isInRoom,
        chessState?.moves.length,
        error,
        loading,
        spectateStatus, // BUG-G03 FIX
      ];
}

// ════════════════════════════════════════════
//  BLOC
// ════════════════════════════════════════════

class GameBloc extends Bloc<GameEvent, GameState> {
  final GameService _service = GameService();

  String? _sessionId;
  String? _myUid;
  String? _myName;

  StreamSubscription<List<GameRoom>>?   _roomsSub;
  StreamSubscription<List<GameInvite>>? _invitesSub;
  StreamSubscription<GameRoom?>?        _currentRoomSub;

  GameBloc() : super(const GameState()) {
    on<GameInitialize>         (_onInit);
    on<GameSendInvite>         (_onSendInvite);
    on<GameAcceptInvite>       (_onAcceptInvite);
    on<GameDeclineInvite>      (_onDeclineInvite);
    on<GameMakeChessMove>      (_onChessMove);
    on<GameSelectChessSquare>  (_onChessSelect);
    on<GameMakeTttMove>        (_onTttMove);
    on<GameRollLudoDice>       (_onLudoRoll);
    on<GameMoveLudoPiece>      (_onLudoMove);
    on<GameRequestSpectate>    (_onRequestSpectate);
    on<GameApproveSpectator>   (_onApproveSpectator);
    on<GameRejectSpectator>    (_onRejectSpectator);
    on<GameEnterRoom>          (_onEnterRoom);
    on<GameLeaveRoom>          (_onLeaveRoom);
    on<GameForfeit>            (_onForfeit);
    on<GameClearError>         ((_, emit) => emit(state.copyWith(clearError: true)));
    on<GameReset>              (_onReset); // BUG-U03 FIX
    on<_RoomsUpdated>          (_onRoomsUpdated);
    on<_InvitesUpdated>        (_onInvitesUpdated);
    on<_CurrentRoomUpdated>    (_onCurrentRoomUpdated);
  }

  // ── Init ─────────────────────────────────────────────────────

  Future<void> _onInit(GameInitialize event, Emitter<GameState> emit) async {
    _sessionId = event.sessionId;
    _myUid     = event.myUid;
    _myName    = event.myName;

    await _roomsSub?.cancel();
    await _invitesSub?.cancel();
    await _currentRoomSub?.cancel(); // BUG-SM03 FIX: old room sub must stop
    _currentRoomSub = null;           // before new session initializes

    _roomsSub = _service
        .gameRoomsStream(event.sessionId)
        .listen((rooms) => add(_RoomsUpdated(rooms)));

    _invitesSub = _service
        .invitesStream(event.sessionId, event.myUid)
        .listen((invites) => add(_InvitesUpdated(invites)));
  }

  // ── Send invite ───────────────────────────────────────────────

  Future<void> _onSendInvite(GameSendInvite event, Emitter<GameState> emit) async {
    final sid  = _sessionId;
    final uid  = _myUid;
    final name = _myName;
    if (sid == null || uid == null) return;

    // Check for existing active invite
    final existing = state.sentInvites
        .where((i) => i.toUid == event.toUid && i.isPending)
        .toList();
    for (final inv in existing) {
      await _service.deleteInvite(sid, inv.inviteId);
    }

    await _service.sendInvite(
      sessionId: sid,
      fromUid:   uid,
      fromName:  name ?? 'Player',
      toUid:     event.toUid,
      toName:    event.toName,
      gameType:  event.gameType,
    );
  }

  // ── Accept invite ─────────────────────────────────────────────

  Future<void> _onAcceptInvite(GameAcceptInvite event, Emitter<GameState> emit) async {
    final sid  = _sessionId;
    final uid  = _myUid;
    final name = _myName;
    if (sid == null || uid == null) return;

    emit(state.copyWith(loading: true));
    try {
      await _service.updateInviteStatus(sid, event.invite.inviteId, 'accepted');

      final room = await _service.createGameRoom(
        sessionId: sid,
        player1:   GamePlayer(uid: event.invite.fromUid, name: event.invite.fromName),
        player2:   GamePlayer(uid: uid, name: name ?? 'Player'),
        gameType:  event.invite.gameType,
      );

      if (room != null) {
        await _service.deleteInvite(sid, event.invite.inviteId);
        _subscribeToRoom(sid, room.gameRoomId);
        final chessState = room.gameType == GameType.chess
            ? ChessLogic.fromJson(room.gameStateJson)
            : null;
        emit(state.copyWith(
          currentRoom: room,
          isInRoom:    true,
          chessState:  chessState,
          loading:     false,
        ));
      } else {
        emit(state.copyWith(
            loading: false, error: 'Could not create game room. Try again.'));
      }
    } catch (e) {
      emit(state.copyWith(loading: false, error: 'Accept failed: $e'));
    }
  }

  // ── Decline invite ────────────────────────────────────────────

  Future<void> _onDeclineInvite(GameDeclineInvite event, Emitter<GameState> emit) async {
    final sid = _sessionId;
    if (sid == null) return;
    await _service.updateInviteStatus(sid, event.invite.inviteId, 'declined');
    await _service.deleteInvite(sid, event.invite.inviteId);
  }

  // ── Enter room (to play or watch) ─────────────────────────────

  Future<void> _onEnterRoom(GameEnterRoom event, Emitter<GameState> emit) async {
    final sid = _sessionId;
    if (sid == null) return;
    // Find room
    final room = state.allRooms.firstWhere(
      (r) => r.gameRoomId == event.gameRoomId,
      orElse: () => throw StateError('Room not found'),
    );
    _subscribeToRoom(sid, event.gameRoomId);
    final chessState = room.gameType == GameType.chess
        ? ChessLogic.fromJson(room.gameStateJson)
        : null;
    emit(state.copyWith(currentRoom: room, isInRoom: true, chessState: chessState));
  }

  void _subscribeToRoom(String sessionId, String roomId) {
    _currentRoomSub?.cancel();
    _currentRoomSub = _service
        .gameRoomStream(sessionId, roomId)
        .listen((room) => add(_CurrentRoomUpdated(room)));
  }

  // ── Chess: select square ──────────────────────────────────────

  void _onChessSelect(GameSelectChessSquare event, Emitter<GameState> emit) {
    final room   = state.currentRoom;
    final cs     = state.chessState;
    if (room == null || cs == null) return;
    if (room.isFinished) return;

    final isMyTurn = room.currentTurnUid == _myUid;
    if (!isMyTurn) return;

    final sq = event.square;

    // If a piece is already selected
    if (cs.selectedSquare != null) {
      // If clicking on a valid move destination
      if (cs.validMoves.contains(sq)) {
        add(GameMakeChessMove(cs.selectedSquare!, sq));
        return;
      }
      // If clicking own piece, re-select
      final piece = cs.board[sq];
      if (piece.isNotEmpty &&
          ChessLogic.pieceColor(piece) == cs.currentTurn) {
        final moves = ChessLogic.legalMovesForSquare(cs, sq);
        emit(state.copyWith(
          chessState: cs.copyWith(selectedSquare: sq, validMoves: moves),
        ));
        return;
      }
      // Deselect
      emit(state.copyWith(chessState: cs.copyWith(clearSelection: true)));
      return;
    }

    // Select a piece
    final piece = cs.board[sq];
    if (piece.isEmpty) return;
    final color = ChessLogic.pieceColor(piece);
    if (color != cs.currentTurn) return;
    final moves = ChessLogic.legalMovesForSquare(cs, sq);
    emit(state.copyWith(
      chessState: cs.copyWith(selectedSquare: sq, validMoves: moves),
    ));
  }

  // ── Chess: make move ──────────────────────────────────────────

  Future<void> _onChessMove(GameMakeChessMove event, Emitter<GameState> emit) async {
    final sid  = _sessionId;
    final room = state.currentRoom;
    final cs   = state.chessState;
    if (sid == null || room == null || cs == null) return;
    if (room.isFinished || room.currentTurnUid != _myUid) return;

    final newCs     = ChessLogic.applyMove(cs, event.from, event.to);
    final opponent  = room.player1.uid == _myUid ? room.player2 : room.player1;
    final winnerId  = newCs.isCheckmate ? _myUid : null;
    final winnerName = newCs.isCheckmate ? _myName : null;
    final isDone    = newCs.isCheckmate || newCs.isDraw;

    emit(state.copyWith(chessState: newCs));

    await _service.pushGameMove(
      sessionId:     sid,
      gameRoomId:    room.gameRoomId,
      gameStateJson: ChessLogic.toJson(newCs),
      currentTurnUid: isDone ? room.currentTurnUid : opponent.uid,
      winnerId:      winnerId,
      winnerName:    winnerName,
      status:        isDone ? GameRoomStatus.finished : null,
    );
  }

  // ── TTT: make move ────────────────────────────────────────────

  Future<void> _onTttMove(GameMakeTttMove event, Emitter<GameState> emit) async {
    final sid  = _sessionId;
    final room = state.currentRoom;
    if (sid == null || room == null || room.gameType != GameType.tictactoe) return;
    if (room.isFinished || room.currentTurnUid != _myUid) return;

    final ttt   = TttLogic.fromJson(room.gameStateJson);
    final myMark = room.player1.uid == _myUid ? 'X' : 'O';
    final newTtt = TttLogic.applyMove(ttt, event.cell, myMark);
    if (newTtt == ttt) return; // illegal move

    final opponent   = room.player1.uid == _myUid ? room.player2 : room.player1;
    final isDone     = newTtt.isFinished;
    final winnerId   = newTtt.winner == myMark ? _myUid : null;
    final winnerName = newTtt.winner == myMark ? _myName : null;

    await _service.pushGameMove(
      sessionId:      sid,
      gameRoomId:     room.gameRoomId,
      gameStateJson:  TttLogic.toJson(newTtt),
      currentTurnUid: isDone ? room.currentTurnUid : opponent.uid,
      winnerId:       winnerId,
      winnerName:     winnerName,
      status:         isDone ? GameRoomStatus.finished : null,
    );
  }

  // ── Ludo: roll dice ────────────────────────────────────────────

  Future<void> _onLudoRoll(GameRollLudoDice event, Emitter<GameState> emit) async {
    final sid  = _sessionId;
    final room = state.currentRoom;
    if (sid == null || room == null || room.gameType != GameType.ludo) return;
    if (room.isFinished || room.currentTurnUid != _myUid) return;

    final ludo    = LudoLogic.fromJson(room.gameStateJson);
    final isRed   = room.player1.uid == _myUid;
    final newLudo = LudoLogic.rollDice(ludo, isRed);
    if (newLudo == ludo) return;

    final opponent = room.player1.uid == _myUid ? room.player2 : room.player1;

    await _service.pushGameMove(
      sessionId:      sid,
      gameRoomId:     room.gameRoomId,
      gameStateJson:  LudoLogic.toJson(newLudo),
      currentTurnUid: newLudo.isRedTurn == isRed
          ? _myUid!          // still my turn (6 rolled or auto-skip)
          : opponent.uid,
    );
  }

  // ── Ludo: move piece ───────────────────────────────────────────

  Future<void> _onLudoMove(GameMoveLudoPiece event, Emitter<GameState> emit) async {
    final sid  = _sessionId;
    final room = state.currentRoom;
    if (sid == null || room == null || room.gameType != GameType.ludo) return;
    if (room.isFinished || room.currentTurnUid != _myUid) return;

    final ludo    = LudoLogic.fromJson(room.gameStateJson);
    final isRed   = room.player1.uid == _myUid;
    final newLudo = LudoLogic.movePiece(ludo, event.pieceIndex, isRed);
    if (newLudo == ludo) return;

    final opponent   = room.player1.uid == _myUid ? room.player2 : room.player1;
    final isDone     = newLudo.winner.isNotEmpty;
    final winnerId   = isDone ? _myUid : null;
    final winnerName = isDone ? _myName : null;
    final nextTurn   = newLudo.isRedTurn == isRed ? _myUid! : opponent.uid;

    await _service.pushGameMove(
      sessionId:      sid,
      gameRoomId:     room.gameRoomId,
      gameStateJson:  LudoLogic.toJson(newLudo),
      currentTurnUid: isDone ? room.currentTurnUid : nextTurn,
      winnerId:       winnerId,
      winnerName:     winnerName,
      status:         isDone ? GameRoomStatus.finished : null,
    );
  }

  // ── Spectate ────────────────────────────────────────────────────

  Future<void> _onRequestSpectate(
      GameRequestSpectate event, Emitter<GameState> emit) async {
    final sid  = _sessionId;
    final uid  = _myUid;
    final name = _myName;
    if (sid == null || uid == null) return;

    final room = state.allRooms
        .firstWhere((r) => r.gameRoomId == event.gameRoomId,
            orElse: () => throw StateError('Room not found'));

    if (room.hasPendingSpectateRequest(uid) || room.isSpectator(uid)) return;

    emit(state.copyWith(spectateStatus: SpectateStatus.pending)); // BUG-G03 FIX
    await _service.requestSpectate(
      sessionId:  sid,
      gameRoomId: event.gameRoomId,
      request: SpectatorRequest(
        uid:           uid,
        name:          name ?? 'Spectator',
        requestedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _onApproveSpectator(
      GameApproveSpectator event, Emitter<GameState> emit) async {
    final sid  = _sessionId;
    final room = state.currentRoom;
    if (sid == null || room == null) return;
    await _service.approveSpectator(
        sessionId: sid, gameRoomId: room.gameRoomId, request: event.request);
  }

  Future<void> _onRejectSpectator(
      GameRejectSpectator event, Emitter<GameState> emit) async {
    final sid  = _sessionId;
    final room = state.currentRoom;
    if (sid == null || room == null) return;
    await _service.rejectSpectator(
        sessionId: sid, gameRoomId: room.gameRoomId, request: event.request);
  }

  // ── Leave room ─────────────────────────────────────────────────

  void _onLeaveRoom(GameLeaveRoom event, Emitter<GameState> emit) {
    _currentRoomSub?.cancel();
    _currentRoomSub = null;
    emit(state.copyWith(
        clearRoom: true, isInRoom: false, clearChess: true));
  }

  // ── Forfeit ──────────────────────────────────────────────────

  Future<void> _onForfeit(GameForfeit event, Emitter<GameState> emit) async {
    final sid  = _sessionId;
    final room = state.currentRoom;
    final uid  = _myUid;
    if (sid == null || room == null || uid == null) return;
    if (room.isFinished) return;
    if (!room.isPlayer(uid)) return;

    final winner = room.player1.uid == uid ? room.player2 : room.player1;
    await _service.forfeitGame(
      sessionId:     sid,
      gameRoomId:    room.gameRoomId,
      forfeitingUid: uid,
      winnerUid:     winner.uid,
      winnerName:    winner.name,
    );
  }

  // ── Internal updates ──────────────────────────────────────────

  void _onRoomsUpdated(_RoomsUpdated event, Emitter<GameState> emit) {
    emit(state.copyWith(allRooms: event.rooms));
  }

  void _onInvitesUpdated(_InvitesUpdated event, Emitter<GameState> emit) {
    final uid = _myUid ?? '';
    // BUG-G02 FIX: filter out invites older than 5 min (sender may have crashed)
    final pending = event.invites.where((i) => i.toUid   == uid && i.isPending && !i.isExpired).toList();
    final sent    = event.invites.where((i) => i.fromUid == uid && i.isPending && !i.isExpired).toList();
    emit(state.copyWith(pendingInvites: pending, sentInvites: sent));
  }

  void _onCurrentRoomUpdated(
      _CurrentRoomUpdated event, Emitter<GameState> emit) {
    if (event.room == null) {
      emit(state.copyWith(clearRoom: true, isInRoom: false, clearChess: true));
      return;
    }
    final room = event.room!;
    // Sync chess state from server
    ChessState? newCs = state.chessState;
    if (room.gameType == GameType.chess) {
      final serverCs = ChessLogic.fromJson(room.gameStateJson);
      // Only update from server if server has more moves (prevents echo)
      if (newCs == null || serverCs.moves.length >= newCs.moves.length) {
        newCs = serverCs;
      }
    }
    // BUG-G03 FIX: detect spectate request outcome for the requester
    SpectateStatus newSpectateStatus = state.spectateStatus;
    final uid = _myUid ?? '';
    if (state.spectateStatus == SpectateStatus.pending) {
      if (room.isSpectator(uid)) {
        newSpectateStatus = SpectateStatus.approved; // request was accepted
      } else if (!room.hasPendingSpectateRequest(uid)) {
        newSpectateStatus = SpectateStatus.rejected; // request was rejected
      }
    }
    emit(state.copyWith(currentRoom: room, chessState: newCs,
        spectateStatus: newSpectateStatus));
    // Show spectator requests to players
    if (room.pendingSpectatorRequests.isNotEmpty && room.isPlayer(_myUid ?? '')) {
      debugPrint('[Game] ${room.pendingSpectatorRequests.length} spectator requests pending');
    }
  }

  // BUG-U03 FIX: reset all state and subscriptions between Together sessions
  Future<void> _onReset(GameReset event, Emitter<GameState> emit) async {
    await _roomsSub?.cancel();
    await _invitesSub?.cancel();
    await _currentRoomSub?.cancel();
    _roomsSub = null;
    _invitesSub = null;
    _currentRoomSub = null;
    _sessionId = null;
    _myUid = null;
    _myName = null;
    emit(const GameState());
  }

  @override
  Future<void> close() async {
    await _roomsSub?.cancel();
    await _invitesSub?.cancel();
    await _currentRoomSub?.cancel();
    return super.close();
  }
}
