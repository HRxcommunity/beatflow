import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import '../bloc/together_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../youtube/youtube_service.dart';

// ╔══════════════════════════════════════════════════════════════════════╗
// ║  WatchTogetherSheet                                                   ║
// ║  Bottom sheet for creating a Watch Together session.                  ║
// ║  Two modes:                                                           ║
// ║    • YouTube  — search & pick any YouTube video                       ║
// ║    • Local    — pick a video file from the device                     ║
// ╚══════════════════════════════════════════════════════════════════════╝

class WatchTogetherSheet extends StatefulWidget {
  const WatchTogetherSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context:          context,
      backgroundColor:  Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: context.read<TogetherBloc>(),
        child: const WatchTogetherSheet(),
      ),
    );
  }

  @override
  State<WatchTogetherSheet> createState() => _WatchTogetherSheetState();
}

class _WatchTogetherSheetState extends State<WatchTogetherSheet> {
  int    _tab           = 0; // 0 = YouTube, 1 = Local Video
  bool   _isPublic      = false;
  String _roomCategory  = 'general';

  // ── YouTube search ──────────────────────────────────────────
  final _ytCtrl = TextEditingController();

  // ── Local video ─────────────────────────────────────────────
  String? _localFilePath;
  String? _localFileName;
  bool    _pickingFile = false;

  static const _categories = [
    ('general', '🎵', 'General'),
    ('pop',     '🎤', 'Pop'),
    ('hiphop',  '🎤', 'Hip Hop'),
    ('lofi',    '☕', 'Lo-Fi'),
    ('rock',    '🎸', 'Rock'),
    ('edm',     '🎛️', 'EDM'),
  ];

  @override
  void dispose() {
    _ytCtrl.dispose();
    super.dispose();
  }

  void _search(BuildContext ctx) {
    final q = _ytCtrl.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(ctx).unfocus();
    ctx.read<TogetherBloc>().add(TogetherSearchYoutube(q));
  }

  Future<void> _pickVideo() async {
    if (_pickingFile) return;
    setState(() => _pickingFile = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type:             FileType.video,
        allowMultiple:    false,
        withData:         false,
        withReadStream:   false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _localFilePath  = file.path;
          _localFileName  = file.name;
        });
      }
    } catch (e) {
      debugPrint('[WatchTogetherSheet] pickVideo error: $e');
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  void _createYouTubeSession(BuildContext ctx, YoutubeTrack track) {
    ctx.read<TogetherBloc>().add(TogetherCreateWatchSession(
      ytTrack:      track,
      isPublic:     _isPublic,
      roomCategory: _roomCategory,
    ));
    Navigator.of(ctx).pop();
  }

  void _createLocalSession(BuildContext ctx) {
    if (_localFilePath == null) return;
    ctx.read<TogetherBloc>().add(TogetherCreateWatchSession(
      localFilePath: _localFilePath,
      localFileTitle: _localFileName,
      isPublic:     _isPublic,
      roomCategory: _roomCategory,
    ));
    Navigator.of(ctx).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return BlocListener<TogetherBloc, TogetherState>(
      listenWhen: (p, c) => p.error != c.error && c.error != null,
      listener: (_, state) {
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Flexible(child: Text(state.error!)),
            ]),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ));
        }
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize:     0.5,
        maxChildSize:     0.97,
        expand: false,
        builder: (ctx, scrollCtrl) {
          return Container(
            decoration: BoxDecoration(
              color:        AppTheme.bgCard,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // ── Drag handle ──────────────────────────────
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color:        Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Header ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            const Color(0xFFFF0000).withOpacity(0.25),
                            AppTheme.accentViolet.withOpacity(0.2),
                          ]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text('🎬', style: TextStyle(fontSize: 20)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Watch Together',
                              style: TextStyle(
                                color:      AppTheme.textPrimary,
                                fontSize:   17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Watch videos in sync with friends',
                              style: TextStyle(
                                color:    AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Tab row ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _TabButton(
                        label: '▶ YouTube',
                        selected: _tab == 0,
                        accent:   const Color(0xFFFF0000),
                        onTap:    () => setState(() => _tab = 0),
                      ),
                      const SizedBox(width: 8),
                      _TabButton(
                        label: '📂 Local Video',
                        selected: _tab == 1,
                        accent:   accent,
                        onTap:    () => setState(() => _tab = 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Content ──────────────────────────────────
                Expanded(
                  child: _tab == 0
                      ? _YouTubeTab(
                          ctrl:         _ytCtrl,
                          onSearch:     () => _search(ctx),
                          onWatchTap:   (track) => _createYouTubeSession(ctx, track),
                          scrollCtrl:   scrollCtrl,
                          isPublic:     _isPublic,
                          roomCategory: _roomCategory,
                          onPublicChanged:   (v) => setState(() => _isPublic = v),
                          onCategoryChanged: (v) => setState(() => _roomCategory = v),
                          categories:   _categories,
                        )
                      : _LocalVideoTab(
                          filePath:     _localFilePath,
                          fileName:     _localFileName,
                          isPicking:    _pickingFile,
                          onPickTap:    () => _pickVideo(),
                          onWatchTap:   () => _createLocalSession(ctx),
                          isPublic:     _isPublic,
                          roomCategory: _roomCategory,
                          onPublicChanged:   (v) => setState(() => _isPublic = v),
                          onCategoryChanged: (v) => setState(() => _roomCategory = v),
                          categories:   _categories,
                          scrollCtrl:   scrollCtrl,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Tab button
// ═══════════════════════════════════════════════════════════════

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color:        selected ? accent.withOpacity(0.15) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent.withOpacity(0.5) : Colors.white12,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color:      selected ? accent : AppTheme.textSecondary,
              fontSize:   13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  YouTube tab
// ═══════════════════════════════════════════════════════════════

class _YouTubeTab extends StatelessWidget {
  final TextEditingController ctrl;
  final VoidCallback onSearch;
  final void Function(YoutubeTrack) onWatchTap;
  final ScrollController scrollCtrl;
  final bool isPublic;
  final String roomCategory;
  final void Function(bool) onPublicChanged;
  final void Function(String) onCategoryChanged;
  final List<(String, String, String)> categories;

  const _YouTubeTab({
    required this.ctrl,
    required this.onSearch,
    required this.onWatchTap,
    required this.scrollCtrl,
    required this.isPublic,
    required this.roomCategory,
    required this.onPublicChanged,
    required this.onCategoryChanged,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    const ytRed = Color(0xFFFF0000);

    return BlocBuilder<TogetherBloc, TogetherState>(
      buildWhen: (p, c) =>
          p.ytResults  != c.ytResults  ||
          p.ytSearching != c.ytSearching ||
          p.isLoading   != c.isLoading,
      builder: (ctx, state) {
        return ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            // ── Search field ──────────────────────────────────
            Row(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color:        Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border:       Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: TextField(
                    controller: ctrl,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    onSubmitted: (_) => onSearch(),
                    decoration: const InputDecoration(
                      hintText:         'Search YouTube videos…',
                      hintStyle:        TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      prefixIcon:       Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 20),
                      border:           InputBorder.none,
                      contentPadding:   EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onSearch,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [ytRed, Color(0xFFCC0000)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Search',
                      style: TextStyle(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
            const SizedBox(height: 8),

            // ── Public / Category toggles ─────────────────────
            _PublicCategorySection(
              accent:            ytRed,
              isPublic:          isPublic,
              roomCategory:      roomCategory,
              onPublicChanged:   onPublicChanged,
              onCategoryChanged: onCategoryChanged,
              categories:        categories,
            ),
            const SizedBox(height: 12),

            // ── Results ───────────────────────────────────────
            if (state.ytSearching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: ytRed, strokeWidth: 2.5),
                      SizedBox(height: 12),
                      Text('Searching YouTube…',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else if (state.ytResults.isEmpty && ctrl.text.trim().isNotEmpty && !state.ytSearching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Text('🔍', style: TextStyle(fontSize: 36)),
                      SizedBox(height: 8),
                      Text('No results. Try different keywords.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else if (state.ytResults.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Text('🎬', style: TextStyle(fontSize: 40)),
                      SizedBox(height: 12),
                      Text('Search for a YouTube video\nto watch with friends',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 14, height: 1.5)),
                    ],
                  ),
                ),
              )
            else
              ...state.ytResults.map((track) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _YouTubeResultTile(
                      track:      track,
                      onWatchTap: () => state.isLoading ? null : onWatchTap(track),
                      isLoading:  state.isLoading,
                    ),
                  )),

            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

// ─── YouTube result tile ──────────────────────────────────────

class _YouTubeResultTile extends StatelessWidget {
  final YoutubeTrack track;
  final VoidCallback? onWatchTap;
  final bool isLoading;

  const _YouTubeResultTile({
    required this.track,
    required this.onWatchTap,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    const ytRed = Color(0xFFFF0000);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:        AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl:    track.thumbnailUrl,
              width:       80,
              height:      52,
              fit:         BoxFit.cover,
              placeholder: (_, __) => Container(
                width: 80, height: 52,
                color: Colors.white.withOpacity(0.05),
                child: const Center(
                  child: Icon(Icons.smart_display_rounded,
                      color: Colors.white30, size: 20),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                width: 80, height: 52,
                decoration: BoxDecoration(
                  color:        ytRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.smart_display_rounded, color: ytRed, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines:  2,
                  overflow:  TextOverflow.ellipsis,
                  style: const TextStyle(
                    color:      AppTheme.textPrimary,
                    fontSize:   13,
                    fontWeight: FontWeight.w600,
                    height:     1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 3, height: 3,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      track.durationFmt,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Watch Together button
                GestureDetector(
                  onTap: onWatchTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        ytRed.withOpacity(isLoading ? 0.4 : 1.0),
                        const Color(0xFFCC0000).withOpacity(isLoading ? 0.3 : 0.7),
                      ]),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLoading)
                          const SizedBox(
                            width: 10, height: 10,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 1.5),
                          )
                        else
                          const Text('🎬', style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 5),
                        Text(
                          isLoading ? 'Creating…' : 'Watch Together',
                          style: const TextStyle(
                            color:      Colors.white,
                            fontSize:   11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Local Video tab
// ═══════════════════════════════════════════════════════════════

class _LocalVideoTab extends StatelessWidget {
  final String? filePath;
  final String? fileName;
  final bool isPicking;
  final VoidCallback onPickTap;
  final VoidCallback onWatchTap;
  final bool isPublic;
  final String roomCategory;
  final void Function(bool) onPublicChanged;
  final void Function(String) onCategoryChanged;
  final List<(String, String, String)> categories;
  final ScrollController scrollCtrl;

  const _LocalVideoTab({
    required this.filePath,
    required this.fileName,
    required this.isPicking,
    required this.onPickTap,
    required this.onWatchTap,
    required this.isPublic,
    required this.roomCategory,
    required this.onPublicChanged,
    required this.onCategoryChanged,
    required this.categories,
    required this.scrollCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return BlocBuilder<TogetherBloc, TogetherState>(
      buildWhen: (p, c) => p.isLoading != c.isLoading,
      builder: (ctx, state) {
        return ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            // Pick video button
            GestureDetector(
              onTap: isPicking ? null : onPickTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color:        Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(16),
                  border:       Border.all(
                    color: filePath != null
                        ? accent.withOpacity(0.4)
                        : Colors.white.withOpacity(0.12),
                    width: 1.5,
                  ),
                  gradient: filePath != null
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end:   Alignment.bottomRight,
                          colors: [accent.withOpacity(0.07), Colors.transparent])
                      : null,
                ),
                child: Column(
                  children: [
                    isPicking
                        ? CircularProgressIndicator(color: accent, strokeWidth: 2.5)
                        : Icon(
                            filePath != null
                                ? Icons.check_circle_rounded
                                : Icons.video_file_rounded,
                            size:  44,
                            color: filePath != null ? accent : Colors.white38,
                          ),
                    const SizedBox(height: 12),
                    Text(
                      isPicking
                          ? 'Opening picker…'
                          : filePath != null
                              ? 'Video selected'
                              : 'Tap to pick a video',
                      style: TextStyle(
                        color:      filePath != null ? accent : AppTheme.textSecondary,
                        fontSize:   14,
                        fontWeight: filePath != null ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (fileName != null) ...const [SizedBox(height: 4)],
                    if (fileName != null)
                      Text(
                        fileName!,
                        maxLines:  1,
                        overflow:  TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      filePath != null ? 'Tap to change' : 'MP4, MKV, MOV supported',
                      style: TextStyle(
                          color:    Colors.white.withOpacity(0.25),
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Info card
            if (filePath == null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:        Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: accent.withOpacity(0.6), size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'The video will be uploaded to sync with friends. '
                        'Once uploaded, all session members will see it play in sync.',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),

            if (filePath != null) ...const [SizedBox(height: 0)] else const SizedBox(height: 8),

            // Public / Category toggles
            _PublicCategorySection(
              accent:            accent,
              isPublic:          isPublic,
              roomCategory:      roomCategory,
              onPublicChanged:   onPublicChanged,
              onCategoryChanged: onCategoryChanged,
              categories:        categories,
            ),
            const SizedBox(height: 14),

            // Watch Together button
            if (filePath != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: state.isLoading ? null : onWatchTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  icon: state.isLoading
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('🎬', style: TextStyle(fontSize: 16)),
                  label: Text(
                    state.isLoading ? 'Creating session…' : 'Watch Together',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),

            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Public / Category section (shared between both tabs)
// ═══════════════════════════════════════════════════════════════

class _PublicCategorySection extends StatelessWidget {
  final Color accent;
  final bool isPublic;
  final String roomCategory;
  final void Function(bool) onPublicChanged;
  final void Function(String) onCategoryChanged;
  final List<(String, String, String)> categories;

  const _PublicCategorySection({
    required this.accent,
    required this.isPublic,
    required this.roomCategory,
    required this.onPublicChanged,
    required this.onCategoryChanged,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Public toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:        Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPublic ? accent.withOpacity(0.4) : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Row(
            children: [
              Text(isPublic ? '🌍' : '🔒', style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Public Room',
                        style: TextStyle(
                            color:      AppTheme.textPrimary,
                            fontSize:   13,
                            fontWeight: FontWeight.w600)),
                    Text(
                      isPublic
                          ? 'Social Hub mein dikhega'
                          : 'Sirf code se join hoga',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value:       isPublic,
                activeColor: accent,
                onChanged:   onPublicChanged,
              ),
            ],
          ),
        ),

        // Category chips (when public)
        if (isPublic) ...const [SizedBox(height: 10)],
        if (isPublic)
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount:       categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat      = categories[i];
                final selected = roomCategory == cat.$1;
                return GestureDetector(
                  onTap: () => onCategoryChanged(cat.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color:        selected
                          ? accent.withOpacity(0.2)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? accent.withOpacity(0.6) : Colors.white12,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cat.$2, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        Text(
                          cat.$3,
                          style: TextStyle(
                            color:      selected ? accent : AppTheme.textSecondary,
                            fontSize:   12,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
