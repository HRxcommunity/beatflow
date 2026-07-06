// lib/features/vocab/ai_vocab_chat_history_screen.dart
// FIX: **bold** markers no longer show literally in session preview
//      Uses MarkdownUtils.stripForPreview() before rendering preview text
//      Layout cleaned up with proper tab styling

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../utils/markdown_utils.dart';

// ─── Models (adjust field names to match your actual Hive models) ─────────────

class VocabChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final int messageCount;
  final String lastMessage; // raw (may contain **markdown**)
  final List<Map<String, String>> messages;

  const VocabChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.messageCount,
    required this.lastMessage,
    required this.messages,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class AiVocabChatHistoryScreen extends StatefulWidget {
  const AiVocabChatHistoryScreen({super.key});

  @override
  State<AiVocabChatHistoryScreen> createState() => _AiVocabChatHistoryScreenState();
}

class _AiVocabChatHistoryScreenState extends State<AiVocabChatHistoryScreen>
    with SingleTickerProviderStateMixin {

  late final TabController _tabCtrl;
  late final TextEditingController _searchCtrl;

  List<VocabChatSession> _sessions = [];
  List<VocabChatSession> _filtered = [];
  String _query = '';

  // Stats
  int get _totalMessages => _sessions.fold(0, (s, e) => s + e.messageCount);
  int get _todayCount => _sessions
      .where((s) {
        final now = DateTime.now();
        return s.createdAt.year == now.year &&
            s.createdAt.month == now.month &&
            s.createdAt.day == now.day;
      })
      .length;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _searchCtrl = TextEditingController();
    _loadSessions();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data Loading ──────────────────────────────────────────────────────────

  Future<void> _loadSessions() async {
    try {
      final box = await Hive.openBox('vocab_chat_sessions');
      final raw = box.values.toList();

      final sessions = raw.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final msgs = (m['messages'] as List? ?? [])
            .map((msg) => Map<String, String>.from(msg as Map))
            .toList();

        final lastMsg = msgs.isNotEmpty
            ? (msgs.last['content'] ?? '')
            : '';

        return VocabChatSession(
          id: m['id'] as String? ?? '',
          title: m['title'] as String? ?? 'Vocab Chat',
          createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ??
              DateTime.now(),
          messageCount: msgs.length,
          lastMessage: lastMsg,
          messages: msgs,
        );
      }).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          _sessions = sessions;
          _applyFilter();
        });
      }
    } catch (e) {
      debugPrint('VocabChatHistory load error: $e');
    }
  }

  void _applyFilter() {
    if (_query.isEmpty) {
      _filtered = List.of(_sessions);
    } else {
      final q = _query.toLowerCase();
      _filtered = _sessions.where((s) {
        return s.title.toLowerCase().contains(q) ||
            MarkdownUtils.stripForPreview(s.lastMessage).toLowerCase().contains(q);
      }).toList();
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Sab clear karo?',
            style: TextStyle(color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text('Saari chat history delete ho jayegi.',
            style: TextStyle(color: Colors.white60, fontFamily: 'Poppins')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok == true) {
      final box = await Hive.openBox('vocab_chat_sessions');
      await box.clear();
      await _loadSessions();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDeep,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Chat History',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_sessions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Stats Row ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _StatChip(icon: Icons.chat_bubble_outline_rounded, label: '${_sessions.length}', sub: 'Sessions'),
                const SizedBox(width: 12),
                _StatChip(icon: Icons.today_rounded, label: '$_todayCount', sub: 'Today'),
                const SizedBox(width: 12),
                _StatChip(icon: Icons.message_rounded, label: '$_totalMessages', sub: 'Messages'),
                const SizedBox(width: 12),
                _StatChip(icon: Icons.bookmark_outline_rounded, label: '0', sub: 'Bookmarks'),
              ],
            ),
          ),

          // ── Search Bar ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white, fontFamily: 'Poppins', fontSize: 14),
              onChanged: (v) => setState(() {
                _query = v;
                _applyFilter();
              }),
              decoration: InputDecoration(
                hintText: 'Search sessions ya words...',
                hintStyle: const TextStyle(color: Colors.white38, fontFamily: 'Poppins', fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 18),
                        onPressed: () => setState(() {
                          _searchCtrl.clear();
                          _query = '';
                          _applyFilter();
                        }),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // ── Tab Bar ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(30),
              ),
              child: TabBar(
                controller: _tabCtrl,
                indicator: BoxDecoration(
                  color: AppTheme.accentViolet,
                  borderRadius: BorderRadius.circular(30),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12),
                unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                tabs: [
                  Tab(text: '🕐 Sessions (${_sessions.length})'),
                  const Tab(text: '🔖 Bookmarks'),
                  const Tab(text: '🔔 Notifs'),
                ],
              ),
            ),
          ),

          // ── Tab Views ────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _SessionsTab(sessions: _filtered, onTap: _openSession),
                _EmptyTab(icon: '🔖', label: 'No bookmarks yet'),
                _EmptyTab(icon: '🔔', label: 'No saved notifications'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openSession(VocabChatSession session) {
    // Navigate to AI vocab chat with existing session
    // Navigator.pushNamed(context, '/vocab-chat', arguments: session);
    debugPrint('Open session: ${session.id}');
  }
}

// ─── Sessions Tab ─────────────────────────────────────────────────────────────

class _SessionsTab extends StatelessWidget {
  final List<VocabChatSession> sessions;
  final ValueChanged<VocabChatSession> onTap;

  const _SessionsTab({required this.sessions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const _EmptyTab(icon: '💬', label: 'Koi session nahi\nVocab AI se baat karo!');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: sessions.length,
      itemBuilder: (ctx, i) => _SessionCard(
        session: sessions[i],
        onTap: () => onTap(sessions[i]),
      ),
    );
  }
}

// ─── Session Card (FIX: markdown stripped from preview) ───────────────────────

class _SessionCard extends StatelessWidget {
  final VocabChatSession session;
  final VoidCallback onTap;

  const _SessionCard({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = now.difference(session.createdAt);

    String timeLabel;
    if (diff.inMinutes < 1) {
      timeLabel = 'just now';
    } else if (diff.inMinutes < 60) {
      timeLabel = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      timeLabel = '${diff.inHours}h ago';
    } else {
      timeLabel = DateFormat('dd MMM').format(session.createdAt);
    }

    // FIX: Strip markdown before showing in preview
    final cleanPreview = MarkdownUtils.stripForPreview(session.lastMessage, maxLength: 100);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.accentViolet.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: AppTheme.accentViolet, size: 20),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + time
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${session.messageCount} msgs',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontFamily: 'Poppins',
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),

                  Text(
                    timeLabel,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontFamily: 'Poppins',
                      fontSize: 11,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // FIX: cleanPreview — no **markers** shown
                  Text(
                    cleanPreview.isEmpty ? 'Conversation...' : cleanPreview,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 8),

                  Row(
                    children: const [
                      Icon(Icons.play_circle_outline_rounded, color: Colors.white38, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Tap to resume',
                        style: TextStyle(
                          color: Colors.white38,
                          fontFamily: 'Poppins',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stat Chip ────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;

  const _StatChip({required this.icon, required this.label, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white60, size: 18),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            Text(
              sub,
              style: const TextStyle(
                color: Colors.white38,
                fontFamily: 'Poppins',
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty Tab ────────────────────────────────────────────────────────────────

class _EmptyTab extends StatelessWidget {
  final String icon;
  final String label;

  const _EmptyTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white38,
              fontFamily: 'Poppins',
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
