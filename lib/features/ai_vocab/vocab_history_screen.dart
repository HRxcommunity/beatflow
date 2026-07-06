// ╔══════════════════════════════════════════════════════════════╗
// ║  Vocab Chat History Screen                                   ║
// ║  Browse, search & resume past chat sessions                  ║
// ║  CHANGE-3: Added "🔔 Notif History" tab (3rd tab)           ║
// ║            _NotifQuizScreen for delivered notifications quiz ║
// ╚══════════════════════════════════════════════════════════════╝

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import 'vocab_history_service.dart';
import 'vocab_notif_service.dart';
import 'ai_vocab_chat_screen.dart';

class VocabHistoryScreen extends StatefulWidget {
  const VocabHistoryScreen({super.key});

  @override
  State<VocabHistoryScreen> createState() => _VocabHistoryScreenState();
}

class _VocabHistoryScreenState extends State<VocabHistoryScreen>
    with SingleTickerProviderStateMixin {
  final _svc        = VocabHistoryService.instance;
  final _searchCtrl = TextEditingController();

  // CHANGE-3: length 2 → 3
  late final TabController _tabCtrl;

  String _query    = '';
  bool   _searching = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this); // CHANGE-3
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ChatSession> get _filteredSessions {
    final all = _svc.sessions;
    if (_query.isEmpty) return all.toList();
    final q = _query.toLowerCase();
    return all.where((s) =>
      s.title.toLowerCase().contains(q) ||
      s.messages.any((m) => m.content.toLowerCase().contains(q))
    ).toList();
  }

  List<({ChatSession session, HistoryMessage message, int index})>
      get _filteredBookmarks {
    final all = _svc.getAllBookmarks();
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((b) => b.message.content.toLowerCase().contains(q)).toList();
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title  : const Text('Saari history delete karein?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Ye action undo nahi ho sakta.',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _svc.clearAll().then((_) => setState(() {}));
            },
            child: const Text('Delete All',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _deleteSession(ChatSession session) {
    _svc.deleteSession(session.id).then((_) {
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content : const Text('Session delete ho gaya'),
            behavior: SnackBarBehavior.floating,
            action  : SnackBarAction(
              label  : 'Undo',
              onPressed: () {
                _svc.saveSession(
                  sessionId: session.id,
                  messages : session.messages,
                ).then((_) => setState(() {}));
              },
            ),
          ),
        );
      }
    });
  }

  void _openSession(ChatSession session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIVocabChatScreen(resumeSession: session),
      ),
    ).then((_) => setState(() {}));
  }

  void _viewBookmarkDetail(ChatSession session, HistoryMessage message) {
    showModalBottomSheet(
      context            : context,
      backgroundColor    : AppTheme.bgCard,
      isScrollControlled : true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BookmarkDetailSheet(
        session  : session,
        message  : message,
        accent   : Theme.of(context).colorScheme.primary,
        onUnbookmark: () {
          final idx = session.messages.indexOf(message);
          if (idx != -1) {
            _svc.toggleBookmark(session.id, idx)
                .then((_) => setState(() {}));
          }
          Navigator.pop(context);
        },
        onContinue: () {
          Navigator.pop(context);
          _openSession(session);
        },
      ),
    );
  }

  // CHANGE-3: Start notif quiz
  void _startNotifQuiz(BuildContext context) {
    final pending = VocabNotifService.instance.deliveredNotifs
        .where((n) => !n.quizAnswered)
        .toList();

    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content : Text('Sabka quiz ho chuka hai! 🎉'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _NotifQuizScreen(words: pending),
      ),
    ).then((_) => setState(() {}));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final stats  = _svc.getStats();

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: _buildAppBar(accent),
      body: Column(
        children: [
          _buildStatsRow(stats, accent),
          _buildSearchBar(accent),
          _buildTabBar(accent),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildSessionsTab(accent),
                _buildBookmarksTab(accent),
                _buildNotifHistoryTab(accent), // CHANGE-3
              ],
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar(Color accent) {
    return AppBar(
      backgroundColor: AppTheme.bgCard,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded,
            color: AppTheme.textPrimary, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Chat History',
        style: TextStyle(
          fontFamily : 'Poppins', fontSize: 17, fontWeight: FontWeight.w700,
          color      : AppTheme.textPrimary,
        ),
      ),
      actions: [
        if (_svc.sessionCount > 0)
          IconButton(
            icon   : const Icon(Icons.delete_sweep_rounded,
                color: Colors.redAccent, size: 22),
            tooltip: 'Clear all history',
            onPressed: _clearAll,
          ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.white.withOpacity(0.07)),
      ),
    );
  }

  Widget _buildStatsRow(Map<String, int> stats, Color accent) {
    return Container(
      margin : const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent.withOpacity(0.15), accent.withOpacity(0.05)],
          begin : Alignment.topLeft,
          end   : Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            value: '${stats['totalSessions']}',
            label: 'Sessions',
            icon : Icons.chat_bubble_outline_rounded,
            accent: accent,
          ),
          _Divider(),
          _StatItem(
            value: '${stats['todaySessions']}',
            label: 'Today',
            icon : Icons.today_rounded,
            accent: accent,
          ),
          _Divider(),
          _StatItem(
            value: '${stats['totalMessages']}',
            label: 'Messages',
            icon : Icons.message_outlined,
            accent: accent,
          ),
          _Divider(),
          _StatItem(
            value: '${stats['bookmarks']}',
            label: 'Bookmarks',
            icon : Icons.bookmark_rounded,
            accent: accent,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          color       : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _searching ? accent.withOpacity(0.5) : Colors.white.withOpacity(0.08)),
        ),
        child: TextField(
          controller: _searchCtrl,
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textPrimary),
          onChanged: (v) => setState(() {
            _query    = v;
            _searching = v.isNotEmpty;
          }),
          decoration: InputDecoration(
            hintText  : 'Search sessions ya words...',
            hintStyle : TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textSecondary),
            prefixIcon: Icon(Icons.search_rounded,
                color: _searching ? accent : AppTheme.textSecondary, size: 20),
            suffixIcon: _searching
                ? IconButton(
                    icon    : const Icon(Icons.close_rounded,
                        color: AppTheme.textSecondary, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() { _query = ''; _searching = false; });
                    },
                  )
                : null,
            border        : InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          ),
        ),
      ),
    );
  }

  // CHANGE-3: Updated TabBar — 3 tabs
  Widget _buildTabBar(Color accent) {
    final deliveredCount   = VocabNotifService.instance.deliveredNotifs.length;
    final unansweredCount  = VocabNotifService.instance.deliveredNotifs
        .where((n) => !n.quizAnswered)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          color       : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TabBar(
          controller          : _tabCtrl,
          labelColor          : Colors.white,
          unselectedLabelColor: AppTheme.textSecondary,
          indicator: BoxDecoration(
            gradient    : LinearGradient(colors: [accent, accent.withOpacity(0.7)]),
            borderRadius: BorderRadius.circular(10),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor : Colors.transparent,
          labelStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600),
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history_rounded, size: 14),
                  const SizedBox(width: 4),
                  Text('📖 Sessions (${_svc.sessionCount})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bookmark_rounded, size: 14),
                  const SizedBox(width: 4),
                  Text('🔖 Bookmarks (${_svc.getStats()['bookmarks']})'),
                ],
              ),
            ),
            // CHANGE-3: New notif history tab
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.notifications_rounded, size: 14),
                  const SizedBox(width: 4),
                  Text(unansweredCount > 0
                      ? '🔔 Notifs ($unansweredCount quiz)'
                      : '🔔 Notifs ($deliveredCount)'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sessions Tab ──────────────────────────────────────────────────────────

  Widget _buildSessionsTab(Color accent) {
    final sessions = _filteredSessions;

    if (sessions.isEmpty) {
      return _EmptyState(
        icon    : Icons.history_rounded,
        title   : _query.isNotEmpty ? 'Koi session nahi mila' : 'Koi history nahi',
        subtitle: _query.isNotEmpty
            ? '"$_query" se koi session match nahi karta'
            : 'Jab bhi vocab chat karoge, yahan save ho jayega!',
        accent  : accent,
      );
    }

    return ListView.builder(
      padding    : const EdgeInsets.fromLTRB(12, 10, 12, 16),
      itemCount  : sessions.length,
      itemBuilder: (_, i) => _SessionCard(
        session : sessions[i],
        accent  : accent,
        onTap   : () => _openSession(sessions[i]),
        onDelete: () => _deleteSession(sessions[i]),
        query   : _query,
      ),
    );
  }

  // ── Bookmarks Tab ─────────────────────────────────────────────────────────

  Widget _buildBookmarksTab(Color accent) {
    final bookmarks = _filteredBookmarks;

    if (bookmarks.isEmpty) {
      return _EmptyState(
        icon    : Icons.bookmark_border_rounded,
        title   : _query.isNotEmpty ? 'Koi bookmark nahi mila' : 'Koi bookmark nahi',
        subtitle: _query.isNotEmpty
            ? '"$_query" se koi match nahi'
            : 'AI replies pe 🔖 button press karo bookmark karne ke liye!',
        accent : accent,
      );
    }

    return ListView.builder(
      padding    : const EdgeInsets.fromLTRB(12, 10, 12, 16),
      itemCount  : bookmarks.length,
      itemBuilder: (_, i) {
        final b = bookmarks[i];
        return _BookmarkCard(
          session : b.session,
          message : b.message,
          accent  : accent,
          onTap   : () => _viewBookmarkDetail(b.session, b.message),
        );
      },
    );
  }

  // ── CHANGE-3: Notif History Tab ───────────────────────────────────────────

  Widget _buildNotifHistoryTab(Color accent) {
    final notifs = VocabNotifService.instance.deliveredNotifs.reversed.toList();

    if (notifs.isEmpty) {
      return _EmptyState(
        icon    : Icons.notifications_none_rounded,
        title   : 'Abhi koi notification nahi aaya',
        subtitle: 'Jab notifications schedule honge, woh words yahan dikhnge.\n'
                  'Quiz do aur track karo apni progress! 📊',
        accent  : accent,
      );
    }

    final unanswered = notifs.where((n) => !n.quizAnswered).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        // Quiz prompt card if there are unanswered notifs
        if (unanswered.isNotEmpty)
          GestureDetector(
            onTap: () => _startNotifQuiz(context),
            child: Container(
              margin : const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent, accent.withOpacity(0.7)],
                  begin : Alignment.topLeft,
                  end   : Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color    : accent.withOpacity(0.4),
                    blurRadius: 12,
                    offset   : const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color : Colors.white.withOpacity(0.2),
                      shape : BoxShape.circle,
                    ),
                    child: const Icon(Icons.quiz_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📝 Quiz Lo!',
                          style: const TextStyle(
                            fontFamily : 'Poppins',
                            fontSize   : 16,
                            fontWeight : FontWeight.w800,
                            color      : Colors.white,
                          ),
                        ),
                        Text(
                          '${unanswered.length} words aaye — quiz do aur yaad karo!',
                          style: const TextStyle(
                            fontFamily : 'Poppins',
                            fontSize   : 12,
                            color      : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white60, size: 20),
                ],
              ),
            ),
          ),

        // Summary row
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(
                '${notifs.length} notifications',
                style: const TextStyle(
                  fontFamily : 'Poppins',
                  fontSize   : 12,
                  fontWeight : FontWeight.w600,
                  color      : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              if (notifs.any((n) => n.quizAnswered))
                Text(
                  '• ${notifs.where((n) => n.quizCorrect == true).length}/'
                  '${notifs.where((n) => n.quizAnswered).length} sahi',
                  style: const TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 12,
                    color      : Colors.greenAccent,
                  ),
                ),
            ],
          ),
        ),

        // Notif list
        ...notifs.map((n) => _NotifHistoryCard(notif: n, accent: accent)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CHANGE-3: Notif History Card
// ═══════════════════════════════════════════════════════════════════

class _NotifHistoryCard extends StatelessWidget {
  final DeliveredVocabNotif notif;
  final Color               accent;

  const _NotifHistoryCard({required this.notif, required this.accent});

  String _timeLabel(DateTime dt) {
    final now  = DateTime.now();
    final diff = now.difference(dt);
    final h    = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m    = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    final timeStr = '$h:$m $ampm';

    if (diff.inDays == 0) return 'Aaj $timeStr';
    if (diff.inDays == 1) return 'Kal $timeStr';
    const months = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month]} $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = notif.quizAnswered
        ? (notif.quizCorrect == true ? Colors.greenAccent : Colors.redAccent)
        : Colors.white38;
    final statusLabel = notif.quizAnswered
        ? (notif.quizCorrect == true ? '✓ Sahi' : '✗ Galat')
        : 'Quiz Nahi Diya';
    final statusBg = notif.quizAnswered
        ? (notif.quizCorrect == true
            ? Colors.greenAccent.withOpacity(0.1)
            : Colors.redAccent.withOpacity(0.1))
        : Colors.white.withOpacity(0.04);

    return Container(
      margin  : const EdgeInsets.only(bottom: 10),
      padding : const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color       : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border      : Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  notif.word.toUpperCase(),
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 18,
                    fontWeight : FontWeight.w800,
                    color      : accent,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color       : statusBg,
                  borderRadius: BorderRadius.circular(20),
                  border      : Border.all(color: statusColor.withOpacity(0.4)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 11,
                    fontWeight : FontWeight.w600,
                    color      : statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            notif.hindiMeaning,
            style: const TextStyle(
              fontFamily : 'Poppins',
              fontSize   : 13,
              fontWeight : FontWeight.w500,
              color      : AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            notif.hindiSentence,
            style: TextStyle(
              fontFamily : 'Poppins',
              fontSize   : 12,
              color      : AppTheme.textSecondary,
              fontStyle  : FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  color: AppTheme.textSecondary, size: 12),
              const SizedBox(width: 4),
              Text(
                _timeLabel(notif.deliveredAt),
                style: const TextStyle(
                  fontFamily : 'Poppins',
                  fontSize   : 11,
                  color      : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CHANGE-3: _NotifQuizScreen
// ═══════════════════════════════════════════════════════════════════

class _NotifQuizScreen extends StatefulWidget {
  final List<DeliveredVocabNotif> words;
  const _NotifQuizScreen({required this.words});

  @override
  State<_NotifQuizScreen> createState() => _NotifQuizScreenState();
}

class _NotifQuizScreenState extends State<_NotifQuizScreen> {
  int     _currentIndex = 0;
  int?    _selectedOption;      // index into _options
  bool    _answered     = false;
  int     _correctCount = 0;
  bool    _finished     = false;
  final   _rng          = Random();

  late List<String> _options;

  @override
  void initState() {
    super.initState();
    _buildOptions();
  }

  void _buildOptions() {
    if (_currentIndex >= widget.words.length) return;

    final correct = widget.words[_currentIndex].hindiMeaning;
    final wordBank = VocabNotifService.instance.wordBank;

    // Get 3 wrong options from word bank
    final pool = wordBank
        .where((w) => w.hindiMeaning != correct && w.hindiMeaning.isNotEmpty)
        .map((w) => w.hindiMeaning)
        .toSet()
        .toList()
      ..shuffle(_rng);

    final wrongs = pool.take(3).toList();

    // Pad with placeholders if not enough
    while (wrongs.length < 3) {
      wrongs.add('—');
    }

    _options = [correct, ...wrongs]..shuffle(_rng);
    _selectedOption = null;
    _answered       = false;
  }

  void _onSelectOption(int idx) {
    if (_answered) return;

    final isCorrect = _options[idx] == widget.words[_currentIndex].hindiMeaning;
    setState(() {
      _selectedOption = idx;
      _answered       = true;
      if (isCorrect) _correctCount++;
    });

    // Persist result
    final notif = widget.words[_currentIndex];
    VocabNotifService.instance.markQuizResult(
      notif.word, notif.deliveredAt, isCorrect);
  }

  void _nextWord() {
    if (_currentIndex + 1 >= widget.words.length) {
      setState(() => _finished = true);
    } else {
      setState(() {
        _currentIndex++;
        _buildOptions();
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor : AppTheme.bgCard,
        elevation       : 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded,
              color: AppTheme.textPrimary, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _finished ? 'Quiz Result' : 'Notif Quiz',
          style: const TextStyle(
            fontFamily : 'Poppins',
            fontSize   : 16,
            fontWeight : FontWeight.w700,
            color      : AppTheme.textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white.withOpacity(0.07)),
        ),
      ),
      body: _finished ? _buildResultScreen(accent) : _buildQuizBody(accent),
    );
  }

  Widget _buildQuizBody(Color accent) {
    final total  = widget.words.length;
    final notif  = widget.words[_currentIndex];
    final correct = notif.hindiMeaning;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value           : (_currentIndex + (_answered ? 1 : 0)) / total,
              backgroundColor : Colors.white.withOpacity(0.08),
              valueColor      : AlwaysStoppedAnimation<Color>(accent),
              minHeight       : 6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Q ${_currentIndex + 1} / $total',
            style: TextStyle(
              fontFamily : 'Poppins',
              fontSize   : 13,
              color      : accent.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 24),

          // Word card
          Container(
            width      : double.infinity,
            padding    : const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration : BoxDecoration(
              gradient: LinearGradient(
                colors: [accent.withOpacity(0.25), accent.withOpacity(0.1)],
                begin : Alignment.topLeft,
                end   : Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Text(
                  notif.word.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 32,
                    fontWeight : FontWeight.w900,
                    color      : accent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hindi meaning kya hai?',
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 13,
                    color      : accent.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Options
          ...List.generate(_options.length, (i) {
            final label   = ['A', 'B', 'C', 'D'][i];
            final isCorrectOpt = _options[i] == correct;

            Color borderColor = Colors.white12;
            Color bgColor     = AppTheme.bgCard;
            Color textColor   = AppTheme.textPrimary;

            if (_answered) {
              if (isCorrectOpt) {
                borderColor = Colors.greenAccent;
                bgColor     = Colors.greenAccent.withOpacity(0.12);
                textColor   = Colors.greenAccent;
              } else if (_selectedOption == i) {
                borderColor = Colors.redAccent;
                bgColor     = Colors.redAccent.withOpacity(0.12);
                textColor   = Colors.redAccent;
              }
            }

            return GestureDetector(
              onTap: () => _onSelectOption(i),
              child: AnimatedContainer(
                duration   : const Duration(milliseconds: 200),
                margin     : const EdgeInsets.only(bottom: 10),
                padding    : const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration : BoxDecoration(
                  color       : bgColor,
                  borderRadius: BorderRadius.circular(14),
                  border      : Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color : _answered && isCorrectOpt
                            ? Colors.greenAccent.withOpacity(0.2)
                            : (_answered && _selectedOption == i && !isCorrectOpt)
                                ? Colors.redAccent.withOpacity(0.2)
                                : accent.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontFamily : 'Poppins',
                            fontSize   : 13,
                            fontWeight : FontWeight.w700,
                            color      : textColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _options[i],
                        style: TextStyle(
                          fontFamily : 'Poppins',
                          fontSize   : 13,
                          color      : textColor,
                        ),
                      ),
                    ),
                    if (_answered && isCorrectOpt)
                      const Icon(Icons.check_circle_rounded,
                          color: Colors.greenAccent, size: 18)
                    else if (_answered && _selectedOption == i && !isCorrectOpt)
                      const Icon(Icons.cancel_rounded,
                          color: Colors.redAccent, size: 18),
                  ],
                ),
              ),
            );
          }),

          const Spacer(),

          // Next button (visible after answering)
          if (_answered)
            GestureDetector(
              onTap: _nextWord,
              child: Container(
                width  : double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, accent.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color    : accent.withOpacity(0.4),
                      blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Text(
                  _currentIndex + 1 >= widget.words.length
                      ? 'Result Dekho 🏆'
                      : 'Agla Word →',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 15,
                    fontWeight : FontWeight.w700,
                    color      : Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultScreen(Color accent) {
    final total = widget.words.length;
    final pct   = total > 0 ? (_correctCount / total * 100).round() : 0;
    final emoji = pct >= 80 ? '🏆' : pct >= 60 ? '👍' : pct >= 40 ? '😊' : '💪';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 64),
            ),
            const SizedBox(height: 20),
            Text(
              '$_correctCount / $total Sahi!',
              style: const TextStyle(
                fontFamily : 'Poppins',
                fontSize   : 32,
                fontWeight : FontWeight.w800,
                color      : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$pct% score',
              style: TextStyle(
                fontFamily : 'Poppins',
                fontSize   : 16,
                color      : accent,
                fontWeight : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              pct >= 80
                  ? 'Wah! Excellent! 🌟 Keep going!'
                  : pct >= 60
                      ? 'Acha kiya! Thoda aur practice karo! 📚'
                      : 'Practice se perfect hoga! Dobara try karo! 💪',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily : 'Poppins',
                fontSize   : 14,
                color      : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 40, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, accent.withOpacity(0.7)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color    : accent.withOpacity(0.4),
                      blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: const Text(
                  'Notif History Dekho',
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 15,
                    fontWeight : FontWeight.w700,
                    color      : Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Session Card
// ═══════════════════════════════════════════════════════════════════

class _SessionCard extends StatelessWidget {
  final ChatSession  session;
  final Color        accent;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final String       query;

  const _SessionCard({
    required this.session,
    required this.accent,
    required this.onTap,
    required this.onDelete,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    final now      = DateTime.now();
    final diff     = now.difference(session.updatedAt);
    final timeLabel = diff.inMinutes < 60
        ? '${diff.inMinutes}m ago'
        : diff.inHours < 24
            ? '${diff.inHours}h ago'
            : diff.inDays == 1
                ? 'Kal'
                : _dateStr(session.updatedAt);

    return Dismissible(
      key       : Key(session.id),
      direction : DismissDirection.endToStart,
      background: Container(
        alignment  : Alignment.centerRight,
        padding    : const EdgeInsets.only(right: 20),
        decoration : BoxDecoration(
          color       : Colors.redAccent.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 24),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin  : const EdgeInsets.only(bottom: 10),
          padding : const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color       : AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border      : Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.chat_bubble_rounded, color: accent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.title,
                          maxLines : 1,
                          overflow : TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily : 'Poppins',
                            fontSize   : 13.5,
                            fontWeight : FontWeight.w600,
                            color      : AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 11,
                            color: AppTheme.textSecondary.withOpacity(0.7)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color       : accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${session.messageCount} msgs',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 10, color: accent),
                        ),
                      ),
                      if (session.bookmarkCount > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bookmark_rounded,
                                size: 11, color: accent.withOpacity(0.7)),
                            const SizedBox(width: 2),
                            Text(
                              '${session.bookmarkCount}',
                              style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 10,
                                color: accent.withOpacity(0.7)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (session.previewText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  session.previewText,
                  maxLines : 2,
                  overflow : TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily : 'Poppins', fontSize: 12,
                    color : AppTheme.textSecondary.withOpacity(0.8), height: 1.4),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.play_circle_outline_rounded, color: accent, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Tap to resume',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 11, color: accent),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dateStr(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month]}';
  }
}

// ═══════════════════════════════════════════════════════════════════
// Bookmark Card
// ═══════════════════════════════════════════════════════════════════

class _BookmarkCard extends StatelessWidget {
  final ChatSession    session;
  final HistoryMessage message;
  final Color          accent;
  final VoidCallback   onTap;

  const _BookmarkCard({
    required this.session,
    required this.message,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin  : const EdgeInsets.only(bottom: 10),
        padding : const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color       : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border      : Border.all(color: accent.withOpacity(0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(Icons.bookmark_rounded, color: accent, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session.title,
                    maxLines : 1,
                    overflow : TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 11,
                      color: accent.withOpacity(0.8)),
                  ),
                ),
                Text(
                  '${message.time.hour.toString().padLeft(2, '0')}'
                  ':${message.time.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 10,
                    color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              message.content,
              maxLines : 4,
              overflow : TextOverflow.ellipsis,
              style    : const TextStyle(
                fontFamily : 'Poppins', fontSize: 13,
                color : AppTheme.textPrimary, height: 1.5),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Tap to view full',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    color: accent.withOpacity(0.7)),
                ),
                const SizedBox(width: 4),
                Icon(Icons.open_in_new_rounded, size: 12,
                    color: accent.withOpacity(0.7)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Bookmark Detail Bottom Sheet
// ═══════════════════════════════════════════════════════════════════

class _BookmarkDetailSheet extends StatelessWidget {
  final ChatSession    session;
  final HistoryMessage message;
  final Color          accent;
  final VoidCallback   onUnbookmark;
  final VoidCallback   onContinue;

  const _BookmarkDetailSheet({
    required this.session,
    required this.message,
    required this.accent,
    required this.onUnbookmark,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.bookmark_rounded, color: accent, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'From: ${session.title}',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12,
                    color: accent.withOpacity(0.8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding    : const EdgeInsets.all(14),
            decoration : BoxDecoration(
              color       : AppTheme.bgDeep,
              borderRadius: BorderRadius.circular(14),
              border      : Border.all(color: accent.withOpacity(0.15)),
            ),
            child: SelectableText(
              message.content,
              style: const TextStyle(
                fontFamily : 'Poppins', fontSize: 13.5,
                color : AppTheme.textPrimary, height: 1.6),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: message.content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content : Text('Copied! 📋'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color       : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border      : Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.copy_rounded, color: AppTheme.textSecondary, size: 16),
                  SizedBox(width: 6),
                  Text('Copy Text',
                      style: TextStyle(
                        fontFamily : 'Poppins', fontSize: 13,
                        color: AppTheme.textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onUnbookmark,
                  child: Container(
                    padding   : const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color       : Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bookmark_remove_rounded,
                            color: Colors.redAccent, size: 16),
                        SizedBox(width: 6),
                        Text('Remove',
                            style: TextStyle(
                              fontFamily : 'Poppins', fontSize: 13,
                              color : Colors.redAccent, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onContinue,
                  child: Container(
                    padding   : const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent, accent.withOpacity(0.7)],
                        begin : Alignment.topLeft,
                        end   : Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 18),
                        SizedBox(width: 4),
                        Text('Continue Chat',
                            style: TextStyle(
                              fontFamily : 'Poppins', fontSize: 13,
                              color : Colors.white, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Helper Widgets
// ═══════════════════════════════════════════════════════════════════

class _StatItem extends StatelessWidget {
  final String  value;
  final String  label;
  final IconData icon;
  final Color   accent;

  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: accent, size: 16),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontFamily : 'Poppins', fontSize: 16, fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary),
        ),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 10, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: Colors.white.withOpacity(0.08));
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final Color    accent;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: accent.withOpacity(0.5), size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily : 'Poppins', fontSize: 16, fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily : 'Poppins', fontSize: 13,
                color: AppTheme.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
