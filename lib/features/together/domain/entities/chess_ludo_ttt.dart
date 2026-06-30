import 'dart:convert';
import 'dart:math';

// ════════════════════════════════════════════
//  CHESS GAME STATE
// ════════════════════════════════════════════

class ChessState {
  final List<String> board;          // 64 squares, '' | 'wP'|'bK' etc.
  final String       currentTurn;    // 'white' | 'black'
  final List<String> moves;          // algebraic move history
  final bool         isCheck;
  final bool         isCheckmate;
  final bool         isDraw;
  final int?         selectedSquare; // index of selected piece
  final List<int>    validMoves;     // valid destinations for selected
  final bool         whiteCanCastleK;
  final bool         whiteCanCastleQ;
  final bool         blackCanCastleK;
  final bool         blackCanCastleQ;
  final int          enPassantTarget; // target square index, -1 if none
  final List<String> capturedByWhite;
  final List<String> capturedByBlack;
  final int          halfMoveClock;  // for 50-move rule
  final int          fullMoveNumber;

  const ChessState({
    required this.board,
    required this.currentTurn,
    required this.moves,
    required this.isCheck,
    required this.isCheckmate,
    required this.isDraw,
    this.selectedSquare,
    required this.validMoves,
    this.whiteCanCastleK  = true,
    this.whiteCanCastleQ  = true,
    this.blackCanCastleK  = true,
    this.blackCanCastleQ  = true,
    this.enPassantTarget  = -1,
    required this.capturedByWhite,
    required this.capturedByBlack,
    this.halfMoveClock    = 0,
    this.fullMoveNumber   = 1,
  });

  static ChessState initial() {
    final board = ChessLogic.initialBoard();
    return ChessState(
      board:           board,
      currentTurn:     'white',
      moves:           const [],
      isCheck:         false,
      isCheckmate:     false,
      isDraw:          false,
      validMoves:      const [],
      capturedByWhite: const [],
      capturedByBlack: const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'board':            board,
        'currentTurn':      currentTurn,
        'moves':            moves,
        'isCheck':          isCheck,
        'isCheckmate':      isCheckmate,
        'isDraw':           isDraw,
        'whiteCanCastleK':  whiteCanCastleK,
        'whiteCanCastleQ':  whiteCanCastleQ,
        'blackCanCastleK':  blackCanCastleK,
        'blackCanCastleQ':  blackCanCastleQ,
        'enPassantTarget':  enPassantTarget,
        'capturedByWhite':  capturedByWhite,
        'capturedByBlack':  capturedByBlack,
        'halfMoveClock':    halfMoveClock,
        'fullMoveNumber':   fullMoveNumber,
      };

  factory ChessState.fromJson(Map<String, dynamic> j) => ChessState(
        board:           (j['board'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
        currentTurn:     j['currentTurn']     as String? ?? 'white',
        moves:           (j['moves'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
        isCheck:         j['isCheck']         as bool? ?? false,
        isCheckmate:     j['isCheckmate']     as bool? ?? false,
        isDraw:          j['isDraw']          as bool? ?? false,
        validMoves:      const [],
        whiteCanCastleK: j['whiteCanCastleK'] as bool? ?? true,
        whiteCanCastleQ: j['whiteCanCastleQ'] as bool? ?? true,
        blackCanCastleK: j['blackCanCastleK'] as bool? ?? true,
        blackCanCastleQ: j['blackCanCastleQ'] as bool? ?? true,
        enPassantTarget: j['enPassantTarget'] as int?  ?? -1,
        capturedByWhite: (j['capturedByWhite'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
        capturedByBlack: (j['capturedByBlack'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
        halfMoveClock:   j['halfMoveClock']   as int? ?? 0,
        fullMoveNumber:  j['fullMoveNumber']  as int? ?? 1,
      );

  ChessState copyWith({
    List<String>? board, String? currentTurn, List<String>? moves,
    bool? isCheck, bool? isCheckmate, bool? isDraw,
    int? selectedSquare, List<int>? validMoves,
    bool? whiteCanCastleK, bool? whiteCanCastleQ,
    bool? blackCanCastleK, bool? blackCanCastleQ,
    int? enPassantTarget,
    List<String>? capturedByWhite, List<String>? capturedByBlack,
    int? halfMoveClock, int? fullMoveNumber,
    bool clearSelection = false,
  }) =>
      ChessState(
        board:           board           ?? this.board,
        currentTurn:     currentTurn     ?? this.currentTurn,
        moves:           moves           ?? this.moves,
        isCheck:         isCheck         ?? this.isCheck,
        isCheckmate:     isCheckmate     ?? this.isCheckmate,
        isDraw:          isDraw          ?? this.isDraw,
        selectedSquare:  clearSelection  ? null : (selectedSquare ?? this.selectedSquare),
        validMoves:      clearSelection  ? const [] : (validMoves ?? this.validMoves),
        whiteCanCastleK: whiteCanCastleK ?? this.whiteCanCastleK,
        whiteCanCastleQ: whiteCanCastleQ ?? this.whiteCanCastleQ,
        blackCanCastleK: blackCanCastleK ?? this.blackCanCastleK,
        blackCanCastleQ: blackCanCastleQ ?? this.blackCanCastleQ,
        enPassantTarget: enPassantTarget ?? this.enPassantTarget,
        capturedByWhite: capturedByWhite ?? this.capturedByWhite,
        capturedByBlack: capturedByBlack ?? this.capturedByBlack,
        halfMoveClock:   halfMoveClock   ?? this.halfMoveClock,
        fullMoveNumber:  fullMoveNumber  ?? this.fullMoveNumber,
      );
}

// ════════════════════════════════════════════
//  CHESS LOGIC ENGINE
// ════════════════════════════════════════════

class ChessLogic {
  // Initial board positions
  static List<String> initialBoard() => [
        'bR','bN','bB','bQ','bK','bB','bN','bR', // rank 8 (indices 0-7)
        'bP','bP','bP','bP','bP','bP','bP','bP', // rank 7 (indices 8-15)
        '','','','','','','','',                  // rank 6
        '','','','','','','','',                  // rank 5
        '','','','','','','','',                  // rank 4
        '','','','','','','','',                  // rank 3
        'wP','wP','wP','wP','wP','wP','wP','wP', // rank 2 (indices 48-55)
        'wR','wN','wB','wQ','wK','wB','wN','wR', // rank 1 (indices 56-63)
      ];

  static String? pieceColor(String piece) {
    if (piece.isEmpty) return null;
    return piece[0] == 'w' ? 'white' : 'black';
  }

  static String pieceType(String piece) =>
      piece.length >= 2 ? piece[1] : '';

  static String opponentColor(String color) =>
      color == 'white' ? 'black' : 'white';

  static int row(int sq) => sq ~/ 8;
  static int col(int sq) => sq % 8;
  static int sq(int r, int c) => r * 8 + c;

  static bool inBounds(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

  // ── Get legal moves for a piece ──────────────────────────────

  static List<int> legalMovesForSquare(ChessState state, int from) {
    final piece = state.board[from];
    if (piece.isEmpty) return [];
    final color = pieceColor(piece)!;
    if (color != state.currentTurn) return [];

    final pseudo = _pseudoMoves(state, from, color);
    // Filter moves that leave own king in check
    return pseudo.where((to) {
      final newBoard = List<String>.from(state.board);
      _applyMoveToBoard(newBoard, from, to,
          enPassantTarget: state.enPassantTarget);
      return !_isInCheck(newBoard, color);
    }).toList();
  }

  // ── Apply a move, return new ChessState ──────────────────────

  static ChessState applyMove(ChessState state, int from, int to) {
    final board    = List<String>.from(state.board);
    final piece    = board[from];
    final color    = pieceColor(piece)!;
    final type     = pieceType(piece);
    final captured = board[to];

    List<String> capturedByWhite = List<String>.from(state.capturedByWhite);
    List<String> capturedByBlack = List<String>.from(state.capturedByBlack);
    int    newEnPassant    = -1;
    bool   newWCK         = state.whiteCanCastleK;
    bool   newWCQ         = state.whiteCanCastleQ;
    bool   newBCK         = state.blackCanCastleK;
    bool   newBCQ         = state.blackCanCastleQ;

    // Track captures (including en passant)
    if (captured.isNotEmpty) {
      if (color == 'white') capturedByWhite.add(captured);
      else capturedByBlack.add(captured);
    }
    // En passant capture
    if (type == 'P' && to == state.enPassantTarget) {
      final captureSq = color == 'white' ? to + 8 : to - 8;
      final epCaptured = board[captureSq];
      board[captureSq] = '';
      if (color == 'white') capturedByWhite.add(epCaptured);
      else capturedByBlack.add(epCaptured);
    }

    // Do the move
    _applyMoveToBoard(board, from, to, enPassantTarget: state.enPassantTarget);

    // Pawn promotion — auto queen
    if (type == 'P') {
      if (color == 'white' && row(to) == 0) board[to] = 'wQ';
      if (color == 'black' && row(to) == 7) board[to] = 'bQ';
      // Set en passant target
      if ((to - from).abs() == 16) {
        newEnPassant = (from + to) ~/ 2;
      }
    }

    // Update castling rights
    if (from == 60) { newWCK = false; newWCQ = false; } // wK moved
    if (from == 4)  { newBCK = false; newBCQ = false; } // bK moved
    if (from == 63 || to == 63) newWCK = false;  // h1 rook
    if (from == 56 || to == 56) newWCQ = false;  // a1 rook
    if (from == 7  || to == 7)  newBCK = false;  // h8 rook
    if (from == 0  || to == 0)  newBCQ = false;  // a8 rook

    final nextTurn     = opponentColor(color);
    final halfClock    = (type == 'P' || captured.isNotEmpty) ? 0 : state.halfMoveClock + 1;
    final fullMove     = color == 'black' ? state.fullMoveNumber + 1 : state.fullMoveNumber;
    final newCheck     = _isInCheck(board, nextTurn);
    final allLegal     = _allLegalMoves(board, nextTurn, newWCK, newWCQ, newBCK, newBCQ, newEnPassant);
    final newCheckmate = newCheck && allLegal.isEmpty;
    final newDraw      = (!newCheck && allLegal.isEmpty) || halfClock >= 100;

    final moveNotation = _moveNotation(state.board, from, to, captured, state.enPassantTarget);

    return state.copyWith(
      board:           board,
      currentTurn:     nextTurn,
      moves:           [...state.moves, moveNotation],
      isCheck:         newCheck,
      isCheckmate:     newCheckmate,
      isDraw:          newDraw,
      whiteCanCastleK: newWCK,
      whiteCanCastleQ: newWCQ,
      blackCanCastleK: newBCK,
      blackCanCastleQ: newBCQ,
      enPassantTarget: newEnPassant,
      capturedByWhite: capturedByWhite,
      capturedByBlack: capturedByBlack,
      halfMoveClock:   halfClock,
      fullMoveNumber:  fullMove,
      clearSelection:  true,
    );
  }

  // ── Internal helpers ─────────────────────────────────────────

  static void _applyMoveToBoard(List<String> board, int from, int to,
      {required int enPassantTarget}) {
    final piece = board[from];
    final type  = pieceType(piece);
    final color = pieceColor(piece)!;

    board[to]   = piece;
    board[from] = '';

    // En passant: remove captured pawn
    if (type == 'P' && to == enPassantTarget) {
      board[color == 'white' ? to + 8 : to - 8] = '';
    }

    // Castling: move rook
    if (type == 'K') {
      if (from == 60 && to == 62) { board[63] = ''; board[61] = 'wR'; } // K-side
      if (from == 60 && to == 58) { board[56] = ''; board[59] = 'wR'; } // Q-side
      if (from == 4  && to == 6)  { board[7]  = ''; board[5]  = 'bR'; }
      if (from == 4  && to == 2)  { board[0]  = ''; board[3]  = 'bR'; }
    }
  }

  static bool _isInCheck(List<String> board, String color) {
    // Find king
    final kingPiece = '${color[0]}K';
    final kingIdx   = board.indexOf(kingPiece);
    if (kingIdx == -1) return false;
    // Check if any opponent can capture king
    final opp = opponentColor(color);
    for (var i = 0; i < 64; i++) {
      if (pieceColor(board[i]) == opp) {
        final attacks = _rawAttacks(board, i, opp);
        if (attacks.contains(kingIdx)) return true;
      }
    }
    return false;
  }

  // Raw attacks (no check filtering) for a piece at [from]
  static List<int> _rawAttacks(List<String> board, int from, String color) {
    final piece = board[from];
    final type  = pieceType(piece);
    switch (type) {
      case 'P': return _pawnAttacks(from, color);
      case 'R': return _slidingMoves(board, from, color, [[1,0],[-1,0],[0,1],[0,-1]]);
      case 'N': return _knightMoves(board, from, color);
      case 'B': return _slidingMoves(board, from, color, [[1,1],[1,-1],[-1,1],[-1,-1]]);
      case 'Q': return _slidingMoves(board, from, color, [[1,0],[-1,0],[0,1],[0,-1],[1,1],[1,-1],[-1,1],[-1,-1]]);
      case 'K': return _kingAttacks(board, from, color);
      default:  return [];
    }
  }

  static List<int> _pseudoMoves(ChessState state, int from, String color) {
    final board = state.board;
    final piece = board[from];
    final type  = pieceType(piece);
    switch (type) {
      case 'P': return _pawnMoves(board, from, color, state.enPassantTarget);
      case 'R': return _slidingMoves(board, from, color, [[1,0],[-1,0],[0,1],[0,-1]]);
      case 'N': return _knightMoves(board, from, color);
      case 'B': return _slidingMoves(board, from, color, [[1,1],[1,-1],[-1,1],[-1,-1]]);
      case 'Q': return _slidingMoves(board, from, color, [[1,0],[-1,0],[0,1],[0,-1],[1,1],[1,-1],[-1,1],[-1,-1]]);
      case 'K': return _kingMoves(board, from, color, state);
      default:  return [];
    }
  }

  static List<int> _pawnAttacks(int from, String color) {
    final r    = row(from);
    final c    = col(from);
    final dir  = color == 'white' ? -1 : 1;
    final List<int> attacks = [];
    for (final dc in [-1, 1]) {
      final nr = r + dir; final nc = c + dc;
      if (inBounds(nr, nc)) attacks.add(sq(nr, nc));
    }
    return attacks;
  }

  static List<int> _pawnMoves(List<String> board, int from, String color, int ep) {
    final r   = row(from);
    final c   = col(from);
    final dir = color == 'white' ? -1 : 1;
    final startRow = color == 'white' ? 6 : 1;
    final List<int> moves = [];

    // Forward 1
    final r1 = r + dir;
    if (inBounds(r1, c) && board[sq(r1, c)].isEmpty) {
      moves.add(sq(r1, c));
      // Forward 2 from start
      if (r == startRow) {
        final r2 = r + 2 * dir;
        if (board[sq(r2, c)].isEmpty) moves.add(sq(r2, c));
      }
    }
    // Diagonal captures
    for (final dc in [-1, 1]) {
      final nr = r + dir; final nc = c + dc;
      if (!inBounds(nr, nc)) continue;
      final dest = sq(nr, nc);
      final target = board[dest];
      if (target.isNotEmpty && pieceColor(target) != color) {
        moves.add(dest);
      }
      // En passant
      if (dest == ep) moves.add(dest);
    }
    return moves;
  }

  static List<int> _slidingMoves(
      List<String> board, int from, String color, List<List<int>> dirs) {
    final r = row(from); final c = col(from);
    final List<int> moves = [];
    for (final d in dirs) {
      var nr = r + d[0]; var nc = c + d[1];
      while (inBounds(nr, nc)) {
        final dest   = sq(nr, nc);
        final target = board[dest];
        if (target.isEmpty) {
          moves.add(dest);
        } else {
          if (pieceColor(target) != color) moves.add(dest);
          break;
        }
        nr += d[0]; nc += d[1];
      }
    }
    return moves;
  }

  static List<int> _knightMoves(List<String> board, int from, String color) {
    final r = row(from); final c = col(from);
    const offsets = [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]];
    return offsets
        .where((o) => inBounds(r + o[0], c + o[1]))
        .map((o) => sq(r + o[0], c + o[1]))
        .where((s) => pieceColor(board[s]) != color)
        .toList();
  }

  static List<int> _kingAttacks(List<String> board, int from, String color) {
    final r = row(from); final c = col(from);
    const offsets = [[-1,-1],[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0],[1,1]];
    return offsets
        .where((o) => inBounds(r + o[0], c + o[1]))
        .map((o) => sq(r + o[0], c + o[1]))
        .where((s) => pieceColor(board[s]) != color)
        .toList();
  }

  static List<int> _kingMoves(
      List<String> board, int from, String color, ChessState state) {
    final moves = _kingAttacks(board, from, color);
    // Castling
    if (color == 'white' && from == 60) {
      if (state.whiteCanCastleK &&
          board[61].isEmpty && board[62].isEmpty &&
          board[63] == 'wR' &&
          !_isInCheck(board, color) &&
          !_squareAttacked(board, 61, color) &&
          !_squareAttacked(board, 62, color)) {
        moves.add(62);
      }
      if (state.whiteCanCastleQ &&
          board[59].isEmpty && board[58].isEmpty && board[57].isEmpty &&
          board[56] == 'wR' &&
          !_isInCheck(board, color) &&
          !_squareAttacked(board, 59, color) &&
          !_squareAttacked(board, 58, color)) {
        moves.add(58);
      }
    }
    if (color == 'black' && from == 4) {
      if (state.blackCanCastleK &&
          board[5].isEmpty && board[6].isEmpty &&
          board[7] == 'bR' &&
          !_isInCheck(board, color) &&
          !_squareAttacked(board, 5, color) &&
          !_squareAttacked(board, 6, color)) {
        moves.add(6);
      }
      if (state.blackCanCastleQ &&
          board[3].isEmpty && board[2].isEmpty && board[1].isEmpty &&
          board[0] == 'bR' &&
          !_isInCheck(board, color) &&
          !_squareAttacked(board, 3, color) &&
          !_squareAttacked(board, 2, color)) {
        moves.add(2);
      }
    }
    return moves;
  }

  static bool _squareAttacked(List<String> board, int sq, String color) {
    final opp = opponentColor(color);
    for (var i = 0; i < 64; i++) {
      if (pieceColor(board[i]) == opp) {
        if (_rawAttacks(board, i, opp).contains(sq)) return true;
      }
    }
    return false;
  }

  static List<int> _allLegalMoves(
    List<String> board,
    String color,
    bool wck, bool wcq, bool bck, bool bcq,
    int ep,
  ) {
    final List<int> all = [];
    final mockState = ChessState(
      board: board, currentTurn: color,
      moves: const [], isCheck: false, isCheckmate: false, isDraw: false,
      validMoves: const [], capturedByWhite: const [], capturedByBlack: const [],
      whiteCanCastleK: wck, whiteCanCastleQ: wcq,
      blackCanCastleK: bck, blackCanCastleQ: bcq,
      enPassantTarget: ep,
    );
    for (var i = 0; i < 64; i++) {
      if (pieceColor(board[i]) == color) {
        all.addAll(legalMovesForSquare(mockState, i));
      }
    }
    return all;
  }

  static String _moveNotation(List<String> board, int from, int to,
      String captured, int ep) {
    final files = 'abcdefgh';
    final fr = row(from); final fc = col(from);
    final tr = row(to);   final tc = col(to);
    final fromAlg = '${files[fc]}${8 - fr}';
    final toAlg   = '${files[tc]}${8 - tr}';
    return captured.isNotEmpty || to == ep
        ? '$fromAlg×$toAlg'
        : '$fromAlg-$toAlg';
  }

  static String toJson(ChessState state) => jsonEncode(state.toJson());

  static ChessState fromJson(String json) {
    try {
      return ChessState.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return ChessState.initial();
    }
  }
}

// ════════════════════════════════════════════
//  TIC-TAC-TOE STATE + LOGIC
// ════════════════════════════════════════════

class TttState {
  final List<String> board;       // 9 cells: '' | 'X' | 'O'
  final String       currentTurn; // 'X' | 'O'
  final String       winner;      // '' | 'X' | 'O' | 'draw'
  final List<int>    winLine;     // winning indices (empty if no winner)

  const TttState({
    required this.board,
    required this.currentTurn,
    required this.winner,
    required this.winLine,
  });

  static TttState initial(String starterMark) => TttState(
        board:       List.filled(9, ''),
        currentTurn: starterMark,
        winner:      '',
        winLine:     const [],
      );

  bool get isFinished => winner.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'board':       board,
        'currentTurn': currentTurn,
        'winner':      winner,
        'winLine':     winLine,
      };

  factory TttState.fromJson(Map<String, dynamic> j) => TttState(
        board:       (j['board'] as List<dynamic>? ?? List.filled(9, '')).map((e) => e as String).toList(),
        currentTurn: j['currentTurn'] as String? ?? 'X',
        winner:      j['winner']      as String? ?? '',
        winLine:     (j['winLine'] as List<dynamic>? ?? []).map((e) => e as int).toList(),
      );

  static const List<List<int>> winLines = [
    [0,1,2],[3,4,5],[6,7,8], // rows
    [0,3,6],[1,4,7],[2,5,8], // cols
    [0,4,8],[2,4,6],         // diags
  ];
}

class TttLogic {
  static TttState applyMove(TttState state, int cellIndex, String myMark) {
    if (state.isFinished || state.board[cellIndex].isNotEmpty) return state;
    if (state.currentTurn != myMark) return state;

    final board = List<String>.from(state.board);
    board[cellIndex] = myMark;

    String winner   = '';
    List<int> winL  = [];

    for (final line in TttState.winLines) {
      if (board[line[0]].isNotEmpty &&
          board[line[0]] == board[line[1]] &&
          board[line[1]] == board[line[2]]) {
        winner = board[line[0]];
        winL   = line;
        break;
      }
    }
    if (winner.isEmpty && board.every((c) => c.isNotEmpty)) {
      winner = 'draw';
    }

    return TttState(
      board:       board,
      currentTurn: myMark == 'X' ? 'O' : 'X',
      winner:      winner,
      winLine:     winL,
    );
  }

  static String toJson(TttState state) => jsonEncode(state.toJson());
  static TttState fromJson(String json) {
    try {
      return TttState.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return TttState.initial('X');
    }
  }
}

// ════════════════════════════════════════════
//  LUDO STATE + LOGIC
// ════════════════════════════════════════════

// 2-player Ludo: Red (player1) vs Blue (player2)
// Each player has 4 pieces.
// Position per piece:
//   -1 = home (not entered)
//    0-55 = on the shared track (absolute)
//   56-60 = home column (private — 5 steps)
//   61 = finished
//
// Red enters at track[0]  and goes forward.
// Blue enters at track[26] and goes forward (offset 26, wrap around).
// Safe squares (no capture): 0, 8, 13, 21, 26, 34, 39, 47

class LudoState {
  // relative positions: -1=home, 0–60=on track + home column, 61=done
  final List<int> redPieces;
  final List<int> bluePieces;
  final bool      isRedTurn;
  final int       diceValue;   // 0 = not yet rolled
  final bool      diceRolled;
  final String    winner;      // '' | 'red' | 'blue'
  final String    message;

  const LudoState({
    required this.redPieces,
    required this.bluePieces,
    required this.isRedTurn,
    required this.diceValue,
    required this.diceRolled,
    required this.winner,
    required this.message,
  });

  static LudoState initial() => const LudoState(
        redPieces:  [-1, -1, -1, -1],
        bluePieces: [-1, -1, -1, -1],
        isRedTurn:  true,
        diceValue:  0,
        diceRolled: false,
        winner:     '',
        message:    'Red rolls first!',
      );

  bool get isFinished => winner.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'redPieces':  redPieces,
        'bluePieces': bluePieces,
        'isRedTurn':  isRedTurn,
        'diceValue':  diceValue,
        'diceRolled': diceRolled,
        'winner':     winner,
        'message':    message,
      };

  factory LudoState.fromJson(Map<String, dynamic> j) => LudoState(
        redPieces:  (j['redPieces']  as List<dynamic>? ?? [-1,-1,-1,-1]).map((e) => e as int).toList(),
        bluePieces: (j['bluePieces'] as List<dynamic>? ?? [-1,-1,-1,-1]).map((e) => e as int).toList(),
        isRedTurn:  j['isRedTurn']  as bool? ?? true,
        diceValue:  j['diceValue']  as int?  ?? 0,
        diceRolled: j['diceRolled'] as bool? ?? false,
        winner:     j['winner']     as String? ?? '',
        message:    j['message']    as String? ?? '',
      );

  LudoState copyWith({
    List<int>? redPieces, List<int>? bluePieces,
    bool? isRedTurn, int? diceValue, bool? diceRolled,
    String? winner, String? message,
  }) => LudoState(
        redPieces:  redPieces  ?? this.redPieces,
        bluePieces: bluePieces ?? this.bluePieces,
        isRedTurn:  isRedTurn  ?? this.isRedTurn,
        diceValue:  diceValue  ?? this.diceValue,
        diceRolled: diceRolled ?? this.diceRolled,
        winner:     winner     ?? this.winner,
        message:    message    ?? this.message,
      );
}

class LudoLogic {
  static const int trackLength   = 52;  // shared track squares
  static const int homeColSteps  = 5;   // home column length
  static const int finishPos     = 58;  // relative position when done

  // Red enters at absolute 0; Blue enters at absolute 26
  static const int blueOffset = 26;

  // Safe squares on the absolute track
  static const Set<int> safeSquares = {0, 8, 13, 21, 26, 34, 39, 47};

  // Convert relative position → absolute board square (for render)
  // Returns -1 if at home, -2 if finished
  static int absolutePos(int relPos, bool isRed) {
    if (relPos == -1)         return -1;  // in home
    if (relPos >= finishPos)  return -2;  // finished
    if (relPos >= trackLength) {
      // home column squares — not on shared track
      return 100 + (isRed ? 0 : 10) + (relPos - trackLength);
    }
    final offset = isRed ? 0 : blueOffset;
    return (relPos + offset) % trackLength;
  }

  // Roll dice, return new state
  static LudoState rollDice(LudoState state, bool isRedPlayer) {
    if (state.diceRolled) return state;
    if (state.isRedTurn != isRedPlayer) return state;

    final dice = Random().nextInt(6) + 1;
    final pieces = isRedPlayer ? state.redPieces : state.bluePieces;

    // Check if any move is possible
    bool canMove = false;
    for (var i = 0; i < 4; i++) {
      if (pieces[i] == -1 && dice == 6) { canMove = true; break; }
      if (pieces[i] >= 0 && pieces[i] < finishPos) {
        final newPos = pieces[i] + dice;
        if (newPos <= finishPos) { canMove = true; break; }
      }
    }

    final colorName = isRedPlayer ? 'Red' : 'Blue';
    String msg = '$colorName rolled $dice!';
    if (!canMove) msg += ' No moves available.';

    final next = state.copyWith(
      diceValue:  dice,
      diceRolled: true,
      message:    msg,
    );

    // Auto-skip turn if no move possible
    if (!canMove && dice != 6) {
      return _nextTurn(next, isRedPlayer, dice, msg + ' Turn skipped.');
    }
    return next;
  }

  // Move piece [pieceIndex] for the current player
  static LudoState movePiece(LudoState state, int pieceIndex, bool isRedPlayer) {
    if (!state.diceRolled) return state;
    if (state.isRedTurn != isRedPlayer) return state;
    if (state.winner.isNotEmpty) return state;

    final dice     = state.diceValue;
    final isRed    = isRedPlayer;
    var   pieces   = List<int>.from(isRed ? state.redPieces : state.bluePieces);
    var   opp      = List<int>.from(isRed ? state.bluePieces : state.redPieces);
    final curPos   = pieces[pieceIndex];

    // Enter board
    if (curPos == -1) {
      if (dice != 6) return state;
      pieces[pieceIndex] = 0;  // enter at position 0 (relative)
    } else if (curPos < finishPos) {
      final newPos = curPos + dice;
      if (newPos > finishPos) return state; // can't overshoot finish
      pieces[pieceIndex] = newPos;

      // Check capture — only on shared track (0–51)
      if (newPos < trackLength) {
        final absNew = absolutePos(newPos, isRed);
        if (!safeSquares.contains(absNew)) {
          for (var j = 0; j < 4; j++) {
            final oppAbs = absolutePos(opp[j], !isRed);
            if (oppAbs == absNew && opp[j] >= 0 && opp[j] < trackLength) {
              opp[j] = -1; // send home!
            }
          }
        }
      }
    } else {
      return state; // already finished
    }

    final newRed  = isRed  ? pieces : opp;
    final newBlue = !isRed ? pieces : opp;

    // Check win
    String winner = '';
    if (newRed.every((p)  => p >= finishPos)) winner = 'red';
    if (newBlue.every((p) => p >= finishPos)) winner = 'blue';

    final colorName = isRed ? 'Red' : 'Blue';
    String msg = '$colorName moved piece ${pieceIndex + 1}.';
    if (winner.isNotEmpty) msg = '🎉 $colorName wins!';

    var next = state.copyWith(
      redPieces:  newRed,
      bluePieces: newBlue,
      winner:     winner,
      message:    msg,
    );

    // Rolling 6 grants another turn; otherwise switch
    if (dice == 6 && winner.isEmpty) {
      next = next.copyWith(diceRolled: false, diceValue: 0,
          message: msg + ' Roll again!');
    } else if (winner.isEmpty) {
      next = _nextTurn(next, isRed, dice, msg);
    }
    return next;
  }

  static LudoState _nextTurn(
      LudoState state, bool wasRed, int dice, String msg) {
    final nextColor = wasRed ? 'Blue' : 'Red';
    return state.copyWith(
      isRedTurn:  !wasRed,
      diceRolled: false,
      diceValue:  0,
      message:    '$msg $nextColor\'s turn.',
    );
  }

  static String toJson(LudoState s) => jsonEncode(s.toJson());
  static LudoState fromJson(String json) {
    try {
      return LudoState.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return LudoState.initial();
    }
  }
}
