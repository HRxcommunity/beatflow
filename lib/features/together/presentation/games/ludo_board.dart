import 'package:flutter/material.dart';
import '../../domain/entities/chess_ludo_ttt.dart';

class LudoBoardWidget extends StatelessWidget {
  final LudoState  state;
  final bool       isRedPlayer;
  final bool       isMyTurn;
  final bool       isFinished;
  final VoidCallback           onRollDice;
  final void Function(int i)   onMovePiece;

  const LudoBoardWidget({
    super.key,
    required this.state,
    required this.isRedPlayer,
    required this.isMyTurn,
    required this.isFinished,
    required this.onRollDice,
    required this.onMovePiece,
  });

  static const Color _red    = Color(0xFFEF4444);
  static const Color _blue   = Color(0xFF3B82F6);
  static const Color _safe   = Color(0xFF22C55E);

  // Generate track cells (52 squares in a cross pattern)
  // We render as a visual 15x15 grid for standard Ludo look
  // For simplicity, we show a linear path with player positions

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Board visual ──────────────────────────────────────
        Expanded(
          child: _LudoBoard(
            state:        state,
            isRedPlayer:  isRedPlayer,
            onMovePiece:  isMyTurn && state.diceRolled && !isFinished
                ? onMovePiece
                : null,
          ),
        ),

        // ── Controls ──────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              // Dice
              GestureDetector(
                onTap: isMyTurn && !state.diceRolled && !isFinished
                    ? onRollDice
                    : null,
                child: _DiceFace(
                  value:   state.diceValue,
                  active:  isMyTurn && !state.diceRolled && !isFinished,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isMyTurn && !state.diceRolled && !isFinished) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Tap dice to roll!',
                        style: TextStyle(
                          color: isRedPlayer ? _red : _blue,
                          fontSize: 12,
                        ),
                      ),
                    ] else if (isMyTurn && state.diceRolled && !isFinished) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Tap a piece to move it.',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════
//  LUDO BOARD VISUAL (15×15 grid approximation)
// ════════════════════════════════════════════

class _LudoBoard extends StatelessWidget {
  final LudoState              state;
  final bool                   isRedPlayer;
  final void Function(int)?    onMovePiece;

  const _LudoBoard({
    required this.state,
    required this.isRedPlayer,
    this.onMovePiece,
  });

  static const Color _red    = Color(0xFFEF4444);
  static const Color _blue   = Color(0xFF3B82F6);
  static const Color _safe   = Color(0xFF22C55E);
  static const Color _board  = Color(0xFF1A1A2E);
  static const Color _track  = Color(0xFF2D2D3F);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final size = constraints.maxWidth.clamp(0.0, constraints.maxHeight);
      return SizedBox(
        width: size, height: size,
        child: Stack(children: [
          // Background board
          Container(
            decoration: BoxDecoration(
              color: _board,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
          ),

          // Red home (top-left)
          Positioned(
            top: 0, left: 0,
            child: _HomeArea(
              color:       _red,
              label:       'RED',
              pieces:      state.redPieces,
              done:        state.redPieces.where((p) => p >= LudoLogic.finishPos).length,
              canMove:     isRedPlayer && onMovePiece != null,
              onMovePiece: onMovePiece,
              size:        size * 0.42,
            ),
          ),

          // Blue home (bottom-right)
          Positioned(
            bottom: 0, right: 0,
            child: _HomeArea(
              color:        _blue,
              label:        'BLUE',
              pieces:       state.bluePieces,
              done:         state.bluePieces.where((p) => p >= LudoLogic.finishPos).length,
              canMove:      !isRedPlayer && onMovePiece != null,
              onMovePiece:  onMovePiece,
              size:         size * 0.42,
            ),
          ),

          // Center finish area
          Positioned(
            top: size * 0.3, left: size * 0.3,
            child: SizedBox(
              width: size * 0.4, height: size * 0.4,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    '🏠',
                    style: TextStyle(fontSize: 30),
                  ),
                ),
              ),
            ),
          ),

          // Track cells (simplified — 12 track squares visible)
          ..._buildTrackCells(size),

          // Piece tokens on track
          ..._buildPiecesOnTrack(size),
        ]),
      );
    });
  }

  List<Widget> _buildTrackCells(double size) {
    // Show key track cells as decorative squares
    final trackPosToXY = _trackPosMap(size);
    return trackPosToXY.entries.map((e) {
      final isSafe = LudoLogic.safeSquares.contains(e.key);
      return Positioned(
        left: e.value.dx - size * 0.04,
        top:  e.value.dy - size * 0.04,
        child: Container(
          width: size * 0.08, height: size * 0.08,
          decoration: BoxDecoration(
            color: isSafe
                ? _safe.withValues(alpha: 0.2)
                : _track.withValues(alpha: 0.8),
            border: Border.all(
              color: isSafe ? _safe.withValues(alpha: 0.5) : Colors.white12,
              width: isSafe ? 1.5 : 0.5,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: isSafe
              ? const Center(
                  child: Text('★',
                      style: TextStyle(fontSize: 8, color: Color(0xFF22C55E))))
              : null,
        ),
      );
    }).toList();
  }

  List<Widget> _buildPiecesOnTrack(double size) {
    final widgets = <Widget>[];
    final trackMap = _trackPosMap(size);

    void addPiece(int relPos, Color color, int pieceIdx, bool canTap) {
      if (relPos == -1 || relPos >= LudoLogic.finishPos) return;
      final absPos = LudoLogic.absolutePos(relPos, color == _red);
      if (absPos < 0 || !trackMap.containsKey(absPos)) return;
      final pos = trackMap[absPos]!;
      widgets.add(
        Positioned(
          left: pos.dx - size * 0.04,
          top:  pos.dy - size * 0.04,
          child: GestureDetector(
            onTap: canTap ? () => onMovePiece!(pieceIdx) : null,
            child: Container(
              width: size * 0.085, height: size * 0.085,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: canTap
                    ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)]
                    : null,
              ),
              child: Center(
                child: Text(
                  '${pieceIdx + 1}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ),
      );
    }

    for (var i = 0; i < 4; i++) {
      addPiece(state.redPieces[i],  _red,  i, isRedPlayer && onMovePiece != null);
      addPiece(state.bluePieces[i], _blue, i, !isRedPlayer && onMovePiece != null);
    }
    return widgets;
  }

  // Map absolute track positions (0–51) → visual XY
  Map<int, Offset> _trackPosMap(double size) {
    final m = <int, Offset>{};
    final c = size / 2;
    final r = size * 0.38;

    // Arrange 52 positions around a rectangular track
    for (var i = 0; i < 52; i++) {
      final angle = (i / 52) * 2 * 3.14159265;
      m[i] = Offset(c + r * 0.8 * _cos(angle), c + r * 0.8 * _sin(angle));
    }
    return m;
  }

  double _cos(double angle) => angle < 1.57
      ? 1 - angle * angle / 2
      : angle < 3.14
          ? -(angle - 1.57) * (angle - 1.57) / 2 + 0
          : angle < 4.71
              ? -1 + (angle - 3.14) * (angle - 3.14) / 2
              : (angle - 4.71) * (angle - 4.71) / 2 - 0;

  double _sin(double angle) => _cos(angle - 1.5708);
}

// ════════════════════════════════════════════
//  HOME AREA
// ════════════════════════════════════════════

class _HomeArea extends StatelessWidget {
  final Color              color;
  final String             label;
  final List<int>          pieces;
  final int                done;
  final bool               canMove;
  final void Function(int)? onMovePiece;
  final double             size;

  const _HomeArea({
    required this.color,
    required this.label,
    required this.pieces,
    required this.done,
    required this.canMove,
    required this.onMovePiece,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.only(
          topLeft:     label == 'RED'  ? const Radius.circular(12) : Radius.zero,
          bottomRight: label == 'BLUE' ? const Radius.circular(12) : Radius.zero,
        ),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          // 2×2 grid of pieces
          SizedBox(
            width: size * 0.7,
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(4, (i) {
                final pos     = pieces[i];
                final atHome  = pos == -1;
                final finished = pos >= LudoLogic.finishPos;
                final onTrack  = pos >= 0 && !finished;
                return GestureDetector(
                  onTap: (canMove && atHome && onMovePiece != null)
                      ? () => onMovePiece!(i)
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: atHome
                          ? color.withValues(alpha: 0.8)
                          : finished
                              ? const Color(0xFF22C55E)
                              : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: canMove && atHome ? 2.0 : 1.0,
                      ),
                      boxShadow: canMove && atHome
                          ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        finished ? '✓' : onTrack ? '' : '${i + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 4),
          Text('$done/4 home',
              style: const TextStyle(
                  color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
//  DICE FACE
// ════════════════════════════════════════════

class _DiceFace extends StatelessWidget {
  final int  value;
  final bool active;

  const _DiceFace({required this.value, required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF7C3AED)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? const Color(0xFF9333EA)
              : Colors.white24,
          width: active ? 2 : 1,
        ),
        boxShadow: active
            ? [const BoxShadow(
                color: Color(0x557C3AED), blurRadius: 12, offset: Offset(0, 4))]
            : null,
      ),
      child: Center(
        child: value == 0
            ? Icon(Icons.casino_rounded,
                color: active ? Colors.white : Colors.white38, size: 28)
            : Text(
                _dots[value] ?? '?',
                style: const TextStyle(fontSize: 28),
              ),
      ),
    );
  }

  static const _dots = {
    1: '⚀', 2: '⚁', 3: '⚂', 4: '⚃', 5: '⚄', 6: '⚅',
  };
}
