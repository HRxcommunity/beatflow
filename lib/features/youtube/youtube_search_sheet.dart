import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../together/bloc/together_bloc.dart';
import 'youtube_service.dart';
import '../../core/theme/app_theme.dart';

// ╔══════════════════════════════════════════════════════════════╗
// ║  YOUTUBE SEARCH SHEET — shown inside BeatFlow Together       ║
// ║  Host can search, play, or share YouTube tracks in chat.     ║
// ╚══════════════════════════════════════════════════════════════╝

class YoutubeSearchSheet extends StatefulWidget {
  final bool isOwner;

  const YoutubeSearchSheet({super.key, required this.isOwner});

  @override
  State<YoutubeSearchSheet> createState() => _YoutubeSearchSheetState();
}

class _YoutubeSearchSheetState extends State<YoutubeSearchSheet> {
  final _ctrl = TextEditingController();
  String? _loadingId; // track being loaded

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _search(BuildContext ctx) {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(ctx).unfocus();
    ctx.read<TogetherBloc>().add(TogetherSearchYoutube(q));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return BlocListener<TogetherBloc, TogetherState>(
      listenWhen: (p, c) => p.error != c.error && c.error != null,
      listener: (ctx, state) {
        // Show error snackbar when YouTube search or play fails
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text(state.error!)),
              ]),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      },
      child: DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ── Drag handle ────────────────────────────────
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Header ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF0000).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.smart_display_rounded,
                          color: Color(0xFFFF0000), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('YouTube Search',
                            style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        Text(
                          widget.isOwner
                              ? 'Search & play for everyone'
                              : 'Search & share tracks in chat',
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Search bar ─────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(context),
                        decoration: InputDecoration(
                          hintText: 'Search songs, artists...',
                          hintStyle: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 14),
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: AppTheme.textSecondary, size: 20),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.07),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: accent, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _search(context),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                              colors: [accent, accent.withOpacity(0.7)]),
                        ),
                        child: const Icon(Icons.search_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Results ─────────────────────────────────────
              Expanded(
                child: BlocBuilder<TogetherBloc, TogetherState>(
                  buildWhen: (p, c) =>
                      p.ytSearching != c.ytSearching ||
                      p.ytResults != c.ytResults ||
                      p.ytLoading  != c.ytLoading,
                  builder: (ctx, state) {
                    if (state.ytSearching) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(strokeWidth: 2),
                            SizedBox(height: 12),
                            Text('Searching YouTube...',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13)),
                          ],
                        ),
                      );
                    }
                    if (state.ytResults.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.smart_display_rounded,
                                color: Colors.white.withOpacity(0.12), size: 64),
                            const SizedBox(height: 12),
                            const Text('Search YouTube to find music',
                                style: TextStyle(
                                    color: AppTheme.textSecondary, fontSize: 13)),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: state.ytResults.length,
                      itemBuilder: (_, i) {
                        final track = state.ytResults[i];
                        final isLoading = _loadingId == track.videoId ||
                            (state.ytLoading && _loadingId == track.videoId);
                        return _YoutubeTrackTile(
                          track:    track,
                          accent:   accent,
                          isOwner:  widget.isOwner,
                          isLoading: isLoading,
                          onPlay: widget.isOwner
                              ? () {
                                  setState(() => _loadingId = track.videoId);
                                  ctx.read<TogetherBloc>()
                                      .add(TogetherPlayYoutube(track));
                                  Future.delayed(const Duration(seconds: 8), () {
                                    if (mounted) setState(() => _loadingId = null);
                                  });
                                  Navigator.pop(context);
                                }
                              : null,
                          onShare: () {
                            ctx.read<TogetherBloc>()
                                .add(TogetherShareYoutubeTrack(track));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(children: [
                                  const Icon(Icons.share_rounded,
                                      color: Colors.white, size: 16),
                                  const SizedBox(width: 8),
                                  Flexible(child: Text('Shared "${track.title}" in chat')),
                                ]),
                                backgroundColor: accent,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),   // DraggableScrollableSheet
    );   // BlocListener
  }
}

class _YoutubeTrackTile extends StatelessWidget {
  final YoutubeTrack track;
  final Color accent;
  final bool isOwner;
  final bool isLoading;
  final VoidCallback? onPlay;
  final VoidCallback onShare;

  const _YoutubeTrackTile({
    required this.track,
    required this.accent,
    required this.isOwner,
    required this.isLoading,
    required this.onPlay,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: track.thumbnailUrl,
              width: 64, height: 48,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                width: 64, height: 48,
                color: Colors.white10,
                child: const Icon(Icons.music_note_rounded,
                    color: Colors.white24, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.3)),
                const SizedBox(height: 3),
                Text(
                  '${track.artist} • ${track.durationFmt}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Action buttons
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Play (owner only)
              if (isOwner)
                GestureDetector(
                  onTap: isLoading ? null : onPlay,
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          colors: [accent, accent.withOpacity(0.7)]),
                    ),
                    child: isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 20),
                  ),
                ),
              if (isOwner) const SizedBox(height: 6),
              // Share in chat
              GestureDetector(
                onTap: onShare,
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.12), width: 1),
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded,
                      color: Colors.white60, size: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
