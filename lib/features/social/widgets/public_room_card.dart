import 'package:flutter/material.dart';
import '../../../features/together/domain/entities/session_entity.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/listening_avatar_widget.dart';

class PublicRoomCard extends StatelessWidget {
  final SessionEntity session;
  final VoidCallback  onJoin;
  final bool          isTrending;

  const PublicRoomCard({
    super.key,
    required this.session,
    required this.onJoin,
    this.isTrending = false,
  });

  @override
  Widget build(BuildContext context) {
    final memberCount   = session.memberCount;
    final categoryEmoji = _emojiFor(session.roomCategory);
    final catColor      = _colorFor(session.roomCategory);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color:        AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(
          color: isTrending
              ? AppTheme.accentViolet.withOpacity(0.5)
              : Colors.white.withOpacity(0.06),
          width: isTrending ? 1.5 : 1,
        ),
        boxShadow: isTrending
            ? [
                BoxShadow(
                  color:       AppTheme.accentViolet.withOpacity(0.18),
                  blurRadius:  18,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ────────────────────────────────────────
            Row(
              children: [
                // Category badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:        catColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                    border:       Border.all(color: catColor.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(categoryEmoji, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        _labelFor(session.roomCategory),
                        style: TextStyle(
                          color:      catColor,
                          fontSize:   10,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Trending badge
                if (isTrending) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:        AppTheme.accentViolet.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 10)),
                        const SizedBox(width: 3),
                        Text(
                          'TRENDING',
                          style: TextStyle(
                            color:      AppTheme.accentViolet,
                            fontSize:   9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Member count
                Row(
                  children: [
                    Icon(Icons.people_rounded,
                        size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 3),
                    Text(
                      '$memberCount',
                      style: TextStyle(
                        color:      AppTheme.textSecondary,
                        fontSize:   12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Song info ──────────────────────────────────────────
            Row(
              children: [
                // Animated note icon
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color:        catColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(color: catColor.withOpacity(0.25)),
                  ),
                  child: const Center(
                    child: Text('🎵', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.songTitle.isNotEmpty ? session.songTitle : 'Room',
                        style: const TextStyle(
                          color:      Colors.white,
                          fontSize:   14,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        session.songArtist.isNotEmpty
                            ? session.songArtist
                            : 'Unknown',
                        style: TextStyle(
                          color:    AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Members avatars + join button ──────────────────────
            Row(
              children: [
                // Stacked avatars
                _StackedAvatars(members: session.members),
                const SizedBox(width: 6),
                Text(
                  'Host: ${session.ownerName}',
                  style: TextStyle(
                    color:    AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                // Join button
                GestureDetector(
                  onTap: onJoin,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.accentViolet, AppTheme.accentCyan],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color:      AppTheme.accentViolet.withOpacity(0.35),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Text(
                      'Join 🎧',
                      style: TextStyle(
                        color:      Colors.white,
                        fontSize:   12,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color  _colorFor(String cat) {
    switch (cat) {
      case 'pop':     return AppTheme.accentPink;
      case 'hiphop':  return AppTheme.accentViolet;
      case 'lofi':    return AppTheme.accentCyan;
      case 'rock':    return const Color(0xFFF97316);
      case 'edm':     return const Color(0xFF22C55E);
      default:        return AppTheme.accentViolet;
    }
  }

  String _emojiFor(String cat) {
    switch (cat) {
      case 'pop':    return '🎤';
      case 'hiphop': return '🎤';
      case 'lofi':   return '☕';
      case 'rock':   return '🎸';
      case 'edm':    return '🎛️';
      default:       return '🎵';
    }
  }

  String _labelFor(String cat) {
    switch (cat) {
      case 'pop':    return 'POP';
      case 'hiphop': return 'HIP HOP';
      case 'lofi':   return 'LO-FI';
      case 'rock':   return 'ROCK';
      case 'edm':    return 'EDM';
      default:       return 'GENERAL';
    }
  }
}

class _StackedAvatars extends StatelessWidget {
  final List<SessionMember> members;
  const _StackedAvatars({required this.members});

  @override
  Widget build(BuildContext context) {
    final visible = members.take(4).toList();
    return SizedBox(
      width: visible.length * 18.0 + 14,
      height: 28,
      child: Stack(
        children: visible.asMap().entries.map((e) {
          final member = e.value;
          final color  = avatarColorFor(member.uid);
          return Positioned(
            left: e.key * 18.0,
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: AppTheme.bgCard, width: 2),
              ),
              child: Center(
                child: Text(
                  member.displayName.isNotEmpty
                      ? member.displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
