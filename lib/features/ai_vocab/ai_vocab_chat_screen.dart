// ╔══════════════════════════════════════════════════════════════╗
// ║  AI Vocab Chat Screen — SSC CGL Vocabulary Learning          ║
// ║  Powered by Groq (Llama 3.3 70B)                            ║
// ║  v2: History save/load, resume session, bookmark            ║
// ╚══════════════════════════════════════════════════════════════╝

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/router/app_router.dart';
import 'groq_service.dart';
import 'vocab_notif_service.dart';
import 'vocab_history_service.dart';
import 'vocab_history_screen.dart';

// ── Quick action chips shown at top ──────────────────────────────
const _kQuickActions = [
  ('📖 Word of the Day', 'Aaj ka word of the day batao'),
  ('🧪 Quiz me!',        'Mujhe SSC CGL vocab quiz do'),
  ('📋 Top 10 Words',    'SSC CGL ke top 10 important words batao'),
  ('🔤 Synonyms',        'Synonyms practice karni hai'),
  ('💡 Idioms',          'Common English idioms sikhao'),
  ('🔁 Antonyms',        'Antonyms practice karte hain'),
  ('📝 One Word Sub',    'One word substitution practice karo'),
  ('🎯 Difficult Words', 'SSC ke kuch difficult words batao'),
];

// ── Message bubble data model ─────────────────────────────────────
class _Msg {
  final String   text;
  final bool     isUser;
  final DateTime time;
  bool           bookmarked;

  _Msg({
    required this.text,
    required this.isUser,
    DateTime? time,
    this.bookmarked = false,
  }) : time = time ?? DateTime.now();

  HistoryMessage toHistory() => HistoryMessage(
        role       : isUser ? 'user' : 'assistant',
        content    : text,
        time       : time,
        bookmarked : bookmarked,
      );
}

// ═══════════════════════════════════════════════════════════════════
class AIVocabChatScreen extends StatefulWidget {
  /// Pass a saved session to resume it instead of starting fresh
  final ChatSession? resumeSession;

  const AIVocabChatScreen({super.key, this.resumeSession});

  @override
  State<AIVocabChatScreen> createState() => _AIVocabChatScreenState();
}

class _AIVocabChatScreenState extends State<AIVocabChatScreen>
    with TickerProviderStateMixin {
  final _ctrl      = TextEditingController();
  final _scroll    = ScrollController();
  final _focusNode = FocusNode();

  final List<_Msg>        _messages   = [];
  final List<ChatMessage> _apiHistory = [];

  bool    _loading    = false;
  bool    _showQuick  = true;
  String? _sessionId; // null = not yet saved

  late final AnimationController _typingCtrl;
  late final Animation<double>   _typingAnim;

  @override
  void initState() {
    super.initState();

    _typingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _typingAnim = CurvedAnimation(parent: _typingCtrl, curve: Curves.easeInOut);

    // Ensure history service is initialized
    VocabHistoryService.instance.init();

    if (widget.resumeSession != null) {
      // ── Resume a saved session ──────────────────────────────────
      final session = widget.resumeSession!;
      _sessionId = session.id;
      _showQuick = false;

      for (final hm in session.messages) {
        _messages.add(_Msg(
          text       : hm.content,
          isUser     : hm.role == 'user',
          time       : hm.time,
          bookmarked : hm.bookmarked,
        ));
        _apiHistory.add(hm.toChatMessage());
      }

      // Scroll to bottom after frame
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } else {
      // ── Fresh chat ─────────────────────────────────────────────
      _messages.add(_Msg(
        text: '🎵 Hey! Main BeatFlow ka AI Vocab Buddy hoon!\n\n'
              'SSC CGL ki taiyaari kar rahe ho? Main tumhara vocab partner hoon — '
              'koi bhi English word poochhlo, quiz lo, ya sirf baat karo.\n\n'
              'Shuru karte hain? 👇',
        isUser: false,
      ));
    }
  }

  @override
  void dispose() {
    _typingCtrl.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    _focusNode.dispose();
    // Auto-save session when screen closes
    _autoSave();
    super.dispose();
  }

  // ── Auto-save chat to history ─────────────────────────────────
  Future<void> _autoSave() async {
    // Only save if there's at least one user message (not just AI greeting)
    final hasUserMsg = _messages.any((m) => m.isUser);
    if (!hasUserMsg) return;

    final historyMessages = _messages.map((m) => m.toHistory()).toList();
    _sessionId = await VocabHistoryService.instance.saveSession(
      sessionId: _sessionId,
      messages : historyMessages,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _send([String? quickText]) async {
    final text = (quickText ?? _ctrl.text).trim();
    if (text.isEmpty || _loading) return;

    _ctrl.clear();
    _focusNode.unfocus();

    setState(() {
      _messages.add(_Msg(text: text, isUser: true));
      _apiHistory.add(ChatMessage(role: 'user', content: text));
      _loading   = true;
      _showQuick = false;
    });
    _scrollToBottom();

    final reply = await GroqService.instance.sendMessage(List.from(_apiHistory));

    setState(() {
      _messages.add(_Msg(text: reply, isUser: false));
      _apiHistory.add(ChatMessage(role: 'assistant', content: reply));
      _loading = false;
    });
    _scrollToBottom(delay: 80);

    // Auto-save after every exchange
    _autoSave();
  }

  void _scrollToBottom({int delay = 0}) {
    Future.delayed(Duration(milliseconds: delay), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve   : Curves.easeOut,
        );
      }
    });
  }

  void _copyMsg(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content  : Text('Copied! 📋'),
        duration : Duration(seconds: 1),
        behavior : SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleBookmark(int index) {
    setState(() => _messages[index].bookmarked = !_messages[index].bookmarked);
    _autoSave();
    final isNowBookmarked = _messages[index].bookmarked;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content : Text(isNowBookmarked ? '🔖 Bookmarked!' : 'Bookmark hata diya'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title  : const Text('Chat clear karein?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Ye chat history mein save ho jayegi.',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Save current session before clearing
              _autoSave().then((_) {
                setState(() {
                  _messages.clear();
                  _apiHistory.clear();
                  _showQuick = true;
                  _sessionId = null; // new session after clear
                  _messages.add(_Msg(
                    text   : '🔄 Chat reset! Kuch naya poochhte hain?',
                    isUser : false,
                  ));
                });
              });
            },
            child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _goToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VocabHistoryScreen()),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    // BUG-CHAT01 FIX: disable Scaffold resize, let the input bar handle it.
    return Scaffold(
      backgroundColor       : AppTheme.bgDeep,
      resizeToAvoidBottomInset: false,
      appBar: _buildAppBar(accent),
      body: Column(
        children: [
          if (_showQuick && _messages.length <= 1) _buildQuickActions(accent),
          Expanded(child: _buildMessageList(accent)),
          if (_loading) _buildTypingIndicator(accent),
          _buildInputBar(accent),
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
      title: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, accent.withValues(alpha: 0.6)],
                begin : Alignment.topLeft,
                end   : Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'AI Vocab Buddy',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 15,
                    fontWeight : FontWeight.w700,
                    color      : AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'SSC CGL Vocab Assistant',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize  : 11,
                    color     : accent.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // History Button
        IconButton(
          icon   : const Icon(Icons.history_rounded,
              color: AppTheme.textSecondary, size: 22),
          tooltip: 'Chat History',
          onPressed: _goToHistory,
        ),
        // Vocab Notification Scheduler Bell
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_rounded,
                  color: AppTheme.textSecondary, size: 22),
              tooltip  : 'Vocab Notifications',
              onPressed: () => context.push(AppRouter.vocabNotifSetup),
            ),
            if (VocabNotifService.instance.settings.enabled)
              Positioned(
                top: 8, right: 8,
                child: Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        IconButton(
          icon     : const Icon(Icons.delete_outline_rounded,
              color: AppTheme.textSecondary, size: 20),
          tooltip  : 'Clear chat',
          onPressed: _clearChat,
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
      ),
    );
  }

  Widget _buildQuickActions(Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Quick actions ⚡',
              style: TextStyle(
                fontFamily : 'Poppins',
                fontSize   : 12,
                color      : accent.withValues(alpha: 0.85),
                fontWeight : FontWeight.w600,
              ),
            ),
          ),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _kQuickActions.map((qa) {
              return _QuickChip(
                label  : qa.$1,
                accent : accent,
                onTap  : () => _send(qa.$2),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
        ],
      ),
    );
  }

  Widget _buildMessageList(Color accent) {
    return ListView.builder(
      controller: _scroll,
      padding   : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount : _messages.length,
      itemBuilder: (_, i) => _MessageBubble(
        msg        : _messages[i],
        accent     : accent,
        onCopy     : () => _copyMsg(_messages[i].text),
        onBookmark : _messages[i].isUser ? null : () => _toggleBookmark(i),
      ),
    );
  }

  Widget _buildTypingIndicator(Color accent) {
    return Container(
      padding  : const EdgeInsets.only(left: 16, bottom: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome_rounded, size: 14, color: accent),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: const BorderRadius.only(
                topLeft   : Radius.circular(4),
                topRight  : Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _typingAnim,
                  builder: (_, __) {
                    final val = math
                        .sin((_typingAnim.value * math.pi) + i * 0.3)
                        .clamp(0.0, 1.0);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width : 6,
                      height: 6 + val * 4,
                      decoration: BoxDecoration(
                        color : accent.withValues(alpha: 0.5 + val * 0.5),
                        shape : BoxShape.circle,
                      ),
                    );
                  },
                );
              }),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Soch raha hoon...',
            style: TextStyle(fontSize: 12, color: accent.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(Color accent) {
    return Container(
      padding: EdgeInsets.only(
        left  : 12,
        right : 12,
        top   : 10,
        bottom: MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color       : AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(24),
                border      : Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: TextField(
                controller      : _ctrl,
                focusNode       : _focusNode,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize  : 14,
                  color     : AppTheme.textPrimary,
                ),
                maxLines        : 4,
                minLines        : 1,
                textInputAction : TextInputAction.send,
                onSubmitted     : (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Koi word poochho ya baat karo...',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize  : 13,
                    color     : AppTheme.textSecondary,
                  ),
                  border        : InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _loading ? null : () => _send(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: _loading
                    ? null
                    : LinearGradient(
                        colors: [accent, accent.withValues(alpha: 0.7)],
                        begin : Alignment.topLeft,
                        end   : Alignment.bottomRight,
                      ),
                color    : _loading ? Colors.white12 : null,
                shape    : BoxShape.circle,
                boxShadow: _loading
                    ? null
                    : [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 10)],
              ),
              child: Icon(
                _loading ? Icons.hourglass_empty_rounded : Icons.send_rounded,
                color: _loading ? Colors.white38 : Colors.white,
                size : 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _MessageBubble extends StatelessWidget {
  final _Msg          msg;
  final Color         accent;
  final VoidCallback  onCopy;
  final VoidCallback? onBookmark; // null for user messages

  const _MessageBubble({
    required this.msg,
    required this.accent,
    required this.onCopy,
    this.onBookmark,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.6)]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 14),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: onCopy,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.80),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: isUser
                          ? LinearGradient(
                              colors: [accent, accent.withValues(alpha: 0.75)],
                              begin : Alignment.topLeft,
                              end   : Alignment.bottomRight,
                            )
                          : null,
                      color: isUser ? null : AppTheme.bgCard,
                      borderRadius: BorderRadius.only(
                        topLeft    : const Radius.circular(18),
                        topRight   : const Radius.circular(18),
                        bottomLeft : isUser
                            ? const Radius.circular(18)
                            : const Radius.circular(4),
                        bottomRight: isUser
                            ? const Radius.circular(4)
                            : const Radius.circular(18),
                      ),
                      border: isUser
                          ? null
                          : Border.all(color: accent.withValues(alpha: 0.18), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color    : (isUser ? accent : Colors.black)
                              .withValues(alpha: isUser ? 0.25 : 0.3),
                          blurRadius: 8,
                          offset   : const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          msg.text,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize  : 13.5,
                            height    : 1.55,
                            color     : isUser ? Colors.white : AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${msg.time.hour.toString().padLeft(2, '0')}'
                              ':${msg.time.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize  : 10,
                                color     : isUser
                                    ? Colors.white.withValues(alpha: 0.6)
                                    : AppTheme.textSecondary,
                              ),
                            ),
                            if (!isUser && msg.bookmarked) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.bookmark_rounded,
                                  size: 11, color: accent.withValues(alpha: 0.8)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Bookmark button for AI messages
                  if (!isUser && onBookmark != null)
                    Positioned(
                      top: -6, right: -6,
                      child: GestureDetector(
                        onTap: onBookmark,
                        child: Container(
                          width : 22, height: 22,
                          decoration: BoxDecoration(
                            color: msg.bookmarked
                                ? accent
                                : AppTheme.bgSurface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accent.withValues(alpha: 0.4), width: 1),
                          ),
                          child: Icon(
                            msg.bookmarked
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            size : 12,
                            color: msg.bookmarked ? Colors.white : accent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 6),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_rounded,
                  color: Colors.white70, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _QuickChip extends StatelessWidget {
  final String       label;
  final Color        accent;
  final VoidCallback onTap;

  const _QuickChip(
      {required this.label, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color       : accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border      : Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily : 'Poppins',
            fontSize   : 12,
            fontWeight : FontWeight.w500,
            color      : accent.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}
