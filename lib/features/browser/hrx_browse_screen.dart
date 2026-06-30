// ╔══════════════════════════════════════════════════════════════╗
// ║  HRxBrowse — Privacy-First In-App Browser for BeatFlow      ║
// ║  Features: Ad-Block · Private Mode · History · Bookmarks    ║
// ║  Default Search: DuckDuckGo (no tracking)                   ║
// ╚══════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/theme/app_theme.dart';

// ─── Constants ───────────────────────────────────────────────────
const _kHomePage   = 'https://duckduckgo.com';
const _kBoxName    = 'hrx_browse_v1';
const _kKeyHistory = 'history';
const _kKeyBookmarks = 'bookmarks';
const _kKeyAdBlock = 'adblock';

const _kDesktopUA =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
const _kMobileUA =
    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

// ─── Ad-domain blocklist ──────────────────────────────────────────
const _kAdDomains = <String>{
  'doubleclick.net',
  'googleadservices.com',
  'googlesyndication.com',
  'adservice.google.com',
  'amazon-adsystem.com',
  'scorecardresearch.com',
  'bat.bing.com',
  'pixel.facebook.com',
  'pagead2.googlesyndication.com',
  'tpc.googlesyndication.com',
  'adnxs.com',
  'adsrvr.org',
  'moatads.com',
  'criteo.com',
  'outbrain.com',
  'taboola.com',
  'popads.net',
  'adblade.com',
  'bidvertiser.com',
  'mgid.com',
  'revcontent.com',
  'zergnet.com',
  'ads.yahoo.com',
  'advertising.com',
  'pubmatic.com',
  'rubiconproject.com',
  'openx.net',
  'appnexus.com',
  'media.net',
  'ads.twitter.com',
  'static.ads-twitter.com',
};

// ─── Ad-removal JS (injected after page load) ─────────────────────
const _kAdBlockJs = r'''
(function(){
  var sels=['.adsbygoogle','[id^="google_ads"]','[id^="div-gpt-ad"]',
    '[class*="advert"]','[class*="banner-ad"]','[class*="ad-banner"]',
    '[class*="ad-slot"]','[class*="advertisement"]','[id*="advertisement"]',
    'iframe[src*="ads"]','iframe[src*="doubleclick"]',
    '.taboola-widget','.outbrain',
    '[data-ad]','[data-adunit]','[data-google-query-id]'];
  function clean(){sels.forEach(function(s){try{document.querySelectorAll(s)
    .forEach(function(e){e.style.display='none';});}catch(e){}});}
  clean();
  try{new MutationObserver(clean).observe(document.documentElement,
    {childList:true,subtree:true});}catch(e){}
})();
''';

// ─── Data models ──────────────────────────────────────────────────
class _HistItem {
  final String url;
  final String title;
  final DateTime time;
  _HistItem(this.url, this.title, this.time);

  Map<String, dynamic> toJson() =>
      {'u': url, 't': title, 'ts': time.millisecondsSinceEpoch};

  factory _HistItem.fromJson(Map j) => _HistItem(
        j['u'] as String,
        j['t'] as String,
        DateTime.fromMillisecondsSinceEpoch(j['ts'] as int),
      );
}

class _Bookmark {
  final String url;
  final String title;
  _Bookmark(this.url, this.title);

  Map<String, dynamic> toJson() => {'u': url, 't': title};
  factory _Bookmark.fromJson(Map j) =>
      _Bookmark(j['u'] as String, j['t'] as String);
}

// ═══════════════════════════════════════════════════════════════════
class HRxBrowseScreen extends StatefulWidget {
  final String? initialUrl;
  final bool startPrivate;

  const HRxBrowseScreen({
    super.key,
    this.initialUrl,
    this.startPrivate = false,
  });

  @override
  State<HRxBrowseScreen> createState() => _HRxBrowseScreenState();
}

class _HRxBrowseScreenState extends State<HRxBrowseScreen> {
  late final WebViewController _wc;
  Box<String>? _box;

  // UI state
  bool _private = false;
  bool _adBlock = true;
  bool _desktop = false;
  bool _loading = false;
  int  _progress = 0;
  bool _canBack  = false;
  bool _canFwd   = false;

  String _url   = _kHomePage;
  String _title = 'HRxBrowse';

  List<_HistItem> _history   = [];
  List<_Bookmark> _bookmarks = [];

  // ── Init ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _private = widget.startPrivate;
    _initWc();
    _initBox();
  }

  Future<void> _initBox() async {
    final box = await Hive.openBox<String>(_kBoxName);
    _box = box;
    _adBlock = (box.get(_kKeyAdBlock) ?? 'true') == 'true';

    final hRaw = box.get(_kKeyHistory);
    if (hRaw != null) {
      final list = jsonDecode(hRaw) as List;
      _history = list.map((e) => _HistItem.fromJson(e as Map)).toList();
    }
    final bRaw = box.get(_kKeyBookmarks);
    if (bRaw != null) {
      final list = jsonDecode(bRaw) as List;
      _bookmarks = list.map((e) => _Bookmark.fromJson(e as Map)).toList();
    }
    if (mounted) setState(() {});
  }

  void _initWc() {
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.bgDeep)
      ..setUserAgent(_kMobileUA)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() { _loading = true; _progress = p; });
        },
        onPageStarted: (url) {
          if (mounted) setState(() { _url = url; _loading = true; });
          _refreshNavButtons();
        },
        onPageFinished: (url) async {
          final title = await _wc.getTitle() ?? url;
          if (mounted) {
            setState(() {
              _url = url; _title = title; _loading = false;
            });
          }
          _refreshNavButtons();
          if (_adBlock) await _wc.runJavaScript(_kAdBlockJs);
          if (!_private && url != 'about:blank' && url.isNotEmpty) {
            _pushHistory(url, title);
          }
        },
        onWebResourceError: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onNavigationRequest: (req) {
          if (_adBlock && _isAdUrl(req.url)) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.initialUrl ?? _kHomePage));

    // Clear session on private-mode start
    if (_private) {
      WebViewCookieManager().clearCookies().ignore();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────
  bool _isAdUrl(String url) {
    try {
      final host = Uri.parse(url).host;
      return _kAdDomains.any((d) => host == d || host.endsWith('.$d'));
    } catch (_) {
      return false;
    }
  }

  String _resolveUrl(String input) {
    input = input.trim();
    if (input.isEmpty) return _kHomePage;
    if (input.startsWith('http://') || input.startsWith('https://')) {
      return input;
    }
    // Looks like a domain (contains dot, no spaces)
    final domainRx = RegExp(r'^[a-zA-Z0-9-]+(\.[a-zA-Z]{2,})(/.*)?$');
    if (domainRx.hasMatch(input) && !input.contains(' ')) {
      return 'https://$input';
    }
    // DuckDuckGo search — privacy by default
    return 'https://duckduckgo.com/?q=${Uri.encodeComponent(input)}';
  }

  void _navigate(String input) =>
      _wc.loadRequest(Uri.parse(_resolveUrl(input)));

  Future<void> _refreshNavButtons() async {
    final back = await _wc.canGoBack();
    final fwd  = await _wc.canGoForward();
    if (mounted) setState(() { _canBack = back; _canFwd = fwd; });
  }

  // ── History ──────────────────────────────────────────────────────
  void _pushHistory(String url, String title) {
    _history.removeWhere((h) => h.url == url);
    _history.insert(0, _HistItem(url, title, DateTime.now()));
    if (_history.length > 300) _history = _history.sublist(0, 300);
    _saveHistory();
  }

  void _clearHistory() {
    setState(() => _history.clear());
    _box?.put(_kKeyHistory, '[]');
  }

  void _saveHistory() =>
      _box?.put(_kKeyHistory,
          jsonEncode(_history.map((h) => h.toJson()).toList()));

  // ── Bookmarks ────────────────────────────────────────────────────
  bool get _isBookmarked => _bookmarks.any((b) => b.url == _url);

  void _toggleBookmark() {
    if (_isBookmarked) {
      setState(() => _bookmarks.removeWhere((b) => b.url == _url));
      _snack('Bookmark removed');
    } else {
      setState(() => _bookmarks.insert(0, _Bookmark(_url, _title)));
      _snack('⭐  Bookmarked!');
    }
    _box?.put(_kKeyBookmarks,
        jsonEncode(_bookmarks.map((b) => b.toJson()).toList()));
  }

  // ── Private mode ─────────────────────────────────────────────────
  Future<void> _togglePrivate() async {
    await WebViewCookieManager().clearCookies();
    await _wc.clearCache();
    await _wc.clearLocalStorage();
    setState(() => _private = !_private);
    _snack(_private
        ? '🕶️  Private ON — no history, cookies wiped'
        : '🌐  Private OFF — normal mode');
  }

  // ── Desktop mode ─────────────────────────────────────────────────
  Future<void> _toggleDesktop() async {
    setState(() => _desktop = !_desktop);
    await _wc.setUserAgent(_desktop ? _kDesktopUA : _kMobileUA);
    await _wc.reload();
    _snack(_desktop ? '🖥️  Desktop mode ON' : '📱  Mobile mode');
  }

  // ── Ad blocker ───────────────────────────────────────────────────
  void _toggleAdBlock() {
    setState(() => _adBlock = !_adBlock);
    _box?.put(_kKeyAdBlock, _adBlock.toString());
    _snack(_adBlock ? '🚫  Ad blocker ON' : '✅  Ad blocker OFF');
  }

  // ── Clear all data ───────────────────────────────────────────────
  Future<void> _clearAllData() async {
    await WebViewCookieManager().clearCookies();
    await _wc.clearCache();
    await _wc.clearLocalStorage();
    _clearHistory();
    _snack('🗑️  All browsing data cleared');
  }

  // ── Snackbar ─────────────────────────────────────────────────────
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      backgroundColor: AppTheme.bgCard,
    ));
  }

  // ── Dialogs / Sheets ─────────────────────────────────────────────
  void _openUrlBar() {
    final ctrl = TextEditingController(text: _url);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(
                  _private
                      ? Icons.visibility_off_rounded
                      : Icons.search_rounded,
                  color: _private
                      ? AppTheme.accentViolet
                      : Theme.of(ctx).colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _private ? 'Private Search' : 'Search or Enter URL',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'duckduckgo.com  or  search…',
                  hintStyle:
                      const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.bgSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear_rounded,
                        color: AppTheme.textSecondary, size: 16),
                    onPressed: () => ctrl.clear(),
                  ),
                ),
                onSubmitted: (v) {
                  Navigator.pop(ctx);
                  _navigate(v);
                },
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontFamily: 'Poppins')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _private
                          ? AppTheme.accentViolet
                          : Theme.of(ctx).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _navigate(ctrl.text);
                    },
                    child: const Text('Go',
                        style: TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _openMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _MenuSheet(
        isPrivate:    _private,
        isAdBlock:    _adBlock,
        isDesktop:    _desktop,
        isBookmarked: _isBookmarked,
        onPrivate:    () { Navigator.pop(ctx); _togglePrivate(); },
        onAdBlock:    () { Navigator.pop(ctx); _toggleAdBlock(); },
        onDesktop:    () { Navigator.pop(ctx); _toggleDesktop(); },
        onBookmark:   () { Navigator.pop(ctx); _toggleBookmark(); },
        onHistory:    () { Navigator.pop(ctx); _openHistory(); },
        onBookmarks:  () { Navigator.pop(ctx); _openBookmarks(); },
        onClearData:  () { Navigator.pop(ctx); _clearAllData(); },
        onCopyLink:   () {
          Navigator.pop(ctx);
          Clipboard.setData(ClipboardData(text: _url));
          _snack('🔗  Link copied');
        },
        onHome: () {
          Navigator.pop(ctx);
          _wc.loadRequest(Uri.parse(_kHomePage));
        },
      ),
    );
  }

  void _openHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _HistSheet(
        items: List.from(_history),
        onNavigate: (url) { Navigator.pop(ctx); _navigate(url); },
        onClear: () {
          Navigator.pop(ctx);
          _clearHistory();
          _snack('🗑️  History cleared');
        },
      ),
    );
  }

  void _openBookmarks() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInner) => _BookmarksSheet(
          bookmarks: _bookmarks,
          onNavigate: (url) { Navigator.pop(ctx); _navigate(url); },
          onDelete: (url) {
            setState(() => _bookmarks.removeWhere((b) => b.url == url));
            setInner(() {});
            _box?.put(_kKeyBookmarks,
                jsonEncode(_bookmarks.map((b) => b.toJson()).toList()));
          },
        ),
      ),
    );
  }

  // ── Dispose ──────────────────────────────────────────────────────
  @override
  void dispose() {
    if (_private) {
      WebViewCookieManager().clearCookies().ignore();
      _wc.clearCache().ignore();
      _wc.clearLocalStorage().ignore();
    }
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final accent = _private
        ? AppTheme.accentViolet
        : Theme.of(context).colorScheme.primary;
    final barBg = _private ? const Color(0xFF130820) : AppTheme.bgDeep;
    final isSecure = _url.startsWith('https://');

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: barBg,
        elevation: 0,
        leadingWidth: 44,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: _canBack ? AppTheme.textPrimary : AppTheme.textSecondary,
            size: 18,
          ),
          onPressed: _canBack ? () => _wc.goBack() : null,
          tooltip: 'Back',
        ),
        title: _UrlBarWidget(
          url:       _url,
          isSecure:  isSecure,
          isPrivate: _private,
          accent:    accent,
          onTap:     _openUrlBar,
        ),
        actions: [
          _loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white38),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh_rounded,
                      color: AppTheme.textSecondary, size: 20),
                  onPressed: () => _wc.reload(),
                  tooltip: 'Reload',
                ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded,
                color: AppTheme.textSecondary, size: 20),
            onPressed: _openMenu,
            tooltip: 'Menu',
          ),
        ],
        bottom: _loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(accent),
                  minHeight: 3,
                ),
              )
            : null,
      ),
      body: Stack(
        children: [
          // ── Main WebView ──
          WebViewWidget(controller: _wc),

          // ── Private mode: subtle violet tint ──
          if (_private)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                    color: AppTheme.accentViolet.withOpacity(0.04)),
              ),
            ),

          // ── Private mode pill ──
          if (_private)
            Positioned(
              bottom: _canFwd ? 70 : 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.accentViolet.withOpacity(0.88),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.accentViolet.withOpacity(0.3),
                          blurRadius: 12),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_off_rounded,
                          size: 13, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Private Mode  ·  No History  ·  Cookies Wiped',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Forward FAB ──
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: 16,
            right: _canFwd ? 16 : -60,
            child: FloatingActionButton.small(
              backgroundColor: AppTheme.bgCard.withOpacity(0.95),
              elevation: 4,
              onPressed: _canFwd ? () => _wc.goForward() : null,
              tooltip: 'Forward',
              child:
                  Icon(Icons.arrow_forward_ios_rounded, size: 16, color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ─── URL Bar Widget ───────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════
class _UrlBarWidget extends StatelessWidget {
  final String url;
  final bool isSecure, isPrivate;
  final Color accent;
  final VoidCallback onTap;

  const _UrlBarWidget({
    required this.url, required this.isSecure, required this.isPrivate,
    required this.accent, required this.onTap,
  });

  String get _displayHost {
    if (url.isEmpty || url == 'about:blank') return 'Search or enter URL…';
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isPrivate
                ? AppTheme.accentViolet.withOpacity(0.5)
                : Colors.white.withOpacity(0.07),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isPrivate
                  ? Icons.visibility_off_rounded
                  : (isSecure ? Icons.lock_rounded : Icons.lock_open_rounded),
              size: 12,
              color: isPrivate
                  ? AppTheme.accentViolet
                  : (isSecure
                      ? Colors.greenAccent.shade400
                      : Colors.orangeAccent),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _displayHost,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                  overflow: TextOverflow.ellipsis,
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ─── Menu Bottom Sheet ────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════
class _MenuSheet extends StatelessWidget {
  final bool isPrivate, isAdBlock, isDesktop, isBookmarked;
  final VoidCallback onPrivate, onAdBlock, onDesktop, onBookmark,
      onHistory, onBookmarks, onClearData, onCopyLink, onHome;

  const _MenuSheet({
    required this.isPrivate, required this.isAdBlock,
    required this.isDesktop, required this.isBookmarked,
    required this.onPrivate, required this.onAdBlock,
    required this.onDesktop, required this.onBookmark,
    required this.onHistory, required this.onBookmarks,
    required this.onClearData, required this.onCopyLink,
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          // ── Quick-toggle row ──
          Row(children: [
            _Toggle(
              icon: isPrivate
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              label: 'Private',
              active: isPrivate,
              color: AppTheme.accentViolet,
              onTap: onPrivate,
            ),
            const SizedBox(width: 10),
            _Toggle(
              icon: Icons.block_rounded,
              label: 'Ad Block',
              active: isAdBlock,
              color: Colors.redAccent,
              onTap: onAdBlock,
            ),
            const SizedBox(width: 10),
            _Toggle(
              icon: Icons.computer_rounded,
              label: 'Desktop',
              active: isDesktop,
              color: accent,
              onTap: onDesktop,
            ),
            const SizedBox(width: 10),
            _Toggle(
              icon: isBookmarked ? Icons.star_rounded : Icons.star_border_rounded,
              label: 'Bookmark',
              active: isBookmarked,
              color: Colors.amber,
              onTap: onBookmark,
            ),
          ]),

          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 4),

          // ── Action list ──
          _MenuTile(icon: Icons.home_rounded,     label: 'Home',             onTap: onHome),
          _MenuTile(icon: Icons.history_rounded,  label: 'History',          onTap: onHistory),
          _MenuTile(icon: Icons.bookmarks_rounded,label: 'Bookmarks',        onTap: onBookmarks),
          _MenuTile(icon: Icons.copy_rounded,     label: 'Copy Link',        onTap: onCopyLink),
          _MenuTile(
            icon: Icons.delete_sweep_rounded,
            label: 'Clear Browsing Data',
            onTap: onClearData,
            color: Colors.redAccent,
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _Toggle({
    required this.icon, required this.label, required this.active,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = active ? color : AppTheme.textSecondary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.12) : AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? color.withOpacity(0.45)
                  : Colors.white.withOpacity(0.06),
            ),
          ),
          child: Column(children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: c)),
          ]),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _MenuTile(
      {required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textPrimary;
    return ListTile(
      leading: Icon(icon, color: c, size: 20),
      title: Text(label,
          style: TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: c)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      dense: true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ─── History Sheet ────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════
class _HistSheet extends StatelessWidget {
  final List<_HistItem> items;
  final ValueChanged<String> onNavigate;
  final VoidCallback onClear;

  const _HistSheet({
      required this.items, required this.onNavigate, required this.onClear});

  String _rel(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1)   return '${diff.inMinutes}m ago';
    if (diff.inDays < 1)    return '${diff.inHours}h ago';
    if (diff.inDays < 7)    return '${diff.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      minChildSize: 0.3,
      builder: (_, sc) => Column(
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              const Icon(Icons.history_rounded, color: AppTheme.textPrimary),
              const SizedBox(width: 8),
              const Text('History',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              const Spacer(),
              if (items.isNotEmpty)
                TextButton(
                  onPressed: onClear,
                  child: const Text('Clear All',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontFamily: 'Poppins',
                          fontSize: 12)),
                ),
            ]),
          ),
          const Divider(color: Colors.white12),

          // ── List ──
          if (items.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No history in this session',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontFamily: 'Poppins')),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: sc,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final h = items[i];
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppTheme.bgSurface,
                      radius: 15,
                      child: Icon(Icons.public_rounded,
                          size: 14, color: AppTheme.textSecondary),
                    ),
                    title: Text(h.title,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: AppTheme.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(h.url,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: Text(_rel(h.time),
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            color: AppTheme.textSecondary)),
                    onTap: () => onNavigate(h.url),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ─── Bookmarks Sheet ──────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════
class _BookmarksSheet extends StatelessWidget {
  final List<_Bookmark> bookmarks;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onDelete;

  const _BookmarksSheet({
      required this.bookmarks, required this.onNavigate, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      minChildSize: 0.3,
      builder: (_, sc) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              const Icon(Icons.bookmarks_rounded, color: Colors.amber),
              const SizedBox(width: 8),
              const Text('Bookmarks',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
            ]),
          ),
          const Divider(color: Colors.white12),

          if (bookmarks.isEmpty)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bookmarks_outlined,
                        size: 40, color: Colors.white12),
                    SizedBox(height: 12),
                    Text('No bookmarks yet',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontFamily: 'Poppins')),
                    SizedBox(height: 4),
                    Text('Tap  ⋮  →  Bookmark  to save sites',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontFamily: 'Poppins',
                            fontSize: 11)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: sc,
                itemCount: bookmarks.length,
                itemBuilder: (_, i) {
                  final b = bookmarks[i];
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x33FFB300),
                      radius: 15,
                      child: Icon(Icons.star_rounded,
                          size: 15, color: Colors.amber),
                    ),
                    title: Text(b.title,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: AppTheme.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(b.url,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent, size: 18),
                      onPressed: () => onDelete(b.url),
                    ),
                    onTap: () => onNavigate(b.url),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
