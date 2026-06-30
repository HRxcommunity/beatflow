import 'package:flutter/material.dart';
import '../../domain/entities/chess_ludo_ttt.dart';

class TicTacToeBoard extends StatelessWidget {
  final TttState     state;
  final String       myMark;   // 'X' or 'O'
  final bool         isMyTurn;
  final bool         isFinished;
  final void Function(int cell) onCellTap;

  const TicTacToeBoard({
    super.key,
    required this.state,
    required this.myMark,
    required this.isMyTurn,
    required this.isFinished,
    required this.onCellTap,
  });

  static const _xColor = Color(0xFFEC4899);
  static const _oColor = Color(0xFF06B6D4);
  static const _winColor = Color(0xFF22C55E);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(builder: (ctx, constraints) {
          final cellSize = constraints.maxWidth / 3;
          return GridView.count(
            crossAxisCount: 3,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(9, (i) {
              final value  = state.board[i];
              final isWin  = state.winLine.contains(i);
              return GestureDetector(
                onTap: (!isMyTurn || value.isNotEmpty || isFinished)
                    ? null
                    : () => onCellTap(i),
                child: _Cell(
                  value:    value,
                  isWin:    isWin,
                  row:      i ~/ 3,
                  col:      i % 3,
                  cellSize: cellSize,
                ),
              );
            }),
          );
        }),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String value;
  final bool   isWin;
  final int    row;
  final int    col;
  final double cellSize;

  const _Cell({
    required this.value,
    required this.isWin,
    required this.row,
    required this.col,
    required this.cellSize,
  });

  static const _xColor   = Color(0xFFEC4899);
  static const _oColor   = Color(0xFF06B6D4);
  static const _winColor = Color(0xFF22C55E);
  static const _lineColor = Colors.white24;

  @override
  Widget build(BuildContext context) {
    final markColor = value == 'X' ? _xColor : _oColor;
    return Container(
      decoration: BoxDecoration(
        color: isWin
            ? _winColor.withOpacity(0.15)
            : Colors.white.withOpacity(0.04),
        border: Border(
          right:  col < 2 ? const BorderSide(color: _lineColor, width: 2) : BorderSide.none,
          bottom: row < 2 ? const BorderSide(color: _lineColor, width: 2) : BorderSide.none,
        ),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: value.isEmpty
              ? const SizedBox.shrink()
              : Text(
                  value,
                  key: ValueKey(value),
                  style: TextStyle(
                    fontSize: cellSize * 0.55,
                    fontWeight: FontWeight.w900,
                    color: isWin ? _winColor : markColor,
                  ),
                ),
        ),
      ),
    );
  }
}
