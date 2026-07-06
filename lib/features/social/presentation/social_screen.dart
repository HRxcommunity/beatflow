import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/social_bloc.dart';
// BUG-S02 FIX: was importing the duplicate listening_avatar.dart (byte-for-byte
// identical to listening_avatar_widget.dart). Deleted the duplicate and updated
// this import to the canonical file used by social_hub_screen.dart.
import '../widgets/listening_avatar_widget.dart';
import '../services/social_service.dart';
import '../../together/domain/entities/session_entity.dart';
import '../../together/bloc/together_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';

// BUG-SOCIAL-AUTH FIX (see together_bloc.dart _TogetherAuthRestored):
// Social now uses MultiBlocListener so it auto-initialises the moment
// Firebase restores the anonymous auth session, without needing the user
// to visit the Together tab first.

// ══════════════════════════════════════════════════════════════
//  SOCIAL SCREEN — root
// ══════════════════════════════════════════════════════════════

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSocial());
  }

  void _initSocial() {
    final tb  = context.read<TogetherBloc>().state;
    final uid = tb.uid;
    if (uid == null) {
      // Not signed in yet — trigger anonymous sign-in via TogetherBloc.
      // The BlocListener<TogetherBloc> below will call _initSocial() again
      // once uid becomes non-null (either via authStateChanges restoration
      // or after the sign-in event completes).
      // BUG-NAME FIX: use existing displayName from state if already set
      // (e.g. user typed a custom name on the Together screen) so we don't
      // overwrite it with the hardcoded 'BeatFlow User' fallback.
      if (tb.status != TogetherStatus.loading) {
        final autoName = (tb.displayName != null && tb.displayName!.isNotEmpty)
            ? tb.displayName!
            : 'BeatFlow User';
        context.read<TogetherBloc>().add(TogetherSignIn(autoName));
      }
      return;
    }
    final socialState = context.read<SocialBloc>().state;
    if (socialState.isInitialized) return; // already done, don't re-init
    final name = tb.displayName ?? 'BeatFlow User';
    context.read<SocialBloc>().add(SocialInitialize(uid, name));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return MultiBlocListener(
      listeners: [
        // Social error snackbar
        BlocListener<SocialBloc, SocialState>(
          listenWhen: (p, c) => c.error != null && p.error != c.error,
          listener: (ctx, s) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text(s.error ?? ''),
                backgroundColor: Colors.red.shade800,
                behavior: SnackBarBehavior.floating,
              ),
            );
            ctx.read<SocialBloc>().add(SocialClearError());
          },
        ),
        // BUG-SOCIAL-AUTH FIX: auto-init Social when Together uid arrives
        // (covers both async Firebase auth restoration and first-time sign-in)
        BlocListener<TogetherBloc, TogetherState>(
          listenWhen: (p, c) => p.uid == null && c.uid != null,
          listener: (_, __) {
            final social = context.read<SocialBloc>().state;
            if (!social.isInitialized) _initSocial();
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: AppTheme.bgDeep,
        body: NestedScrollView(
          headerSliverBuilder: (ctx, inner) => [
            SliverAppBar(
              floating: true,
              snap: true,
              pinned: false,
              backgroundColor: AppTheme.bgDeep,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [accent, AppTheme.accentPink]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.people_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Social', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                ],
              ),
              actions: [
                _QrJoinButton(),
                const SizedBox(width: 8),
              ],
              bottom: TabBar(
                controller: _tabCtrl,
                labelColor: accent,
                unselectedLabelColor: AppTheme.textSecondary,
                indicatorColor: accent,
                indicatorWeight: 2.5,
                labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12),
                tabs: const [
                  Tab(icon: Icon(Icons.people_outline_rounded, size: 18), text: 'Friends'),
                  Tab(icon: Icon(Icons.public_rounded, size: 18), text: 'Rooms'),
                  Tab(icon: Icon(Icons.search_rounded, size: 18), text: 'Discover'),
                ],
              ),
            ),
          ],
          body: BlocBuilder<SocialBloc, SocialState>(
            builder: (ctx, state) {
              if (state.isLoading && !state.isInitialized) {
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              if (!state.isInitialized) {
                return _NotSignedInPlaceholder(onRetry: _initSocial);
              }
              return TabBarView(
                controller: _tabCtrl,
                children: [
                  _FriendsTab(state: state),
                  _RoomsTab(state: state),
                  _DiscoverTab(state: state),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  QR JOIN BUTTON
// ══════════════════════════════════════════════════════════════

class _QrJoinButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.qr_code_scanner_rounded),
      tooltip: 'Join with code / QR',
      onPressed: () => _showJoinDialog(context),
    );
  }

  Future<void> _showJoinDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Join a Room', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.accentViolet.withOpacity(0.15), AppTheme.accentCyan.withOpacity(0.1)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.accentViolet.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.qr_code_2_rounded, size: 48, color: AppTheme.textSecondary),
                  const SizedBox(height: 8),
                  Text(
                    'Scan the QR code from a friend\'s screen,\nor enter the 6-digit room code below.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Poppins'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 22, letterSpacing: 8, color: Colors.white,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'XXXXXX',
                hintStyle: TextStyle(color: AppTheme.textSecondary, letterSpacing: 8),
                counterText: '',
                filled: true,
                fillColor: AppTheme.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.accentViolet.withOpacity(0.4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.accentViolet, width: 2),
                ),
              ),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentViolet,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final code = ctrl.text.trim().toUpperCase();
              if (code.length == 6) {
                Navigator.pop(ctx);
                context.push(AppRouter.together, extra: {'joinCode': code});
              }
            },
            child: const Text('Join Room', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  FRIENDS TAB
// ══════════════════════════════════════════════════════════════

class _FriendsTab extends StatelessWidget {
  final SocialState state;
  const _FriendsTab({required this.state});

  @override
  Widget build(BuildContext context) {
    final hasActivity = state.activityFeed.isNotEmpty;
    final hasFriends  = state.friends.isNotEmpty;

    if (!hasFriends && !hasActivity) {
      return _EmptyState(
        icon: Icons.people_outline_rounded,
        title: 'No friends yet',
        subtitle: 'Go to Discover tab to find and follow people',
      );
    }

    return CustomScrollView(
      slivers: [
        // ── Live Now banner ───────────────────────────────────
        if (hasActivity) ...[
          const SliverToBoxAdapter(child: _SectionHeader(title: '🎵 Live Now', subtitle: 'Friends currently listening')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 130,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: state.activityFeed.length,
                itemBuilder: (ctx, i) => _ActivityAvatarCard(activity: state.activityFeed[i]),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          const SliverToBoxAdapter(child: _Divider()),
        ],

        // ── All friends ───────────────────────────────────────
        if (hasFriends) ...[
          const SliverToBoxAdapter(child: _SectionHeader(title: '👥 Following', subtitle: 'People you follow')),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _FriendTile(user: state.friends[i], state: state),
              childCount: state.friends.length,
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

class _ActivityAvatarCard extends StatelessWidget {
  final SocialActivity activity;
  const _ActivityAvatarCard({required this.activity});

  @override
  Widget build(BuildContext context) {
    final color = avatarColorFor(activity.uid);
    return GestureDetector(
      onTap: () {
        if (activity.isInSession && activity.sessionCode != null) {
          context.push(AppRouter.together, extra: {'joinCode': activity.sessionCode});
        }
      },
      child: Container(
        width: 90,
        margin: const EdgeInsets.only(right: 14, top: 8, bottom: 8),
        child: Column(
          children: [
            ListeningAvatar(
              name: activity.displayName,
              color: color,
              size: 56,
              isPlaying: true,
              showBars: true,
            ),
            const SizedBox(height: 6),
            Text(
              activity.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              activity.songTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: color),
            ),
            if (activity.isInSession)
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentViolet.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.accentViolet.withOpacity(0.5), width: 0.5),
                ),
                child: const Text('Together', style: TextStyle(fontFamily: 'Poppins', fontSize: 8, color: AppTheme.accentViolet, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  final SocialUser  user;
  final SocialState state;
  const _FriendTile({required this.user, required this.state});

  @override
  Widget build(BuildContext context) {
    final color    = avatarColorFor(user.uid);
    final isOnline = user.isOnline;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          ListeningAvatar(name: user.displayName, color: color, size: 44, isPlaying: false, showBars: false),
          if (isOnline)
            Positioned(
              right: 0, bottom: 0,
              child: Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.green,
                  border: Border.all(color: AppTheme.bgCard, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(user.displayName, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: Colors.white, fontSize: 14)),
      subtitle: Text(
        '${user.followersCount} followers · ${user.followingCount} following',
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textSecondary),
      ),
      trailing: _FollowButton(user: user, state: state),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  ROOMS TAB
// ══════════════════════════════════════════════════════════════

class _RoomsTab extends StatelessWidget {
  final SocialState state;
  const _RoomsTab({required this.state});

  @override
  Widget build(BuildContext context) {
    final rooms    = state.trendingRooms;
    final trending = rooms.take(3).toList();
    final rest     = rooms.skip(3).toList();

    if (rooms.isEmpty) {
      return _EmptyState(
        icon: Icons.public_rounded,
        title: 'No public rooms',
        subtitle: 'Create a Together session and make it public to appear here',
      );
    }

    return CustomScrollView(
      slivers: [
        // ── Trending ──────────────────────────────────────────
        if (trending.isNotEmpty) ...[
          const SliverToBoxAdapter(child: _SectionHeader(title: '🔥 Trending Rooms', subtitle: 'Most active right now')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 170,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: trending.length,
                itemBuilder: (ctx, i) => _TrendingRoomCard(room: trending[i], rank: i + 1),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: _Divider()),
        ],

        // ── All public rooms ──────────────────────────────────
        if (rest.isNotEmpty) ...[
          const SliverToBoxAdapter(child: _SectionHeader(title: '🌎 All Rooms', subtitle: 'Join a live listening session')),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _PublicRoomTile(room: rest[i]),
              childCount: rest.length,
            ),
          ),
        ] else if (trending.length <= 3 && rooms.isNotEmpty) ...[
          const SliverToBoxAdapter(child: _SectionHeader(title: '🌎 All Rooms', subtitle: 'Join a live listening session')),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _PublicRoomTile(room: trending[i]),
              childCount: trending.length,
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

class _TrendingRoomCard extends StatelessWidget {
  final SessionEntity room;
  final int rank;
  const _TrendingRoomCard({required this.room, required this.rank});

  @override
  Widget build(BuildContext context) {
    final accent = rank == 1
        ? const Color(0xFFF59E0B)
        : rank == 2
            ? const Color(0xFF94A3B8)
            : const Color(0xFFCD7F32);
    final ownerColor = avatarColorFor(room.ownerId);

    return GestureDetector(
      onTap: () => _joinRoom(context, room),
      child: Container(
        width: 190,
        margin: const EdgeInsets.only(right: 14, top: 8, bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [
              ownerColor.withOpacity(0.18),
              AppTheme.bgCard,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ownerColor.withOpacity(0.4), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withOpacity(0.15)),
                  child: Center(
                    child: Text('#$rank', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'Poppins')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    room.ownerName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _MusicNote(color: ownerColor),
            const SizedBox(height: 6),
            Text(
              room.songTitle,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: Colors.white, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              room.songArtist,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: ownerColor),
            ),
            const Spacer(),
            Row(
              children: [
                Icon(Icons.people_rounded, size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${room.memberCount} listening',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppTheme.textSecondary),
                ),
                const Spacer(),
                if (room.isPlaying)
                  Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicRoomTile extends StatelessWidget {
  final SessionEntity room;
  const _PublicRoomTile({required this.room});

  @override
  Widget build(BuildContext context) {
    final color = avatarColorFor(room.ownerId);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [color, color.withOpacity(0.5)]),
        ),
        child: Center(
          child: Text(
            room.ownerName.isNotEmpty ? room.ownerName[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontFamily: 'Poppins', fontSize: 18),
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              room.songTitle.isNotEmpty ? room.songTitle : 'Unknown Song',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13),
            ),
          ),
          if (room.roomCategory.isNotEmpty && room.roomCategory != 'general') ...[
            const SizedBox(width: 6),
            _CountryBadge(country: room.roomCategory),
          ],
        ],
      ),
      subtitle: Text(
        '${room.ownerName} · ${room.memberCount} listener${room.memberCount != 1 ? 's' : ''}',
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textSecondary),
      ),
      trailing: ElevatedButton(
        onPressed: () => _joinRoom(context, room),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.2),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: color.withOpacity(0.5))),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('Join', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _CountryBadge extends StatelessWidget {
  final String country;
  const _CountryBadge({required this.country});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(country, style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppTheme.textSecondary)),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  DISCOVER TAB
// ══════════════════════════════════════════════════════════════

class _DiscoverTab extends StatefulWidget {
  final SocialState state;
  const _DiscoverTab({required this.state});

  @override
  State<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<_DiscoverTab> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) context.read<SocialBloc>().add(SocialSearchUsers(q));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Column(
      children: [
        // ── Search bar ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _ctrl,
            onChanged: _onSearch,
            style: const TextStyle(color: Colors.white, fontFamily: 'Poppins'),
            decoration: InputDecoration(
              hintText: 'Search by username…',
              hintStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Poppins'),
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: AppTheme.textSecondary),
                      onPressed: () {
                        _ctrl.clear();
                        _onSearch('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppTheme.bgSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.7), width: 1.5),
              ),
            ),
          ),
        ),

        // ── Results ────────────────────────────────────────────
        Expanded(
          child: state.searchLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : state.searchResults.isEmpty && _ctrl.text.isNotEmpty
                  ? _EmptyState(
                      icon: Icons.person_search_rounded,
                      title: 'No users found',
                      subtitle: 'Try a different name',
                    )
                  : state.searchResults.isEmpty
                      ? _EmptyState(
                          icon: Icons.manage_search_rounded,
                          title: 'Find BeatFlow users',
                          subtitle: 'Search by their display name',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: state.searchResults.length,
                          itemBuilder: (ctx, i) => _UserSearchTile(
                            user: state.searchResults[i],
                            state: state,
                          ),
                        ),
        ),
      ],
    );
  }
}

class _UserSearchTile extends StatelessWidget {
  final SocialUser  user;
  final SocialState state;
  const _UserSearchTile({required this.user, required this.state});

  @override
  Widget build(BuildContext context) {
    final color = avatarColorFor(user.uid);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [color, color.withOpacity(0.5)]),
        ),
        child: Center(
          child: Text(
            user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontFamily: 'Poppins', fontSize: 18),
          ),
        ),
      ),
      title: Text(
        user.displayName,
        style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: Colors.white, fontSize: 14),
      ),
      subtitle: Text(
        '${user.followersCount} followers',
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textSecondary),
      ),
      trailing: _FollowButton(user: user, state: state),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  SHARED WIDGETS
// ══════════════════════════════════════════════════════════════

class _FollowButton extends StatelessWidget {
  final SocialUser  user;
  final SocialState state;
  const _FollowButton({required this.user, required this.state});

  @override
  Widget build(BuildContext context) {
    final isFollowing = state.isFollowing(user.uid);
    final accent      = Theme.of(context).colorScheme.primary;

    return OutlinedButton(
      onPressed: () {
        if (isFollowing) {
          context.read<SocialBloc>().add(SocialUnfollowUser(user.uid));
        } else {
          context.read<SocialBloc>().add(SocialFollowUser(user.uid, user.displayName));
        }
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: isFollowing ? AppTheme.textSecondary : accent,
        side: BorderSide(color: isFollowing ? Colors.white24 : accent.withOpacity(0.7)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        isFollowing ? 'Following' : 'Follow',
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
          Text(subtitle, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Divider(color: Colors.white10));
}

class _MusicNote extends StatelessWidget {
  final Color color;
  const _MusicNote({required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.music_note_rounded, size: 14, color: color),
        const SizedBox(width: 4),
        Text('Playing', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withOpacity(0.1),
                border: Border.all(color: accent.withOpacity(0.2)),
              ),
              child: Icon(icon, size: 40, color: accent.withOpacity(0.7)),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppTheme.textSecondary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _NotSignedInPlaceholder extends StatelessWidget {
  final VoidCallback onRetry;
  const _NotSignedInPlaceholder({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 48, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          const Text('Sign in to use Social', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 6),
          const Text('Open Together tab to sign in first', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentViolet, foregroundColor: Colors.white),
            child: const Text('Retry', style: TextStyle(fontFamily: 'Poppins')),
          ),
        ],
      ),
    );
  }
}

// ── Helper ────────────────────────────────────────────────────
void _joinRoom(BuildContext context, SessionEntity room) {
  context.push(AppRouter.together, extra: {'joinCode': room.sessionCode});
}
