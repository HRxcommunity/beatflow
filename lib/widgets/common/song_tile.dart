import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/song_entity.dart';
import '../../core/theme/app_theme.dart';
import '../../presentation/settings/settings_bloc.dart';
import 'song_artwork_widget.dart';

class SongTile extends StatelessWidget {
  final SongEntity song;
  final VoidCallback onTap;
  final bool isPlaying;
  final Widget? trailing;

  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.isPlaying = false,
    this.trailing,
  });

  /// Resolve card base color from settings
  Color _cardBaseColor(BuildContext context, SettingsState settings) {
    final accent = Theme.of(context).colorScheme.primary;
    switch (settings.songCardColorIndex) {
      case 1: // Accent tint
        return accent;
      case 2: // White
        return Colors.white;
      case 3: // Black
        return Colors.black;
      default: // 0 = dark (default)
        return AppTheme.bgCard;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, c) =>
          p.songCardOpacity != c.songCardOpacity ||
          p.songCardColorIndex != c.songCardColorIndex ||
          p.songCardColorValue != c.songCardColorValue,
      builder: (context, settings) {
        final baseColor = _cardBaseColor(context, settings);
        final cardColor = isPlaying
            ? accent.withOpacity(0.15)
            : baseColor.withOpacity(settings.songCardOpacity);

        final borderColor = isPlaying
            ? accent.withOpacity(0.30)
            : Colors.white.withOpacity(settings.songCardOpacity * 0.08);

        return GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Row(
              children: [
                // Art
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SongArtworkWidget(songId: song.id, size: 46, borderRadius: 10),
                    if (isPlaying)
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.equalizer_rounded, color: accent, size: 22),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isPlaying ? accent : AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Duration
                Text(
                  _fmt(Duration(milliseconds: song.duration)),
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 4),
                trailing ??
                    Icon(Icons.more_vert_rounded,
                        color: AppTheme.textSecondary.withOpacity(0.5), size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
