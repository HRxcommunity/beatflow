import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/game_bloc.dart';
import '../bloc/together_bloc.dart';
import '../domain/entities/game_entity.dart';
import '../domain/entities/chess_ludo_ttt.dart';
import '../../../../core/theme/app_theme.dart';
import 'games/chess_board.dart';
import 'games/tictactoe_board.dart';
import 'games/ludo_board.dart';

class GameRoomScreen extends StatefulWidget {
  final GameRoom room;
  final String   myUid;
  final String   myName;
  final String   sessionId;

  const GameRoomScreen({
    super.key,
    required this.room,
    required this.myUid,
    required this.myName,
    required this.sessionId,
  });

  @override
  State<GameRoomScreen> createState() => _GameRoomScreenState();
}

class _GameRoomScreenState extends State<GameRoomScreen>
    with TickerProviderStateMixin {
  late AnimationController _headerAnim;
  late Animation<double>   _headerFade;

  static const Color _purple = Color(0xFF7C3AED);

  @override
  void initState() {
    super.initState();
    _headerAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400))
      ..forward();
    _headerFade = CurvedAnimation(parent: _headerAnim, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _headerAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<GameBloc, GameState>(
      listenWhen: (p, c) =>
          c.currentRoom?.isFinished == true &&
          p.currentRoom?.isFinished != true,
      listener: (ctx, gs) {
        if (gs.currentRoom?.isFinished == true) {
          _showResultDialog(ctx, gs.currentRoom!);
        }
        // Spectator request — show to players
        final room = gs.currentRoom;
        if (room != null && room.isPlayer(widget.myUid)) {
          final newReqs = room.pendingSpectatorRequests;
          if (newReqs.isNotEmpty) {
            _showSpectatorRequestSnack(ctx, newReqs.last);
          }
        }
      },
      builder: (context, gs) {
        final room      = gs.currentRoom ?? widget.room;
        final isPlayer  = room.isPlayer(widget.myUid);
        final isSpectator = room.isSpectator(widget.myUid);
        final isMyTurn  = room.currentTurnUid == widget.myUid && !room.isFinished;
        final amPlayer1 = room.player1.uid == widget.myUid;

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A1A),
          body: Stack(
            children: [
              // Background gradient
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: 1.5,
                      colors: [
                        _purple.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: Column(
                  children: [
                    // ── Header ────────────────────────────────
                    FadeTransition(
                      opacity: _headerFade,
                      child: _GameHeader(
                        room:      room,
                        myUid:     widget.myUid,
                        isSpectator: isSpectator && !isPlayer,
                        onBack:    () {
                          context.read<GameBloc>().add(GameLeaveRoom());
                          Navigator.pop(context);
                        },
                        onForfeit: isPlayer && !room.isFinished
                            ? () => _showForfeitDialog(context)
                            : null,
                      ),
                    ),

                    // ── Mini music player ──────────────────────
                    const _MiniMusicBar(),

                    // ── Turn indicator ─────────────────────────
                    if (!room.isFinished)
                      _TurnIndicator(
                        room:     room,
                        isMyTurn: isMyTurn,
                        myUid:    widget.myUid,
                      ),

                    // ── Game board ─────────────────────────────
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: _buildGameContent(context, gs, room,
                            isMyTurn: isMyTurn,
                            amPlayer1: amPlayer1,
                            isPlayer: isPlayer),
                      ),
                    ),

                    // ── Move history / status ──────────────────
                    if (room.gameType == GameType.chess && gs.chessState != null)
                      _MoveHistoryBar(moves: gs.chessState!.moves),

                    const SizedBox(height: 8),
                  ],
                ),
              ),

              // ── Spectator badge ──────────────────────────────
              if (isSpectator && !isPlayer)
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 12,
                  left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.white24, width: 1),
                      ),
                      child: const Text(
                        '👁  Spectating',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGameContent(
    BuildContext context,
    GameState gs,
    GameRoom room, {
    required bool isMyTurn,
    required bool amPlayer1,
    required bool isPlayer,
  }) {
    switch (room.gameType) {
      case GameType.chess:
        final cs = gs.chessState ?? ChessLogic.fromJson(room.gameStateJson);
        return Column(
          children: [
            // Captured by opponent
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: CapturedPiecesRow(
                pieces: amPlayer1 ? cs.capturedByBlack : cs.capturedByWhite,
                label:  'Captured:',
              ),
            ),
            Expanded(
              child: ChessBoardWidget(
                chessState: cs,
                myUid:      widget.myUid,
                player1Uid: room.player1.uid,
                isMyTurn:   isMyTurn && isPlayer,
                isFinished: room.isFinished,
                onSquareTap: (sq) =>
                    context.read<GameBloc>().add(GameSelectChessSquare(sq)),
              ),
            ),
            // Captured by me
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: CapturedPiecesRow(
                pieces: amPlayer1 ? cs.capturedByWhite : cs.capturedByBlack,
                label:  'You captured:',
              ),
            ),
          ],
        );

      case GameType.tictactoe:
        final ttt  = TttLogic.fromJson(room.gameStateJson);
        final mark = room.player1.uid == widget.myUid ? 'X' : 'O';
        return TicTacToeBoard(
          state:      ttt,
          myMark:     mark,
          isMyTurn:   isMyTurn && isPlayer,
          isFinished: room.isFinished,
          onCellTap:  (cell) =>
              context.read<GameBloc>().add(GameMakeTttMove(cell)),
        );

      case GameType.ludo:
        final ludo    = LudoLogic.fromJson(room.gameStateJson);
        final isRedPl = room.player1.uid == widget.myUid;
        return LudoBoardWidget(
          state:        ludo,
          isRedPlayer:  isRedPl,
          isMyTurn:     isMyTurn && isPlayer,
          isFinished:   room.isFinished,
          onRollDice:   () => context.read<GameBloc>().add(GameRollLudoDice()),
          onMovePiece:  (i) =>
              context.read<GameBloc>().add(GameMoveLudoPiece(i)),
        );
    }
  }

  void _showResultDialog(BuildContext context, GameRoom room) {
    final myWin = room.winnerId == widget.myUid;
    final isDraw = room.winnerId == null && room.isFinished;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Center(
          child: Text(
            myWin ? '🏆 You Win!' : isDraw ? '🤝 Draw!' : '😔 You Lost',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
        ),
        content: Text(
          myWin
              ? 'Congratulations! You beat ${room.opponentName(widget.myUid)}!'
              : isDraw
                  ? 'Well played by both sides!'
                  : '${room.winnerName ?? "Opponent"} wins this round.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              context.read<GameBloc>().add(GameLeaveRoom());
              Navigator.pop(context); // close room screen
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              elevation: 0,
            ),
            child: const Text('Back to Session',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showForfeitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Forfeit Game?',
            style: TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
          'Your opponent will win if you forfeit.',
          style:
              TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<GameBloc>().add(GameForfeit());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Forfeit',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showSpectatorRequestSnack(BuildContext context, SpectatorRequest req) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${req.name} wants to watch your game!'),
        backgroundColor: AppTheme.bgCard,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'Allow',
          textColor: _purple,
          onPressed: () {
            context
                .read<GameBloc>()
                .add(GameApproveSpectator(req));
          },
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
//  GAME HEADER
// ════════════════════════════════════════════

class _GameHeader extends StatelessWidget {
  final GameRoom     room;
  final String       myUid;
  final bool         isSpectator;
  final VoidCallback onBack;
  final VoidCallback? onForfeit;

  const _GameHeader({
    required this.room,
    required this.myUid,
    required this.isSpectator,
    required this.onBack,
    this.onForfeit,
  });

  @override
  Widget build(BuildContext context) {
    final p1IsMe = room.player1.uid == myUid;
    final myName = p1IsMe ? room.player1.name : room.player2.name;
    final opName = p1IsMe ? room.player2.name : room.player1.name;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  color: Colors.white70, size: 16),
            ),
            onPressed: onBack,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(room.gameType.emoji,
                    style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    isSpectator
                        ? '${room.player1.name} vs ${room.player2.name}'
                        : '$myName vs $opName',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (onForfeit != null)
            TextButton(
              onPressed: onForfeit,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              child: const Text('Forfeit',
                  style:
                      TextStyle(color: AppTheme.accentPink, fontSize: 12)),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
//  MINI MUSIC BAR (music keeps playing)
// ════════════════════════════════════════════

class _MiniMusicBar extends StatelessWidget {
  const _MiniMusicBar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TogetherBloc, TogetherState>(
      builder: (ctx, ts) {
        final session = ts.session;
        if (session == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
          ),
          child: Row(
            children: [
              Icon(
                session.isPlaying
                    ? Icons.music_note_rounded
                    : Icons.music_off_rounded,
                color: session.isPlaying
                    ? const Color(0xFF7C3AED)
                    : Colors.white38,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.songTitle.isNotEmpty
                      ? '♫  ${session.songTitle}'
                      : '♫  Music playing',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: session.isPlaying
                      ? const Color(0xFF22C55E)
                      : Colors.white24,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════
//  TURN INDICATOR
// ════════════════════════════════════════════

class _TurnIndicator extends StatelessWidget {
  final GameRoom room;
  final bool     isMyTurn;
  final String   myUid;

  const _TurnIndicator({
    required this.room,
    required this.isMyTurn,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    final currentName = room.player1.uid == room.currentTurnUid
        ? room.player1.name
        : room.player2.name;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: isMyTurn
            ? const Color(0xFF7C3AED).withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMyTurn
              ? const Color(0xFF7C3AED).withValues(alpha: 0.5)
              : Colors.white12,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMyTurn) ...[
            Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF22C55E),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            isMyTurn
                ? 'Your turn!'
                : "$currentName's turn",
            style: TextStyle(
              color: isMyTurn ? Colors.white : Colors.white60,
              fontSize: 13,
              fontWeight:
                  isMyTurn ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
//  MOVE HISTORY BAR (Chess)
// ════════════════════════════════════════════

class _MoveHistoryBar extends StatelessWidget {
  final List<String> moves;
  const _MoveHistoryBar({required this.moves});

  @override
  Widget build(BuildContext context) {
    if (moves.isEmpty) return const SizedBox.shrink();
    final last5 = moves.length > 5 ? moves.sublist(moves.length - 5) : moves;
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: last5.length,
        shrinkWrap: true,
        separatorBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('·', style: TextStyle(color: Colors.white24)),
        ),
        itemBuilder: (_, i) {
          final moveNum  = moves.length - last5.length + i + 1;
          return Center(
            child: Text(
              '${(moveNum / 2).ceil()}. ${last5[i]}',
              style: const TextStyle(
                  color: Colors.white54, fontSize: 11),
            ),
          );
        },
      ),
    );
  }
}
