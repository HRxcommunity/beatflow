import 'package:flutter/material.dart';
import '../../domain/entities/chess_ludo_ttt.dart';

class ChessBoardWidget extends StatelessWidget {
  final ChessState chessState;
  final String     myUid;
  final String     player1Uid;   // white
  final bool       isMyTurn;
  final bool       isFinished;
  final void Function(int square) onSquareTap;

  const ChessBoardWidget({
    super.key,
    required this.chessState,
    required this.myUid,
    required this.player1Uid,
    required this.isMyTurn,
    required this.isFinished,
    required this.onSquareTap,
  });

  // Am I playing white (player1)?
  bool get _iAmWhite => myUid == player1Uid;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final sqSize = constraints.maxWidth / 8;
          return Stack(
            children: [
              // ── Board squares ───────────────────────────────
              Column(
                children: List.generate(8, (visualRow) {
                  // Flip board so current player's pieces are at bottom
                  final boardRow = _iAmWhite ? visualRow : 7 - visualRow;
                  return Expanded(
                    child: Row(
                      children: List.generate(8, (visualCol) {
                        final boardCol  = _iAmWhite ? visualCol : 7 - visualCol;
                        final squareIdx = boardRow * 8 + boardCol;
                        final isDark    = (boardRow + boardCol) % 2 == 1;
                        final piece     = chessState.board[squareIdx];
                        final isSelected =
                            chessState.selectedSquare == squareIdx;
                        final isValidMove =
                            chessState.validMoves.contains(squareIdx);
                        final isCheck = chessState.isCheck &&
                            piece == (chessState.currentTurn == 'white'
                                ? 'wK'
                                : 'bK');
                        return GestureDetector(
                          onTap: isFinished
                              ? null
                              : () => onSquareTap(squareIdx),
                          child: _Square(
                            isDark:      isDark,
                            isSelected:  isSelected,
                            isValidMove: isValidMove,
                            isCheck:     isCheck,
                            piece:       piece,
                            size:        sqSize,
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),

              // ── Rank & file labels ──────────────────────────
              // Files (a–h) at bottom
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Row(
                  children: List.generate(8, (i) {
                    final col = _iAmWhite ? i : 7 - i;
                    return SizedBox(
                      width: sqSize,
                      child: Text(
                        String.fromCharCode('a'.codeUnitAt(0) + col),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: sqSize * 0.18,
                          color: Colors.white38,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              // Ranks (1–8) at left
              Positioned(
                top: 0, left: 0, bottom: 0,
                child: Column(
                  children: List.generate(8, (i) {
                    final rank = _iAmWhite ? 8 - i : i + 1;
                    return SizedBox(
                      height: sqSize,
                      child: Center(
                        child: Text(
                          '$rank',
                          style: TextStyle(
                            fontSize: sqSize * 0.18,
                            color: Colors.white38,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Square extends StatelessWidget {
  final bool   isDark;
  final bool   isSelected;
  final bool   isValidMove;
  final bool   isCheck;
  final String piece;
  final double size;

  const _Square({
    required this.isDark,
    required this.isSelected,
    required this.isValidMove,
    required this.isCheck,
    required this.piece,
    required this.size,
  });

  static const _lightSq  = Color(0xFFF0D9B5);
  static const _darkSq   = Color(0xFFB58863);
  static const _selLight  = Color(0xFFF6F669);
  static const _selDark   = Color(0xFFBBCC44);
  static const _dotColor  = Color(0x4D000000);
  static const _checkRed  = Color(0x99FF0000);

  Color get _sqColor {
    if (isCheck)    return _checkRed;
    if (isSelected) return isDark ? _selDark : _selLight;
    return isDark ? _darkSq : _lightSq;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size, height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Square background
          Container(color: _sqColor),

          // Valid move dot/ring
          if (isValidMove)
            piece.isEmpty
                ? Container(
                    width: size * 0.35,
                    height: size * 0.35,
                    decoration: const BoxDecoration(
                      color: _dotColor,
                      shape: BoxShape.circle,
                    ),
                  )
                : Container(
                    width: size - 2,
                    height: size - 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _dotColor, width: size * 0.1),
                    ),
                  ),

          // Piece
          if (piece.isNotEmpty)
            Text(
              _pieceEmoji(piece),
              style: TextStyle(
                fontSize: size * 0.72,
                height: 1,
              ),
            ),
        ],
      ),
    );
  }

  static String _pieceEmoji(String piece) {
    const map = {
      'wK': '♔', 'wQ': '♕', 'wR': '♖', 'wB': '♗', 'wN': '♘', 'wP': '♙',
      'bK': '♚', 'bQ': '♛', 'bR': '♜', 'bB': '♝', 'bN': '♞', 'bP': '♟',
    };
    return map[piece] ?? '';
  }
}

// ════════════════════════════════════════════
//  CAPTURED PIECES STRIP
// ════════════════════════════════════════════

class CapturedPiecesRow extends StatelessWidget {
  final List<String> pieces;
  final String       label;

  const CapturedPiecesRow({
    super.key,
    required this.pieces,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (pieces.isEmpty) return const SizedBox.shrink();
    final counts = <String, int>{};
    for (final p in pieces) {
      counts[p] = (counts[p] ?? 0) + 1;
    }
    return Row(
      children: [
        Text('$label  ', style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ...counts.entries.map((e) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '${_emoji(e.key)}${e.value > 1 ? "×${e.value}" : ""}',
                style: const TextStyle(fontSize: 13),
              ),
            )),
      ],
    );
  }

  static String _emoji(String piece) {
    const map = {
      'wK': '♔', 'wQ': '♕', 'wR': '♖', 'wB': '♗', 'wN': '♘', 'wP': '♙',
      'bK': '♚', 'bQ': '♛', 'bR': '♜', 'bB': '♝', 'bN': '♞', 'bP': '♟',
    };
    return map[piece] ?? '';
  }
}
