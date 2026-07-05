// ╔══════════════════════════════════════════════════════════════╗
// ║  Vocab Word Bank Screen                                      ║
// ║  Browse, search & explore notification word bank            ║
// ║  NEW FILE — Add link from VocabNotifSettingsScreen          ║
// ╚══════════════════════════════════════════════════════════════╝

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import 'vocab_notif_service.dart';
import 'ai_vocab_chat_screen.dart';
import 'groq_service.dart';

class VocabWordBankScreen extends StatefulWidget {
  const VocabWordBankScreen({super.key});

  @override
  State<VocabWordBankScreen> createState() => _VocabWordBankScreenState();
}

class _VocabWordBankScreenState extends State<VocabWordBankScreen> {
  final _svc        = VocabNotifService.instance;
  final _searchCtrl = TextEditingController();

  String _query = '';

  List<VocabWord> get _filtered {
    final all = _svc.wordBank;
    if (_query.isEmpty) return all.toList();
    final q = _query.toLowerCase();
    return all.where((w) =>
      w.word.toLowerCase().contains(q) ||
      w.hindiMeaning.toLowerCase().contains(q) ||
      w.hindiSentence.toLowerCase().contains(q)
    ).toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openWordDetail(VocabWord word, Color accent) {
    showModalBottomSheet(
      context        : context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _WordDetailSheet(word: word, accent: accent),
    );
  }

  void _askAIAboutWord(VocabWord word) {
    // Open chat with the word pre-loaded as query
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIVocabChatScreen(
          resumeSession: null,
          // Will auto-send this word as first message
        ),
      ),
    );
    // Note: To pre-load query, pass it via a different approach or
    // user can just type the word themselves in the chat.
  }

  @override
  Widget build(BuildContext context) {
    final accent   = Theme.of(context).colorScheme.primary;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: _buildAppBar(accent),
      body: Column(
        children: [
          _buildHeader(accent),
          _buildSearchBar(accent),
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState(accent)
                : _buildWordList(filtered, accent),
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
        'Word Bank',
        style: TextStyle(
          fontFamily : 'Poppins',
          fontSize   : 17,
          fontWeight : FontWeight.w700,
          color      : AppTheme.textPrimary,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent, accent.withValues(alpha: 0.7)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_svc.wordBankSize} words',
                style: const TextStyle(
                  fontFamily : 'Poppins',
                  fontSize   : 11,
                  fontWeight : FontWeight.w700,
                  color      : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
      ),
    );
  }

  Widget _buildHeader(Color accent) {
    return Container(
      margin : const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: 0.15), accent.withValues(alpha: 0.05)],
          begin : Alignment.topLeft,
          end   : Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.library_books_rounded,
                color: accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_svc.wordBankSize} SSC Words Ready!',
                  style: const TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 15,
                    fontWeight : FontWeight.w700,
                    color      : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _svc.wordBankSize > 0
                      ? 'Ye words tumhare notifications mein aate hain 🔔'
                      : 'Word bank empty hai — Settings se generate karo',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize  : 12,
                    color     : AppTheme.textSecondary,
                    height    : 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color       : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border      : Border.all(
            color: _query.isNotEmpty
                ? accent.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.08)),
        ),
        child: TextField(
          controller: _searchCtrl,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize  : 13,
            color     : AppTheme.textPrimary,
          ),
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText   : 'Word ya Hindi meaning se search karo...',
            hintStyle  : TextStyle(
              fontFamily: 'Poppins',
              fontSize  : 13,
              color     : AppTheme.textSecondary,
            ),
            prefixIcon : Icon(Icons.search_rounded,
                color: _query.isNotEmpty ? accent : AppTheme.textSecondary,
                size : 20),
            suffixIcon : _query.isNotEmpty
                ? IconButton(
                    icon     : const Icon(Icons.close_rounded,
                        color: AppTheme.textSecondary, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
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

  Widget _buildEmptyState(Color accent) {
    if (_svc.wordBankSize == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.library_books_outlined,
                    color: accent.withValues(alpha: 0.4), size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'Word Bank Empty!',
                style: TextStyle(
                  fontFamily : 'Poppins',
                  fontSize   : 16,
                  fontWeight : FontWeight.w600,
                  color      : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Notification settings mein jao aur\n"Generate Word Bank" press karo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize  : 13,
                  color     : AppTheme.textSecondary,
                  height    : 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Text(
        '"$_query" — koi word nahi mila',
        style: const TextStyle(
          fontFamily: 'Poppins',
          color     : AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildWordList(List<VocabWord> words, Color accent) {
    return ListView.builder(
      padding    : const EdgeInsets.fromLTRB(12, 6, 12, 20),
      itemCount  : words.length,
      itemBuilder: (_, i) {
        final w = words[i];
        return _WordCard(
          word   : w,
          index  : i,
          accent : accent,
          onTap  : () => _openWordDetail(w, accent),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Word Card
// ═══════════════════════════════════════════════════════════════════

class _WordCard extends StatelessWidget {
  final VocabWord word;
  final int       index;
  final Color     accent;
  final VoidCallback onTap;

  const _WordCard({
    required this.word,
    required this.index,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin  : const EdgeInsets.only(bottom: 8),
        padding : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color       : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border      : Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            // Number badge
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 11,
                    fontWeight : FontWeight.w700,
                    color      : accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    word.word,
                    style: const TextStyle(
                      fontFamily : 'Poppins',
                      fontSize   : 15,
                      fontWeight : FontWeight.w700,
                      color      : AppTheme.textPrimary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    word.hindiMeaning,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize  : 12,
                      color     : accent.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: AppTheme.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Word Detail Bottom Sheet
// ═══════════════════════════════════════════════════════════════════

class _WordDetailSheet extends StatefulWidget {
  final VocabWord word;
  final Color     accent;

  const _WordDetailSheet({required this.word, required this.accent});

  @override
  State<_WordDetailSheet> createState() => _WordDetailSheetState();
}

class _WordDetailSheetState extends State<_WordDetailSheet> {
  bool   _loadingAI  = false;
  String _aiResponse = '';

  Future<void> _fetchAIDetail() async {
    setState(() { _loadingAI = true; _aiResponse = ''; });

    final query = 'Mujhe "${widget.word.word}" word detail mein explain karo '
                  '— pronunciation, meaning, examples, memory trick, SSC CGL intel.';

    final reply = await GroqService.instance.sendMessage([
      ChatMessage(role: 'user', content: query),
    ]);

    if (mounted) setState(() { _loadingAI = false; _aiResponse = reply; });
  }

  @override
  Widget build(BuildContext context) {
    final w      = widget.word;
    final accent = widget.accent;

    return DraggableScrollableSheet(
      expand           : false,
      initialChildSize : 0.6,
      minChildSize     : 0.4,
      maxChildSize     : 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color       : AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding   : EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.of(context).padding.bottom + 20),
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Word Title
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w.word.toUpperCase(),
                        style: TextStyle(
                          fontFamily   : 'Poppins',
                          fontSize     : 26,
                          fontWeight   : FontWeight.w800,
                          color        : accent,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        w.hindiMeaning,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize  : 14,
                          color     : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Copy word button
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: w.word));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content : Text('Word copied!'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.copy_rounded,
                        color: accent, size: 18),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 16),

            // Hinglish sentence
            _SectionLabel(
              icon : Icons.format_quote_rounded,
              label: 'Example Sentence',
              accent: accent,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color       : accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border      : Border.all(color: accent.withValues(alpha: 0.18)),
              ),
              child: Text(
                '"${w.hindiSentence}"',
                style: const TextStyle(
                  fontFamily : 'Poppins',
                  fontSize   : 13.5,
                  color      : AppTheme.textPrimary,
                  height     : 1.5,
                  fontStyle  : FontStyle.italic,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // AI Explain button
            if (_aiResponse.isEmpty)
              GestureDetector(
                onTap: _loadingAI ? null : _fetchAIDetail,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: _loadingAI
                        ? null
                        : LinearGradient(
                            colors: [accent, accent.withValues(alpha: 0.7)],
                            begin : Alignment.topLeft,
                            end   : Alignment.bottomRight,
                          ),
                    color       : _loadingAI ? Colors.white12 : null,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _loadingAI
                        ? null
                        : [BoxShadow(
                            color     : accent.withValues(alpha: 0.3),
                            blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  alignment: Alignment.center,
                  child: _loadingAI
                      ? const SizedBox(
                          width : 22, height: 22,
                          child : CircularProgressIndicator(
                            color     : Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome_rounded,
                                color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'AI se Full Detail lo 🚀',
                              style: TextStyle(
                                fontFamily : 'Poppins',
                                fontSize   : 14,
                                fontWeight : FontWeight.w700,
                                color      : Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              )
            else ...[
              // AI Response
              _SectionLabel(
                icon : Icons.auto_awesome_rounded,
                label: 'AI Explanation',
                accent: accent,
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color       : AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(14),
                  border      : Border.all(color: accent.withValues(alpha: 0.15)),
                ),
                child: SelectableText(
                  _aiResponse,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize  : 13.5,
                    color     : AppTheme.textPrimary,
                    height    : 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Ask again button
              GestureDetector(
                onTap: _fetchAIDetail,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color       : accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border      : Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Dobara refresh karo 🔄',
                    style: TextStyle(
                      fontFamily : 'Poppins',
                      fontSize   : 13,
                      fontWeight : FontWeight.w600,
                      color      : accent,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Helper
// ═══════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    accent;

  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: accent, size: 15),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily : 'Poppins',
            fontSize   : 12,
            fontWeight : FontWeight.w700,
            color      : accent,
          ),
        ),
      ],
    );
  }
}
