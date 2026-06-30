import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../songs/library_bloc.dart';
import '../player/player_bloc.dart';
import '../settings/settings_bloc.dart';
import '../../domain/entities/song_entity.dart';
import '../../domain/entities/playlist_entity.dart';
import '../../domain/entities/player_state_entity.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common/mini_player.dart';
import '../../widgets/common/song_tile.dart';
import '../../widgets/common/song_artwork_widget.dart';
import '../../features/together/presentation/together_session_badge.dart';
import '../../features/together/bloc/together_bloc.dart';
import '../../features/browser/hrx_browse_home_card.dart';
// OTA Update
import '../../services/update_service.dart';
import '../../features/update/update_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;

  // Per-tab fade controllers — only the ACTIVE tab fades in.
  // FadeTransition on IndexedStack composites ALL 5 hidden layers simultaneously
  // during the animation, causing ghost/triple-rendering artifacts on screen.
  late final List<AnimationController> _tabCtrls;
  late final List<Animation<double>> _tabFades;

  @override
  void initState() {
    super.initState();
    _tabCtrls = List.generate(
      5,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 220),
        value: i == 0 ? 1.0 : 0.0, // first tab starts fully visible
      ),
    );
    _tabFades = _tabCtrls
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOut))
        .toList();
    context.read<LibraryBloc>().add(LibraryLoad());

    // ── OTA Update check — 4 sec delay taaki splash settle ho jaye ──────
    Future.delayed(const Duration(seconds: 4), _checkForUpdate);
  }

  /// Silent background update check — dialog tabhi show hoga jab update ho.
  Future<void> _checkForUpdate() async {
    if (!mounted) return;
    try {
      final info = await UpdateService.instance.checkForUpdate();
      if (!mounted) return;
      if (info != null && info.hasUpdate) {
        showUpdateDialog(context, info);
      }
    } catch (_) {
      // Network nahi hai — koi baat nahi, silently ignore
    }
  }

  @override
  void dispose() {
    for (final c in _tabCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTab(int i) {
    if (_currentIndex == i) return;
    // Fade out current tab, then switch index and fade in new tab
    _tabCtrls[_currentIndex].reverse().then((_) {
      if (!mounted) return;
      setState(() => _currentIndex = i);
      _tabCtrls[i].forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasBg = context.select<SettingsBloc, bool>(
      (b) => b.state.backgroundType == 1 && (b.state.backgroundImagePath?.isNotEmpty ?? false),
    );
    // Use Offstage + TickerMode so each tab maintains its state while hidden,
    // but only the active tab is actually rendered/animated by the GPU.
    return Scaffold(
      backgroundColor: hasBg ? Colors.transparent : AppTheme.bgDeep,
      body: Stack(
        children: List.generate(5, (i) {
          final tabs = const [
            _HomeTab(),
            _SongsTab(),
            _AlbumsTab(),
            _ArtistsTab(),
            _PlaylistsTab(),
          ];
          return Offstage(
            offstage: _currentIndex != i,
            child: TickerMode(
              enabled: _currentIndex == i,
              child: FadeTransition(
                opacity: _tabFades[i],
                child: tabs[i],
              ),
            ),
          );
        }),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          _PremiumNavBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onTab,
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 1
          ? FloatingActionButton(
              onPressed: () => context.push(AppRouter.search),
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.search_rounded, color: Colors.white),
            )
          : _currentIndex == 0
              ? const TogetherSessionBadge()
              : null,
    );
  }
}

// ── Premium nav bar ──
class _PremiumNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _PremiumNavBar({required this.selectedIndex, required this.onDestinationSelected});

  static const _items = [
    (Icons.home_rounded, Icons.home_outlined, 'Home'),
    (Icons.music_note_rounded, Icons.music_note_outlined, 'Songs'),
    (Icons.album_rounded, Icons.album_outlined, 'Albums'),
    (Icons.person_rounded, Icons.person_outline_rounded, 'Artists'),
    (Icons.queue_music_rounded, Icons.queue_music_outlined, 'Playlists'),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final hasBg = context.select<SettingsBloc, bool>(
      (b) => b.state.backgroundType == 1 && (b.state.backgroundImagePath?.isNotEmpty ?? false),
    );
    // bottomPadding = system nav bar height (48dp on 3-button, 0 on gesture nav)
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      // 70dp for our buttons + system nav bar height below them
      height: 70 + bottomPadding,
      decoration: BoxDecoration(
        color: hasBg ? AppTheme.bgCard.withOpacity(0.75) : AppTheme.bgCard,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06), width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        // Push buttons UP so they sit in the 70dp zone, not under the nav bar
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_items.length, (i) {
          final (active, inactive, label) = _items[i];
          final isSelected = i == selectedIndex;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onDestinationSelected(i),
            child: SizedBox(
              width: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? accent.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isSelected ? active : inactive,
                      color: isSelected ? accent : AppTheme.textSecondary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? accent : AppTheme.textSecondary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        ),
      ),
    );
  }
}

// ── Home tab ──
class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final hasBg = context.select<SettingsBloc, bool>(
      (b) => b.state.backgroundType == 1 && (b.state.backgroundImagePath?.isNotEmpty ?? false),
    );
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: hasBg ? Colors.transparent : AppTheme.bgDeep,
          floating: true,
          snap: true,
          elevation: 0,
          title: RichText(
            text: TextSpan(
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 24, fontWeight: FontWeight.w800),
              children: [
                const TextSpan(text: 'Beat', style: TextStyle(color: Colors.white)),
                TextSpan(
                  text: 'Flow',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            // ── AI Vocab Chat button ──
            Container(
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    Theme.of(context).colorScheme.primary.withOpacity(0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.push(AppRouter.aiVocab),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 15,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Vocab AI',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // ── Study AI button ──
            Container(
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.accentCyan.withOpacity(0.2),
                    AppTheme.accentCyan.withOpacity(0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.accentCyan.withOpacity(0.4),
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.push(AppRouter.studyAi),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.school_rounded,
                        size: 15,
                        color: AppTheme.accentCyan,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Study AI',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accentCyan,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // ── Settings button ──
            Container(
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 20),
                onPressed: () => context.push(AppRouter.settings),
              ),
            ),
          ],
        ),
        BlocBuilder<LibraryBloc, LibraryState>(
          builder: (context, state) {
            if (state.status == LibraryStatus.loading || state.status == LibraryStatus.initial) {
              return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
            }
            if (state.status == LibraryStatus.scanning) {
              return SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      if (state.scanProgress != null)
                        Text(
                          'Scanning ${state.scanProgress!.scanned}/${state.scanProgress!.total}',
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                ),
              );
            }
            return SliverList(
              delegate: SliverChildListDelegate([
                const _TogetherHomeCard(),
                const HRxBrowseHomeCard(),
                if (state.recentlyPlayed.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Recently Played',
                    onRescan: () => context.read<LibraryBloc>().add(LibraryRescan()),
                  ),
                  _PremiumHorizontalList(songs: state.recentlyPlayed),
                ],
                if (state.mostPlayed.isNotEmpty) ...[
                  const _SectionHeader(title: 'Most Played'),
                  _PremiumHorizontalList(songs: state.mostPlayed),
                ],
                if (state.allSongs.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.music_off_rounded, size: 56, color: Colors.white24),
                          ),
                          const SizedBox(height: 20),
                          const Text('No music found', style: TextStyle(color: AppTheme.textSecondary)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => context.read<LibraryBloc>().add(LibraryRescan()),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Scan Library'),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
              ]),
            );
          },
        ),
      ],
    );
  }
}

// ── BeatFlow Together home card ──
class _TogetherHomeCard extends StatelessWidget {
  const _TogetherHomeCard();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return BlocBuilder<TogetherBloc, TogetherState>(
      buildWhen: (prev, curr) => prev.isInSession != curr.isInSession,
      builder: (context, togetherState) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: GestureDetector(
            onTap: () => context.push(AppRouter.together),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: togetherState.isInSession
                      ? [
                          const Color(0xFF22C55E).withOpacity(0.20),
                          accent.withOpacity(0.10),
                        ]
                      : [
                          accent.withOpacity(0.15),
                          AppTheme.accentCyan.withOpacity(0.08),
                        ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: togetherState.isInSession
                      ? const Color(0xFF22C55E).withOpacity(0.40)
                      : accent.withOpacity(0.25),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [
                        accent.withOpacity(0.4),
                        AppTheme.accentCyan.withOpacity(0.25),
                      ]),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          togetherState.isInSession
                              ? 'Session Active ❤️'
                              : 'BeatFlow Together ❤️',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          togetherState.isInSession
                              ? '${togetherState.session?.memberCount ?? 0} listening · Tap to view'
                              : 'Listen with friends in real time',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: accent.withOpacity(0.6),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onRescan;

  const _SectionHeader({required this.title, this.onRescan});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 16, 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: 0.1,
            ),
          ),
          const Spacer(),
          if (onRescan != null)
            GestureDetector(
              onTap: onRescan,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.refresh_rounded, size: 16, color: AppTheme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _PremiumHorizontalList extends StatelessWidget {
  final List<SongEntity> songs;

  const _PremiumHorizontalList({required this.songs});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 175,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: songs.take(10).length,
        itemBuilder: (context, i) {
          final song = songs[i];
          return GestureDetector(
            onTap: () {
              final pb = context.read<PlayerBloc>();
              final isCurrentSong = pb.state.currentSong?.id == song.id;
              if (isCurrentSong) {
                if (pb.state.isPlaying) {
                  pb.add(PlayerPause());
                } else {
                  pb.add(PlayerResume());
                }
              } else {
                pb.add(PlayerPlay(queue: songs, index: i));
              }
            },
            child: Container(
              width: 130,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent.withOpacity(0.2),
                          AppTheme.bgSurface,
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.07),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(0.1),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SongArtworkWidget(songId: song.id, size: 130, borderRadius: 16),
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withOpacity(0.85),
                            ),
                            child: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    song.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    song.artist,
                    style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Songs Tab ──
class _SongsTab extends StatelessWidget {
  const _SongsTab();

  @override
  Widget build(BuildContext context) {
    final hasBg = context.select<SettingsBloc, bool>(
      (b) => b.state.backgroundType == 1 && (b.state.backgroundImagePath?.isNotEmpty ?? false),
    );
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, state) {
        return BlocBuilder<PlayerBloc, PlayerStateEntity>(
          buildWhen: (prev, curr) =>
              prev.currentSong?.id != curr.currentSong?.id ||
              prev.isPlaying != curr.isPlaying,
          builder: (context, playerState) {
            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: hasBg ? Colors.transparent : AppTheme.bgDeep,
                  title: const Text('Songs'),
                  floating: true,
                  snap: true,
                  elevation: 0,
                ),
                if (state.status == LibraryStatus.loading)
                  const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final song = state.filteredSongs[i];
                        final isCurrentSong = playerState.currentSong?.id == song.id;
                        return SongTile(
                          song: song,
                          isPlaying: isCurrentSong,
                          onTap: () {
                            final pb = ctx.read<PlayerBloc>();
                            if (isCurrentSong) {
                              if (pb.state.isPlaying) {
                                pb.add(PlayerPause());
                              } else {
                                pb.add(PlayerResume());
                              }
                            } else {
                              pb.add(PlayerPlay(queue: state.filteredSongs, index: i));
                            }
                          },
                        );
                      },
                      childCount: state.filteredSongs.length,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

// ── Albums Tab ──
class _AlbumsTab extends StatelessWidget {
  const _AlbumsTab();

  @override
  Widget build(BuildContext context) {
    final hasBg = context.select<SettingsBloc, bool>(
      (b) => b.state.backgroundType == 1 && (b.state.backgroundImagePath?.isNotEmpty ?? false),
    );
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, state) {
        final albums = state.albums.entries.toList();
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: hasBg ? Colors.transparent : AppTheme.bgDeep,
              title: const Text('Albums'),
              floating: true,
              snap: true,
              elevation: 0,
            ),
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  // FIX: context.select must NOT be called inside SliverChildBuilderDelegate
                  // directly — doing so triggers a Provider assertion crash because the
                  // callback context is a SliverWithKeepAliveWidget context.
                  // Solution: extract each item to its own widget (_AlbumCard), which has
                  // its own BuildContext where context.select is safe.
                  (ctx, i) => _AlbumCard(
                    name:  albums[i].key,
                    songs: albums[i].value,
                  ),
                  childCount: albums.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.88,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Extracted widget — owns its own BuildContext so context.select is safe.
class _AlbumCard extends StatelessWidget {
  final String name;
  final List<SongEntity> songs;
  const _AlbumCard({required this.name, required this.songs});

  @override
  Widget build(BuildContext context) {
    final accent         = Theme.of(context).colorScheme.primary;
    final cardOpacity    = context.select<SettingsBloc, double>((b) => b.state.songCardOpacity);
    final cardColorIndex = context.select<SettingsBloc, int>((b) => b.state.songCardColorIndex);
    final Color baseColor;
    switch (cardColorIndex) {
      case 1:  baseColor = accent;        break;
      case 2:  baseColor = Colors.white;  break;
      case 3:  baseColor = Colors.black;  break;
      default: baseColor = AppTheme.bgCard;
    }
    return GestureDetector(
      onTap: () => context.push(
        '${AppRouter.album}/${Uri.encodeComponent(name)}',
        extra: songs,
      ),
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color:         baseColor.withOpacity(cardOpacity),
          borderRadius:  BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(cardOpacity * 0.07),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 70, height: 70,
              decoration: BoxDecoration(
                shape:    BoxShape.circle,
                gradient: RadialGradient(colors: [
                  accent.withOpacity(0.25),
                  AppTheme.bgSurface,
                ]),
              ),
              child: Icon(Icons.album_rounded, size: 38, color: accent.withOpacity(0.6)),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                name,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Text(
              '${songs.length} songs',
              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Artists Tab ──
class _ArtistsTab extends StatelessWidget {
  const _ArtistsTab();

  @override
  Widget build(BuildContext context) {
    final hasBg = context.select<SettingsBloc, bool>(
      (b) => b.state.backgroundType == 1 && (b.state.backgroundImagePath?.isNotEmpty ?? false),
    );
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, state) {
        final artists = state.artists.entries.toList();
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: hasBg ? Colors.transparent : AppTheme.bgDeep,
              title: const Text('Artists'),
              floating: true,
              snap: true,
              elevation: 0,
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                // FIX: context.select inside SliverChildBuilderDelegate → Provider crash.
                // Extracted to _ArtistTile which has its own safe BuildContext.
                (ctx, i) => _ArtistTile(
                  name:  artists[i].key,
                  songs: artists[i].value,
                ),
                childCount: artists.length,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Extracted widget — owns its own BuildContext so context.select is safe.
class _ArtistTile extends StatelessWidget {
  final String name;
  final List<SongEntity> songs;
  const _ArtistTile({required this.name, required this.songs});

  @override
  Widget build(BuildContext context) {
    final accent         = Theme.of(context).colorScheme.primary;
    final cardOpacity    = context.select<SettingsBloc, double>((b) => b.state.songCardOpacity);
    final cardColorIndex = context.select<SettingsBloc, int>((b) => b.state.songCardColorIndex);
    final Color baseColor;
    switch (cardColorIndex) {
      case 1:  baseColor = accent;        break;
      case 2:  baseColor = Colors.white;  break;
      case 3:  baseColor = Colors.black;  break;
      default: baseColor = AppTheme.bgCard;
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color:        baseColor.withOpacity(cardOpacity),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(cardOpacity * 0.06)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [accent.withOpacity(0.3), AppTheme.bgSurface],
            ),
          ),
          child: Icon(Icons.person_rounded, color: accent.withOpacity(0.8), size: 22),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        subtitle: Text(
          '${songs.length} songs',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: AppTheme.textSecondary.withOpacity(0.5),
        ),
        onTap: () => context.push('${AppRouter.artist}/${Uri.encodeComponent(name)}'),
      ),
    );
  }
}

// ── Playlists Tab ──
class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final hasBg = context.select<SettingsBloc, bool>(
      (b) => b.state.backgroundType == 1 && (b.state.backgroundImagePath?.isNotEmpty ?? false),
    );
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, state) {
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: hasBg ? Colors.transparent : AppTheme.bgDeep,
              title: const Text('Playlists'),
              floating: true,
              snap: true,
              elevation: 0,
              actions: [
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.add_rounded, color: accent, size: 22),
                    onPressed: () => _showCreateDialog(context),
                  ),
                ),
              ],
            ),
            if (state.playlists.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.queue_music_rounded, size: 48, color: accent.withOpacity(0.4)),
                      ),
                      const SizedBox(height: 16),
                      const Text('No playlists yet',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
                      const SizedBox(height: 8),
                      const Text('Tap + to create one',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  // FIX: context.select inside SliverChildBuilderDelegate → Provider crash.
                  // Extracted to _PlaylistTile which has its own safe BuildContext.
                  (ctx, i) => _PlaylistTile(playlist: state.playlists[i]),
                  childCount: state.playlists.length,
                ),
              ),
          ],
        );
      },
    );
  }

  void _showCreateDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New Playlist', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                context.read<LibraryBloc>().add(LibraryCreatePlaylist(ctrl.text.trim()));
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// Extracted widget — owns its own BuildContext so context.select is safe.
/// Replaces the inlined item builder that caused the Provider assertion:
/// "Tried to use context.select inside a SliverList/SliderGridView."
class _PlaylistTile extends StatelessWidget {
  final PlaylistEntity playlist;
  const _PlaylistTile({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final accent         = Theme.of(context).colorScheme.primary;
    final cardOpacity    = context.select<SettingsBloc, double>((b) => b.state.songCardOpacity);
    final cardColorIndex = context.select<SettingsBloc, int>((b) => b.state.songCardColorIndex);
    final Color baseColor;
    switch (cardColorIndex) {
      case 1:  baseColor = accent;        break;
      case 2:  baseColor = Colors.white;  break;
      case 3:  baseColor = Colors.black;  break;
      default: baseColor = AppTheme.bgCard;
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color:        baseColor.withOpacity(cardOpacity),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(cardOpacity * 0.06)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              colors: [accent.withOpacity(0.3), AppTheme.bgSurface],
            ),
          ),
          child: Icon(Icons.queue_music_rounded, color: accent.withOpacity(0.8)),
        ),
        title: Text(
          playlist.name,
          style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        subtitle: Text(
          '${playlist.songIds.length} songs',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        onTap: () => context.push('${AppRouter.playlist}/${playlist.id}'),
        trailing: playlist.type == PlaylistType.user
            ? IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
                onPressed: () => context
                    .read<LibraryBloc>()
                    .add(LibraryDeletePlaylist(playlist.id)),
              )
            : null,
      ),
    );
  }
}
