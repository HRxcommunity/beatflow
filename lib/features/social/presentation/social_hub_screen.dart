import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/social_bloc.dart';
import '../widgets/listening_avatar_widget.dart';
import '../widgets/public_room_card.dart';
import '../../together/bloc/together_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../features/together/domain/entities/session_entity.dart';

class SocialHubScreen extends StatefulWidget {
  const SocialHubScreen({super.key});

  @override
  State<SocialHubScreen> createState() => _SocialHubScreenState();
}

class _SocialHubScreenState extends State<SocialHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _searchCtrl = TextEditingController();
  bool _searchFocused = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tryInitSocial();
  }

  void _tryInitSocial() {
    final togetherState = context.read<TogetherBloc>().state;
    final social        = context.read<SocialBloc>();
    if (togetherState.uid != null &&
        togetherState.displayName != null &&
        !social.state.isInitialized) {
      social.add(SocialInitialize(
        togetherState.uid!,
        togetherState.displayName!,
      ));
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TogetherBloc, TogetherState>(
      builder: (ctx, togetherState) {
        // If not signed in to Together, show sign-in prompt
        if (togetherState.uid == null) {
          return _NotSignedInView(
            onGoToTogether: () => context.push(AppRouter.together),
          );
        }

        return Scaffold(
          backgroundColor: AppTheme.bgDeep,
          body: NestedScrollView(
            headerSliverBuilder: (_, __) => [
              SliverAppBar(
                pinned:          true,
                backgroundColor: AppTheme.bgDeep,
                elevation:       0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white70, size: 20),
                  onPressed: () => context.pop(),
                ),
                title: Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (b) => LinearGradient(
                        colors: [AppTheme.accentViolet, AppTheme.accentCyan],
                      ).createShader(b),
                      child: const Text(
                        '🌐 Social',
                        style: TextStyle(
                          color:      Colors.white,
                          fontSize:   20,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                  ],
                ),
                bottom: TabBar(
                  controller:         _tabs,
                  indicatorColor:     AppTheme.accentViolet,
                  indicatorWeight:    2.5,
                  labelColor:         AppTheme.accentViolet,
                  unselectedLabelColor: Colors.white38,
                  labelStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize:   13,
                  ),
                  tabs: const [
                    Tab(text: '🌍 Discover'),
                    Tab(text: '👥 Friends'),
                    Tab(text: '📻 Activity'),
                  ],
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabs,
              children: [
                _DiscoverTab(onJoinRoom: _onJoinRoom),
                _FriendsTab(searchCtrl: _searchCtrl),
                const _ActivityTab(),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onJoinRoom(String code) {
    context.read<TogetherBloc>().add(TogetherJoinSession(code));
    context.go(AppRouter.together);
  }
}

// ══════════════════════════════════════════════════════════════
//  DISCOVER TAB — Public Rooms
// ══════════════════════════════════════════════════════════════

class _DiscoverTab extends StatelessWidget {
  final void Function(String code) onJoinRoom;
  const _DiscoverTab({required this.onJoinRoom});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SocialBloc, SocialState>(
      builder: (ctx, state) {
        if (state.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
          );
        }

        final rooms = state.trendingRooms;

        if (rooms.isEmpty) {
          return _EmptyState(
            emoji:   '🌍',
            title:   'No Public Rooms Yet',
            message: 'Koi bhi room abhi public nahi hai.\n'
                'Together mein jaake ek public room banao!',
            action:  TextButton(
              onPressed: () => context.push(AppRouter.together),
              child: const Text('Open Together →',
                  style: TextStyle(color: Color(0xFF7C3AED))),
            ),
          );
        }

        return RefreshIndicator(
          color:           AppTheme.accentViolet,
          backgroundColor: AppTheme.bgCard,
          onRefresh: () async {
            // Streams auto-update; just give visual feedback
            await Future.delayed(const Duration(milliseconds: 600));
          },
          child: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              // Section header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    const Text('🔥 ', style: TextStyle(fontSize: 16)),
                    Text(
                      'Trending Rooms',
                      style: TextStyle(
                        color:      AppTheme.textPrimary,
                        fontSize:   15,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${rooms.length} live',
                      style: TextStyle(
                        color:    AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // Room cards
              ...rooms.asMap().entries.map((e) => PublicRoomCard(
                    key:         ValueKey(e.value.sessionId),
                    session:     e.value,
                    isTrending:  e.key < 3,
                    onJoin:      () => onJoinRoom(e.value.sessionCode),
                  )),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  FRIENDS TAB — Follow / Unfollow users
// ══════════════════════════════════════════════════════════════

class _FriendsTab extends StatefulWidget {
  final TextEditingController searchCtrl;
  const _FriendsTab({required this.searchCtrl});

  @override
  State<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<_FriendsTab> {
  bool _showSearch = false;
  // Owned FocusNode so we can programmatically unfocus on close —
  // prevents the keyboard from staying up after the TextField is removed.
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _showSearch = true);
    // Delay by one frame so the TextField is in the tree before requesting focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    // Dismiss keyboard BEFORE removing the TextField from the tree.
    // Calling unfocus() after removing it leaves the keyboard hanging.
    _searchFocus.unfocus();
    widget.searchCtrl.clear();
    context.read<SocialBloc>().add(const SocialSearchUsers(''));
    setState(() => _showSearch = false);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SocialBloc, SocialState>(
      builder: (ctx, state) {
        return Column(
          children: [
            // ── Search bar ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AnimatedContainer(
                duration:    const Duration(milliseconds: 200),
                height:      46,
                decoration:  BoxDecoration(
                  color:        AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border:       Border.all(
                    color: _showSearch
                        ? AppTheme.accentViolet.withValues(alpha: 0.6)
                        : Colors.white12,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded,
                        color: AppTheme.textSecondary, size: 18),
                    const SizedBox(width: 8),

                    // FIX: conditional rendering — TextField only exists in
                    // the widget tree when _showSearch is true.
                    //
                    // OLD BUG: TextField was always present with autofocus:false.
                    // Flutter's focus system still let the TextField grab focus
                    // on any nearby scroll/tap event → random keyboard pops.
                    //
                    // NEW: when _showSearch=false → static GestureDetector (no
                    //      keyboard risk at all, zero focus surface).
                    //      when _showSearch=true  → real TextField with a
                    //      dedicated FocusNode; _closeSearch() calls unfocus()
                    //      BEFORE removing the widget so keyboard dismisses cleanly.
                    Expanded(
                      child: _showSearch
                          ? TextField(
                              controller: widget.searchCtrl,
                              focusNode:  _searchFocus,
                              autofocus:  false, // focus managed via _searchFocus.requestFocus()
                              style: const TextStyle(
                                  color: Colors.white, fontFamily: 'Poppins'),
                              decoration: InputDecoration(
                                hintText:  'User dhundo...',
                                hintStyle: TextStyle(
                                    color: AppTheme.textSecondary, fontSize: 13),
                                border:  InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: (q) {
                                context.read<SocialBloc>()
                                    .add(SocialSearchUsers(q));
                              },
                            )
                          // Tappable placeholder — visually identical to the
                          // TextField hint but is not a focusable input widget.
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _openSearch,
                              child: Text(
                                'User dhundo...',
                                style: TextStyle(
                                    color: AppTheme.textSecondary, fontSize: 13),
                              ),
                            ),
                    ),

                    // Close button — only when search is active
                    if (_showSearch)
                      GestureDetector(
                        onTap: _closeSearch,
                        child: Icon(Icons.close_rounded,
                            color: AppTheme.textSecondary, size: 18),
                      ),
                  ],
                ),
              ),
            ),

            // ── Content ───────────────────────────────────────────
            Expanded(
              child: _showSearch && widget.searchCtrl.text.isNotEmpty
                  ? _SearchResults(state: state)
                  : _FriendsList(friends: state.friends, state: state),
            ),
          ],
        );
      },
    );
  }
}

class _SearchResults extends StatelessWidget {
  final SocialState state;
  const _SearchResults({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.searchLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
      );
    }
    if (state.searchResults.isEmpty) {
      return const _EmptyState(
        emoji:   '🔍',
        title:   'Koi nahi mila',
        message: 'Username se try karo',
      );
    }
    return ListView.separated(
      padding:    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount:  state.searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final user = state.searchResults[i];
        return _UserTile(user: user, state: state);
      },
    );
  }
}

class _FriendsList extends StatelessWidget {
  final List<dynamic> friends;
  final SocialState   state;
  const _FriendsList({required this.friends, required this.state});

  @override
  Widget build(BuildContext context) {
    if (friends.isEmpty) {
      return _EmptyState(
        emoji:   '👥',
        title:   'Koi friend nahi abhi',
        message: 'Upar search karo aur users ko follow karo!',
        action:  null,
      );
    }
    return ListView.separated(
      padding:    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount:  friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final user = friends[i];
        return _UserTile(user: user, state: state);
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  final dynamic     user;  // SocialUser
  final SocialState state;
  const _UserTile({required this.user, required this.state});

  @override
  Widget build(BuildContext context) {
    final isFollowing = state.isFollowing(user.uid as String);
    final color       = avatarColorFor(user.uid as String);

    return Container(
      padding:    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          ListeningAvatar(
            name:      user.displayName as String,
            color:     color,
            size:      42,
            isPlaying: false,
            showBars:  false,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName as String,
                  style: const TextStyle(
                    color:      Colors.white,
                    fontSize:   14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '${user.followersCount} followers',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                    ),
                    Text(
                      '  •  ${user.followingCount} following',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Follow / Unfollow button
          GestureDetector(
            onTap: () {
              final bloc = context.read<SocialBloc>();
              if (isFollowing) {
                bloc.add(SocialUnfollowUser(user.uid as String));
              } else {
                bloc.add(SocialFollowUser(
                    user.uid as String, user.displayName as String));
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: isFollowing
                    ? Colors.white.withValues(alpha: 0.08)
                    : AppTheme.accentViolet,
                border: isFollowing
                    ? Border.all(color: Colors.white24)
                    : null,
              ),
              child: Text(
                isFollowing ? 'Following ✓' : 'Follow',
                style: TextStyle(
                  color:      isFollowing ? Colors.white60 : Colors.white,
                  fontSize:   12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  ACTIVITY TAB — Listening feed
// ══════════════════════════════════════════════════════════════

class _ActivityTab extends StatelessWidget {
  const _ActivityTab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SocialBloc, SocialState>(
      builder: (ctx, state) {
        if (state.activityFeed.isEmpty) {
          return const _EmptyState(
            emoji:   '📻',
            title:   'Abhi kuch nahi chal raha',
            message: 'Jab tumhare friends music sunenge,\nyahan dikhega!',
          );
        }

        return ListView.separated(
          padding:    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount:  state.activityFeed.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final act   = state.activityFeed[i];
            final color = avatarColorFor(act.uid as String);
            final age   = DateTime.now().difference(act.updatedAt as DateTime);
            final timeLabel = age.inMinutes < 1
                ? 'abhi'
                : age.inMinutes < 60
                    ? '${age.inMinutes}m ago'
                    : '${age.inHours}h ago';

            return Container(
              padding:    const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:        AppTheme.bgCard,
                borderRadius: BorderRadius.circular(14),
                border:       Border.all(
                    color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  ListeningAvatar(
                    name:      act.displayName as String,
                    color:     color,
                    size:      46,
                    isPlaying: true,
                    showBars:  true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          act.displayName as String,
                          style: const TextStyle(
                            color:      Colors.white,
                            fontSize:   13,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        Text(
                          '🎵 ${act.songTitle}',
                          style: TextStyle(
                              color: AppTheme.textPrimary, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          (act.songArtist as String).isNotEmpty
                              ? act.songArtist as String
                              : 'Unknown Artist',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timeLabel,
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 10),
                      ),
                      const SizedBox(height: 4),
                      if (act.isInSession as bool && act.sessionCode != null)
                        GestureDetector(
                          onTap: () {
                            context.read<TogetherBloc>()
                                .add(TogetherJoinSession(act.sessionCode as String));
                            context.go(AppRouter.together);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color:        AppTheme.accentViolet.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border:       Border.all(
                                  color: AppTheme.accentViolet.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              '🎧 Join',
                              style: TextStyle(
                                color:      AppTheme.accentViolet,
                                fontSize:   10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  HELPERS
// ══════════════════════════════════════════════════════════════

class _NotSignedInView extends StatelessWidget {
  final VoidCallback onGoToTogether;
  const _NotSignedInView({required this.onGoToTogether});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDeep,
        elevation:       0,
        leading:         IconButton(
          icon:      const Icon(Icons.arrow_back_ios_rounded,
              color: Colors.white70, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('🌐 Social',
            style: TextStyle(
                color:      Colors.white,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🌐', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              const Text(
                'Social ke liye\nBeatFlow Together join karo!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:      Colors.white,
                  fontSize:   18,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Pehle Together mein ek naam set karo,\nphir social features use kar sakte ho.',
                textAlign: TextAlign.center,
                style:     TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed:  onGoToTogether,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentViolet,
                  padding:    const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Open Together →',
                    style: TextStyle(
                        color:      Colors.white,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String    emoji;
  final String    title;
  final String    message;
  final Widget?   action;

  const _EmptyState({
    required this.emoji,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color:      AppTheme.textPrimary,
                fontSize:   16,
                fontWeight: FontWeight.w700,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style:     TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
