// lib/features/downloader/downloader_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../core/theme/app_theme.dart';
import 'models/download_item.dart';
import 'download_history_service.dart';
import 'downloader_service.dart';

class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({super.key});

  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen>
    with TickerProviderStateMixin {
  final _svc     = UniversalDownloaderService.instance;
  final _history = DownloadHistoryService.instance;
  final _urlCtrl = TextEditingController();
  late TabController _tabCtrl;

  bool      _analyzing  = false;
  String?   _clipUrl;
  bool      _hasClipUrl = false;
  String?   _errorMsg;
  VideoInfo? _pendingInfo;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _checkClipboard();
    _setupSharingIntent();
    _initNotifChannel();
  }

  void _setupSharingIntent() {
    // URLs shared from other apps (while app is running)
    ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      for (final f in files) {
        final text = f.path ?? '';
        if (text.startsWith('http')) _handleIncomingUrl(text);
      }
    });

    // URL shared to open the app
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      for (final f in files) {
        final text = f.path ?? '';
        if (text.startsWith('http')) _handleIncomingUrl(text);
      }
    });
  }

  void _handleIncomingUrl(String url) {
    if (!mounted || url.isEmpty) return;
    setState(() { _urlCtrl.text = url; });
    _analyze(url);
  }

  Future<void> _initNotifChannel() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
        'downloader', 'Downloads',
        description: 'BeatFlow download notifications',
        importance : Importance.high,
      ));
    } catch (_) {}
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim() ?? '';
      if (_isUrl(text) && mounted) {
        setState(() { _hasClipUrl = true; _clipUrl = text; });
      }
    } catch (_) {}
  }

  bool _isUrl(String t) => t.startsWith('http://') || t.startsWith('https://');

  // ── Analyze URL ────────────────────────────────────────────────
  Future<void> _analyze([String? overrideUrl]) async {
    final input = (overrideUrl ?? _urlCtrl.text).trim();
    if (input.isEmpty) return;
    if (!_isUrl(input)) {
      setState(() => _errorMsg =
          'Sahi URL daalo (http/https se shuru honi chahiye)');
      return;
    }

    setState(() {
      _analyzing   = true;
      _errorMsg    = null;
      _pendingInfo = null;
    });

    try {
      final info = await _svc.fetchVideoInfo(input);
      if (!mounted) return;
      setState(() { _pendingInfo = info; _analyzing = false; });
      _showQualitySheet(input, info);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg  = e.toString().replaceFirst('Exception: ', '');
        _analyzing = false;
      });
    }
  }

  // ── Quality bottom sheet ────────────────────────────────────────
  void _showQualitySheet(String url, VideoInfo info) {
    showModalBottomSheet(
      context        : context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _QualitySheet(
        info  : info,
        accent: Theme.of(context).colorScheme.primary,
        onSelect: (quality) async {
          Navigator.pop(context);
          try {
            await _svc.startDownload(
              originalUrl: url, info: info, quality: quality);
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content : Text('Error: $e'),
              behavior: SnackBarBehavior.floating,
            ));
            return;
          }
          if (!mounted) return;
          setState(() { _urlCtrl.clear(); _pendingInfo = null; _hasClipUrl = false; });
          _tabCtrl.animateTo(0);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content : Text('⬇️ Download shuru! "${info.title.substring(0, info.title.length.clamp(0, 30))}"'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ));
        },
      ),
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation      : 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [accent, accent.withOpacity(0.55)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.download_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Video Downloader',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
                fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        ]),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor  : Colors.white,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor : Colors.transparent,
          indicator: BoxDecoration(
            gradient: LinearGradient(
                colors: [accent, accent.withOpacity(0.65)]),
            borderRadius: BorderRadius.circular(10),
          ),
          labelStyle: const TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w600, fontSize: 12),
          tabs: const [
            Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [Icon(Icons.download_rounded, size: 15),
                  SizedBox(width: 5), Text('Downloads')])),
            Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [Icon(Icons.history_rounded, size: 15),
                  SizedBox(width: 5), Text('History')])),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildDownloadTab(accent),
          _buildHistoryTab(accent),
        ],
      ),
    );
  }

  // ── Tab 1: Download ─────────────────────────────────────────────
  Widget _buildDownloadTab(Color accent) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _buildPlatformChips(accent),
        const SizedBox(height: 14),
        if (_hasClipUrl && _clipUrl != null) _buildClipSuggestion(accent),
        _buildUrlInput(accent),
        if (_errorMsg != null) ...[
          const SizedBox(height: 10),
          _buildErrorCard(),
        ],
        const SizedBox(height: 14),
        _buildActiveDownloads(accent),
      ]),
    );
  }

  Widget _buildPlatformChips(Color accent) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          SourcePlatform.youtube, SourcePlatform.instagram,
          SourcePlatform.tiktok, SourcePlatform.twitter,
          SourcePlatform.facebook, SourcePlatform.reddit,
          SourcePlatform.vimeo, SourcePlatform.direct,
        ].map((p) => Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withOpacity(0.25)),
          ),
          child: Text('${p.emoji} ${p.displayName}',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                color: accent.withOpacity(0.9), fontWeight: FontWeight.w500)),
        )).toList(),
      ),
    );
  }

  Widget _buildClipSuggestion(Color accent) {
    return GestureDetector(
      onTap: () { _urlCtrl.text = _clipUrl!; _analyze(_clipUrl!); },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withOpacity(0.35)),
        ),
        child: Row(children: [
          Icon(Icons.content_paste_rounded, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📋 Clipboard mein URL mili!',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: FontWeight.w700, color: accent)),
              const SizedBox(height: 2),
              Text(_clipUrl!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: AppTheme.textSecondary)),
            ],
          )),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [accent, accent.withOpacity(0.7)]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Download', style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ]),
      ),
    );
  }

  Widget _buildUrlInput(Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _urlCtrl,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText : 'YouTube, Instagram, TikTok, ya koi bhi URL...',
                hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    color: AppTheme.textSecondary),
                filled     : true,
                fillColor  : Colors.white.withOpacity(0.04),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.white12)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.white12)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: accent, width: 1.5)),
                suffixIcon: _urlCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: AppTheme.textSecondary, size: 18),
                        onPressed: () => setState(() {
                          _urlCtrl.clear();
                          _errorMsg = null;
                        }),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() => _errorMsg = null),
              onSubmitted: (_) => _analyze(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final data = await Clipboard.getData('text/plain');
              if (data?.text != null && mounted) {
                setState(() => _urlCtrl.text = data!.text!.trim());
              }
            },
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withOpacity(0.3)),
              ),
              child: Icon(Icons.content_paste_rounded, color: accent, size: 20),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _analyzing ? null : () => _analyze(),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 4,
            ),
            child: _analyzing
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('Video info le raha hoon...',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    ])
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_rounded, size: 20),
                      SizedBox(width: 8),
                      Text('Analyze & Download',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline_rounded,
            color: Colors.redAccent, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(_errorMsg ?? '',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
              color: Colors.redAccent))),
      ]),
    );
  }

  Widget _buildActiveDownloads(Color accent) {
    return StreamBuilder<DownloadItem>(
      stream: _svc.progressStream,
      builder: (_, snapshot) {
        final active = _history.getActive();
        if (active.isEmpty) return _buildEmptyActiveState(accent);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⬇️ Active Downloads',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent.withOpacity(0.9))),
            const SizedBox(height: 8),
            ...active.map((item) => _DownloadProgressCard(
              item    : item,
              accent  : accent,
              onCancel: () {
                _svc.cancelDownload(item.id);
                setState(() {});
              },
            )),
          ],
        );
      },
    );
  }

  Widget _buildEmptyActiveState(Color accent) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.15)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.download_rounded, color: accent.withOpacity(0.35), size: 48),
        const SizedBox(height: 14),
        const Text('URL paste karo, ya dusre app se share karo',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary)),
        const SizedBox(height: 8),
        Text('Supported: YouTube, Instagram, TikTok, Twitter, Reddit...',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
              color: AppTheme.textSecondary.withOpacity(0.7))),
      ]),
    );
  }

  // ── Tab 2: History ──────────────────────────────────────────────
  Widget _buildHistoryTab(Color accent) {
    return StreamBuilder<DownloadItem>(
      stream: _svc.progressStream,
      builder: (_, __) {
        final completed = _history.getCompleted();
        if (completed.isEmpty) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 80, height: 80,
              decoration: BoxDecoration(
                  color: accent.withOpacity(0.10), shape: BoxShape.circle),
              child: Icon(Icons.download_done_rounded,
                  color: accent.withOpacity(0.4), size: 40)),
            const SizedBox(height: 16),
            const Text('Koi download nahi abhi',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                  fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            const SizedBox(height: 6),
            const Text('Videos download karoge, yahan dikhenge!',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: AppTheme.textSecondary)),
          ]));
        }

        return ListView.builder(
          padding   : const EdgeInsets.all(12),
          itemCount : completed.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Align(
                alignment: Alignment.topRight,
                child: TextButton.icon(
                  onPressed: () => _confirmClearAll(accent),
                  icon : const Icon(Icons.delete_sweep_rounded,
                      color: Colors.redAccent, size: 16),
                  label: const Text('Saab delete karo',
                    style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 12, color: Colors.redAccent)),
                ),
              );
            }
            final item = completed[i - 1];
            return _CompletedDownloadCard(
              key     : ValueKey(item.id),
              item    : item,
              accent  : accent,
              onDelete: () {
                _history.deleteItem(item.id);
                if (item.filePath.isNotEmpty) {
                  try { File(item.filePath).delete(); } catch (_) {}
                }
                setState(() {});
              },
              onShare: () {
                if (item.filePath.isNotEmpty) {
                  Share.shareXFiles([XFile(item.filePath)], text: item.title);
                }
              },
              onOpen  : () {
                if (item.filePath.isNotEmpty) OpenFile.open(item.filePath);
              },
              onRetry : item.status == DownloadStatus.failed
                  ? () {
                      _svc.retryDownload(item);
                      setState(() {});
                      _tabCtrl.animateTo(0);
                    }
                  : null,
            );
          },
        );
      },
    );
  }

  void _confirmClearAll(Color accent) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Saab clear karein?',
          style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        content: const Text(
          'Saari download history delete ho jayegi.\n'
          'Files disk pe rahenge.',
          style: TextStyle(fontFamily: 'Poppins',
              fontSize: 13, color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
              style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              _history.clearAll();
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Delete Karo',
                style: TextStyle(color: Colors.redAccent,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Quality Selection Bottom Sheet
// ═══════════════════════════════════════════════════════════════════

class _QualitySheet extends StatelessWidget {
  final VideoInfo info;
  final Color accent;
  final void Function(DownloadQualityOption) onSelect;

  const _QualitySheet({
    required this.info,
    required this.accent,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 550),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Container(width: 40, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Thumbnail + title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: info.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: info.thumbnailUrl!,
                        width: 70, height: 50, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _platformBadge(),
                      )
                    : _platformBadge(),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text(info.platform.emoji,
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    Text(info.platform.displayName,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                          color: accent.withOpacity(0.85),
                          fontWeight: FontWeight.w600)),
                    if (info.author.isNotEmpty &&
                        info.author != info.platform.displayName) ...[
                      Text(' · ${info.author}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                            color: AppTheme.textSecondary)),
                    ],
                  ]),
                ],
              )),
            ]),
          ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Quality select karo:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 8),

          // Quality options
          Flexible(
            child: ListView.builder(
              shrinkWrap  : true,
              padding     : const EdgeInsets.symmetric(horizontal: 16),
              itemCount   : info.qualities.length,
              itemBuilder : (_, i) {
                final q = info.qualities[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onSelect(q),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: (q.isAudioOnly
                                  ? Colors.orange : accent).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              q.isAudioOnly
                                  ? Icons.audiotrack_rounded
                                  : Icons.videocam_rounded,
                              color: q.isAudioOnly ? Colors.orange : accent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(q.label,
                                style: const TextStyle(
                                    fontFamily: 'Poppins', fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary)),
                              Text(
                                q.isAudioOnly ? 'Audio only · ${q.fileExtension.toUpperCase()}'
                                    : 'Video · ${q.fileExtension.toUpperCase()}',
                                style: const TextStyle(fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: AppTheme.textSecondary)),
                            ],
                          )),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                accent, accent.withOpacity(0.7)
                              ]),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('Download',
                              style: TextStyle(fontFamily: 'Poppins',
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Info footer
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Row(children: [
              Icon(Icons.folder_rounded,
                  color: AppTheme.textSecondary.withOpacity(0.6), size: 14),
              const SizedBox(width: 6),
              const Expanded(child: Text(
                'Save hoga: /storage/Download/BeatFlow/',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: AppTheme.textSecondary),
              )),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _platformBadge() {
    return Container(
      width: 70, height: 50,
      decoration: BoxDecoration(
        color: accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(child: Text(info.platform.emoji,
          style: const TextStyle(fontSize: 24))),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Active Download Progress Card
// ═══════════════════════════════════════════════════════════════════

class _DownloadProgressCard extends StatelessWidget {
  final DownloadItem item;
  final Color accent;
  final VoidCallback onCancel;

  const _DownloadProgressCard({
    required this.item,
    required this.accent,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (item.progress * 100).toStringAsFixed(0);
    final downloaded = _fmtBytes(item.downloadedBytes);
    final total      = item.fileSizeBytes > 0
        ? _fmtBytes(item.fileSizeBytes) : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title row
        Row(children: [
          Text(item.platform.emoji,
              style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Text(item.title,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
          GestureDetector(
            onTap: onCancel,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.redAccent, size: 14),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(item.qualityLabel,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
              color: AppTheme.textSecondary)),

        const SizedBox(height: 10),

        // Status chip
        _StatusChip(status: item.status, accent: accent),

        const SizedBox(height: 8),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: item.status == DownloadStatus.preparing
                ? null : item.progress.clamp(0.0, 1.0),
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
            minHeight: 5,
          ),
        ),

        const SizedBox(height: 6),

        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$downloaded / $total',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                color: AppTheme.textSecondary)),
          if (item.status == DownloadStatus.downloading)
            Text('$pct%',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w700, color: accent)),
        ]),
      ]),
    );
  }

  String _fmtBytes(int b) {
    if (b <= 0) return '0 B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ═══════════════════════════════════════════════════════════════════
// Completed / Failed / Cancelled Download Card
// ═══════════════════════════════════════════════════════════════════

class _CompletedDownloadCard extends StatelessWidget {
  final DownloadItem item;
  final Color accent;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onOpen;
  final VoidCallback? onRetry;

  const _CompletedDownloadCard({
    super.key,
    required this.item,
    required this.accent,
    required this.onDelete,
    required this.onShare,
    required this.onOpen,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = item.completedAt != null
        ? _fmtTime(item.completedAt!) : '';
    final sizeStr = item.fileSizeBytes > 0
        ? _fmtBytes(item.fileSizeBytes) : '';

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_rounded,
            color: Colors.redAccent, size: 24),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Title row
          Row(children: [
            Text(item.platform.emoji,
                style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text(item.title,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary))),
            const SizedBox(width: 8),
            _StatusChip(status: item.status, accent: accent),
          ]),

          const SizedBox(height: 6),

          // Meta info
          Row(children: [
            if (item.qualityLabel.isNotEmpty) ...[
              const Icon(Icons.hd_rounded,
                  color: AppTheme.textSecondary, size: 13),
              const SizedBox(width: 4),
              Text(item.qualityLabel,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: AppTheme.textSecondary)),
              const SizedBox(width: 10),
            ],
            if (sizeStr.isNotEmpty) ...[
              const Icon(Icons.storage_rounded,
                  color: AppTheme.textSecondary, size: 13),
              const SizedBox(width: 4),
              Text(sizeStr,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: AppTheme.textSecondary)),
              const SizedBox(width: 10),
            ],
            if (timeStr.isNotEmpty) ...[
              const Icon(Icons.access_time_rounded,
                  color: AppTheme.textSecondary, size: 13),
              const SizedBox(width: 4),
              Text(timeStr,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: AppTheme.textSecondary)),
            ],
          ]),

          // Error message
          if (item.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(item.errorMessage!,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: Colors.redAccent)),
          ],

          const SizedBox(height: 10),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 10),

          // Action buttons
          Row(children: [
            if (item.status == DownloadStatus.completed) ...[
              _ActionBtn(
                icon : Icons.folder_open_rounded,
                label: 'Open',
                color: accent,
                onTap: onOpen,
              ),
              const SizedBox(width: 8),
              _ActionBtn(
                icon : Icons.share_rounded,
                label: 'Share',
                color: const Color(0xFF06B6D4),
                onTap: onShare,
              ),
            ] else if (onRetry != null) ...[
              _ActionBtn(
                icon : Icons.refresh_rounded,
                label: 'Retry',
                color: Colors.orange,
                onTap: onRetry!,
              ),
            ],
            const Spacer(),
            _ActionBtn(
              icon : Icons.delete_outline_rounded,
              label: 'Delete',
              color: Colors.redAccent,
              onTap: onDelete,
            ),
          ]),
        ]),
      ),
    );
  }

  String _fmtBytes(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _fmtTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Abhi';
    if (diff.inHours < 1) return '${diff.inMinutes}m pehle';
    if (diff.inDays < 1) return '${diff.inHours}h pehle';
    return '${dt.day}/${dt.month}';
  }
}

// ── Small helper widgets ───────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final DownloadStatus status;
  final Color accent;
  const _StatusChip({required this.status, required this.accent});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      DownloadStatus.completed   => ('✅ Done',       const Color(0xFF10B981)),
      DownloadStatus.downloading => ('⬇️ Downloading', accent),
      DownloadStatus.preparing   => ('⏳ Preparing',   Colors.orange),
      DownloadStatus.pending     => ('🕐 Queue mein', Colors.blueGrey),
      DownloadStatus.failed      => ('❌ Failed',      Colors.redAccent),
      DownloadStatus.cancelled   => ('🚫 Cancelled',  Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
            fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
              fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }
}
