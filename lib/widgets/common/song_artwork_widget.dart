import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// Displays album/song artwork loaded from the device media store.
///
/// Falls back to a music-note placeholder when no artwork is found.
/// [albumId] is accepted for API compatibility but ignored — artwork is
/// always queried by [songId] (ArtworkType.AUDIO), which works for
/// tracks that carry embedded cover art regardless of album.
class SongArtworkWidget extends StatelessWidget {
  final int songId;

  /// Kept for call-site compatibility; not used in the query.
  final int? albumId;

  final double size;
  final double borderRadius;
  final bool isCircle;

  const SongArtworkWidget({
    super.key,
    required this.songId,
    this.albumId,
    required this.size,
    this.borderRadius = 8,
    this.isCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = isCircle ? size / 2 : borderRadius;

    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: cs.onSurface.withOpacity(0.35),
        size: size * 0.42,
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: QueryArtworkWidget(
        id: songId,
        type: ArtworkType.AUDIO,
        artworkWidth: size,
        artworkHeight: size,
        artworkBorder: BorderRadius.circular(radius),
        nullArtworkWidget: placeholder,
        keepOldArtwork: true,
        artworkQuality: FilterQuality.medium,
        artworkClipBehavior: Clip.antiAlias,
      ),
    );
  }
}
