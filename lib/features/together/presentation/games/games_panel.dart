import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/game_bloc.dart';
import '../../bloc/together_bloc.dart';
import '../../domain/entities/game_entity.dart';
import '../../domain/entities/session_entity.dart';
import '../../../../core/theme/app_theme.dart';
import '../game_room_screen.dart';

class GamesPanel extends StatelessWidget {
  final SessionEntity session;
  final String        myUid;
  final String        accent;

  const GamesPanel({
    super.key,
    required this.session,
    required this.myUid,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = const Color(0xFF7C3AED); // games purple accent
    return BlocConsumer<GameBloc, GameState>(
      listenWhen: (p, c) =>
          c.error != null && p.error != c.error ||
          // Entered a room via invite accept — navigate
          (!p.isInRoom && c.isInRoom && c.currentRoom != null),
      listener: (ctx, gs) {
        if (gs.error != null) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text(gs.error!),
            backgroundColor: AppTheme.accentPink,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
          ctx.read<GameBloc>().add(GameClearError());
        }
        if (!context.mounted) return;
        if (gs.isInRoom && gs.currentRoom != null) {
          _openGameRoom(ctx, gs.currentRoom!);
        }
      },
      builder: (context, gs) {
        final others = session.members
            .where((m) => m.uid != myUid && m.isOnline)
            .toList();

        return Column(
          children: [
            // ── Header ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        accentColor,
                        const Color(0xFF9333EA),
                      ]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('🎮', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Games',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (gs.activeGamesCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: accentColor.withValues(alpha: 0.4), width: 1),
                      ),
                      child: Text(
                        '${gs.activeGamesCount} Live',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // ── Incoming invites ────────────────────────
                  if (gs.pendingInvites.isNotEmpty) ...[
                    _SectionLabel(label: '⚡ Challenges for You'),
                    ...gs.pendingInvites.map((inv) => _InviteCard(
                          invite:      inv,
                          accentColor: accentColor,
                          onAccept: () =>
                              context.read<GameBloc>().add(GameAcceptInvite(inv)),
                          onDecline: () =>
                              context.read<GameBloc>().add(GameDeclineInvite(inv)),
                        )),
                    const SizedBox(height: 8),
                  ],

                  // ── Active games ─────────────────────────────
                  if (gs.allRooms.isNotEmpty) ...[
                    _SectionLabel(label: '🎯 Active Games'),
                    ...gs.allRooms.map((room) => _ActiveGameCard(
                          room:        room,
                          myUid:       myUid,
                          accentColor: accentColor,
                          onJoin: () {
                            context.read<GameBloc>().add(GameEnterRoom(room.gameRoomId));
                            _openGameRoom(context, room);
                          },
                          onWatch: () {
                            if (room.isSpectator(myUid)) {
                              context.read<GameBloc>().add(GameEnterRoom(room.gameRoomId));
                              _openGameRoom(context, room);
                            } else if (room.hasPendingSpectateRequest(myUid)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Watch request sent! Waiting for approval...'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            } else {
                              context.read<GameBloc>().add(
                                  GameRequestSpectate(room.gameRoomId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('👁 Watch request sent to players!'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        )),
                    const SizedBox(height: 8),
                  ],

                  // ── Challenge someone ─────────────────────────
                  _SectionLabel(label: '🕹 Challenge Someone'),
                  if (others.isEmpty)
                    _EmptyHint(
                      icon: '👥',
                      text: 'No one else is online in this session right now.',
                    )
                  else
                    ...others.map((member) => _MemberChallengeRow(
                          member:      member,
                          accentColor: accentColor,
                          hasPending:  gs.sentInvites
                              .any((i) => i.toUid == member.uid),
                          onChallenge: (type) {
                            context.read<GameBloc>().add(GameSendInvite(
                                  gameType: type,
                                  toUid:    member.uid,
                                  toName:   member.displayName,
                                ));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    '${type.emoji} Challenge sent to ${member.displayName}!'),
                                backgroundColor:
                                    accentColor.withValues(alpha: 0.9),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          },
                        )),

                  const SizedBox(height: 16),
                  _GameInfoRow(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _openGameRoom(BuildContext context, GameRoom room) {
    final ts = context.read<TogetherBloc>().state;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<GameBloc>()),
            BlocProvider.value(value: context.read<TogetherBloc>()),
          ],
          child: GameRoomScreen(
            room:      room,
            myUid:     myUid,
            myName:    ts.displayName ?? 'Player',
            sessionId: ts.session?.sessionId ?? '',
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
//  SECTION LABEL
// ════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      );
}

// ════════════════════════════════════════════
//  INVITE CARD
// ════════════════════════════════════════════

class _InviteCard extends StatelessWidget {
  final GameInvite  invite;
  final Color       accentColor;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _InviteCard({
    required this.invite,
    required this.accentColor,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withValues(alpha: 0.12),
            accentColor.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.35), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(invite.gameType.emoji,
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invite.fromName,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'challenges you to ${invite.gameType.displayName}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.textSecondary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('Decline',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    elevation: 0,
                  ),
                  child: const Text('Accept!',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
//  ACTIVE GAME CARD
// ════════════════════════════════════════════

class _ActiveGameCard extends StatelessWidget {
  final GameRoom     room;
  final String       myUid;
  final Color        accentColor;
  final VoidCallback onJoin;
  final VoidCallback onWatch;

  const _ActiveGameCard({
    required this.room,
    required this.myUid,
    required this.accentColor,
    required this.onJoin,
    required this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    final amPlayer   = room.isPlayer(myUid);
    final amSpectator = room.isSpectator(myUid);
    final hasPending = room.hasPendingSpectateRequest(myUid);
    final isFinished = room.isFinished;

    Color statusColor;
    String statusLabel;
    if (isFinished) {
      statusColor = Colors.grey;
      statusLabel = room.winnerName != null ? '🏆 ${room.winnerName} won' : 'Finished';
    } else {
      statusColor = const Color(0xFF22C55E);
      statusLabel = 'LIVE';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isFinished
                ? Colors.white10
                : accentColor.withValues(alpha: 0.25),
            width: 1),
      ),
      child: Row(
        children: [
          Text(room.gameType.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.gameType.displayName,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${room.player1.name} vs ${room.player2.name}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(statusLabel,
                        style:
                            TextStyle(color: statusColor, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          if (amPlayer && !isFinished)
            _SmallButton(
              label: 'Resume',
              color: accentColor,
              onTap: onJoin,
            )
          else if (!isFinished)
            _SmallButton(
              label: amSpectator
                  ? 'Watch'
                  : hasPending
                      ? 'Pending...'
                      : 'Watch',
              color: amSpectator
                  ? const Color(0xFF0EA5E9)
                  : accentColor.withValues(alpha: 0.6),
              onTap: onWatch,
            )
          else if (amPlayer || amSpectator)
            _SmallButton(
              label: 'Recap',
              color: Colors.grey,
              onTap: onJoin,
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
//  MEMBER CHALLENGE ROW
// ════════════════════════════════════════════

class _MemberChallengeRow extends StatelessWidget {
  final SessionMember   member;
  final Color           accentColor;
  final bool            hasPending;
  final void Function(GameType) onChallenge;

  const _MemberChallengeRow({
    required this.member,
    required this.accentColor,
    required this.hasPending,
    required this.onChallenge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: accentColor.withValues(alpha: 0.2),
                child: Text(
                  member.displayName.isNotEmpty
                      ? member.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  member.displayName,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          if (hasPending)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '⏳ Challenge sent, waiting...',
                style: TextStyle(
                    color: accentColor, fontSize: 12),
              ),
            )
          else ...[
            const SizedBox(height: 10),
            Row(
              children: GameType.values.map((type) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _GameTypeChip(
                      type:    type,
                      onTap: () => _showChallenge(context, type),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  void _showChallenge(BuildContext context, GameType type) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '${type.emoji} Challenge ${member.displayName}?',
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16),
        ),
        content: Text(
          '${type.displayName} — ${type.description}',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
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
              onChallenge(type);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Send Challenge',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _GameTypeChip extends StatelessWidget {
  final GameType     type;
  final VoidCallback onTap;
  const _GameTypeChip({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(type.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 2),
            Text(
              type.displayName,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
//  SMALL BUTTON
// ════════════════════════════════════════════

class _SmallButton extends StatelessWidget {
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _SmallButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      );
}

// ════════════════════════════════════════════
//  EMPTY HINT
// ════════════════════════════════════════════

class _EmptyHint extends StatelessWidget {
  final String icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10, width: 1),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      );
}

// ════════════════════════════════════════════
//  GAME INFO ROW
// ════════════════════════════════════════════

class _GameInfoRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppTheme.textSecondary, size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Music keeps playing while you game 🎵',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
