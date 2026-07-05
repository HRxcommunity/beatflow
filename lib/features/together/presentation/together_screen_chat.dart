// ╔══════════════════════════════════════════════════════════════╗
// ║  CHAT PANEL with Media, Emoji & YouTube cards               ║
// ╚══════════════════════════════════════════════════════════════╝

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import '../domain/entities/session_entity.dart';
import '../bloc/together_bloc.dart';
import '../services/together_session_service.dart';
import '../../youtube/youtube_search_sheet.dart';
import '../../youtube/youtube_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../service_locator.dart';

class TogetherChatPanel extends StatefulWidget {
  final SessionEntity session;
  final Color accent;
  final String currentUid;
  final bool isOwner;
  final void Function(int count)? onMessageCountChanged;

  const TogetherChatPanel({
    super.key,
    required this.session,
    required this.accent,
    required this.currentUid,
    required this.isOwner,
    this.onMessageCountChanged,
  });

  @override
  State<TogetherChatPanel> createState() => _TogetherChatPanelState();
}

class _TogetherChatPanelState extends State<TogetherChatPanel> {
  final _ctrl       = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode  = FocusNode();
  bool _showEmoji   = false;

  // FIX: Cache stream so parent rebuilds don't recreate it (caused msgs disappearing)
  late Stream<List<SessionChatMessage>> _chatStream;
  List<SessionChatMessage> _messages = [];
  int _lastMsgCount = 0;

  @override
  void initState() {
    super.initState();
    // Create stream once and cache — never recreate on rebuild
    _chatStream = ServiceLocator.instance
        .togetherSessionService
        .chatStream(widget.session.sessionId);
    _focusNode.addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void didUpdateWidget(TogetherChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // No-op: messages now come from StreamBuilder, not widget prop
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // Keyboard opened via text field tap — close emoji picker & scroll down
  void _onFocusChange() {
    if (_focusNode.hasFocus && _showEmoji) {
      setState(() => _showEmoji = false);
    }
    if (_focusNode.hasFocus) {
      // Give keyboard animation time to finish then scroll
      Future.delayed(const Duration(milliseconds: 350), _scrollToBottom);
    }
  }

  /// Instant jump — used on first open when animation isn't needed
  void _jumpToBottom() {
    if (_scrollCtrl.hasClients &&
        _scrollCtrl.position.maxScrollExtent > 0) {
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    }
    _lastMsgCount = _messages.length;
  }

  /// Animated scroll — used when new message arrives or keyboard opens
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  void _sendText() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    context.read<TogetherBloc>().add(TogetherSendChat(text));
    _ctrl.clear();
    _scrollToBottom();
  }

  void _sendEmoji(String emoji) {
    context.read<TogetherBloc>().add(
        TogetherSendChat(emoji, type: ChatMessageType.emoji));
    _scrollToBottom();
  }

  void _toggleEmoji() {
    if (!_showEmoji) {
      // Dismiss keyboard before showing emoji picker
      _focusNode.unfocus();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) setState(() => _showEmoji = true);
        Future.delayed(const Duration(milliseconds: 50), _scrollToBottom);
      });
    } else {
      setState(() => _showEmoji = false);
      // Re-open keyboard
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    return BlocListener<TogetherBloc, TogetherState>(
      listenWhen: (p, c) => c.error != null && p.error != c.error,
      listener: (ctx, state) {
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text(state.error!)),
              ]),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      },
      child: AnimatedPadding(
        // FIX: Animate the bottom padding to match keyboard height.
        // This is the core of WhatsApp-style "chat lifts with keyboard".
        padding: EdgeInsets.only(bottom: _showEmoji ? 0 : keyboardHeight),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Column(
          children: [
            // ── Message list — Fix 1: sub-collection stream ──────
            Expanded(
              child: StreamBuilder<List<SessionChatMessage>>(
                stream: _chatStream,
                builder: (ctx, snapshot) {
                  if (snapshot.hasData) {
                    final newMsgs = snapshot.data!;
                    // Only scroll if new message arrived
                    if (newMsgs.length > _lastMsgCount) {
                      _lastMsgCount = newMsgs.length;
                      // Schedule scroll after frame (safe inside build)
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _scrollToBottom());
                      // Notify parent of new message count for badge
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        widget.onMessageCountChanged?.call(newMsgs.length);
                      });
                    }
                    // Update local messages list — always use latest snapshot
                    _messages = newMsgs;
                  }
                  // Use snapshot data directly if available, else fallback to cached
                  final msgs = snapshot.data ?? _messages;
                  return msgs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('💬',
                              style: TextStyle(
                                  fontSize: 40,
                                  color: Colors.white.withValues(alpha: 0.2))),
                          const SizedBox(height: 10),
                          Text(
                            'No messages yet.\nSay hi! 👋',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 14,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      // reverse: false with proper scroll controller
                      // padding bottom gives space for last bubble above input bar
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                      itemCount: msgs.length,
                      itemBuilder: (_, i) => _ChatBubble(
                        msg:     msgs[i],
                        isMe:    msgs[i].uid == widget.currentUid,
                        accent:  widget.accent,
                        isOwner: widget.isOwner,
                        onPlayYt: (YoutubeTrack track) {
                          if (!widget.isOwner) return;
                          context.read<TogetherBloc>()
                              .add(TogetherPlayYoutube(track));
                        },
                      ),
                    );
                },
              ),
            ),

            // ── Emoji picker ───────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => SizeTransition(
                sizeFactor: anim,
                axisAlignment: -1,
                child: child,
              ),
              child: _showEmoji
                  ? SizedBox(
                      key: const ValueKey('emoji'),
                      height: 280,
                      child: EmojiPicker(
                        onEmojiSelected: (_, emoji) =>
                            _sendEmoji(emoji.emoji),
                        config: Config(
                          emojiViewConfig: EmojiViewConfig(
                            columns: 8,
                            emojiSizeMax: 28.0 *
                                (foundation.defaultTargetPlatform ==
                                        TargetPlatform.iOS
                                    ? 1.2
                                    : 1.0),
                            backgroundColor: AppTheme.bgCard,
                          ),
                          categoryViewConfig: const CategoryViewConfig(
                            backgroundColor: AppTheme.bgCard,
                            indicatorColor: Color(0xFF6C63FF),
                            iconColorSelected: Color(0xFF6C63FF),
                          ),
                          bottomActionBarConfig: const BottomActionBarConfig(
                            backgroundColor: AppTheme.bgCard,
                            buttonIconColor: Colors.white54,
                            enabled: true,
                          ),
                          searchViewConfig: const SearchViewConfig(
                            backgroundColor: AppTheme.bgCard,
                            buttonIconColor: Colors.white54,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('no-emoji')),
            ),

            // ── Input bar ───────────────────────────────────────────
            BlocBuilder<TogetherBloc, TogetherState>(
              buildWhen: (p, c) => p.mediaUploading != c.mediaUploading,
              builder: (ctx, state) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    border: Border(
                      top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.07), width: 1),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.mediaUploading)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white54),
                              ),
                              const SizedBox(width: 8),
                              Text('Uploading...',
                                  style: TextStyle(
                                      color: widget.accent.withValues(alpha: 0.8),
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          // Emoji toggle
                          _IconBtn(
                            icon: _showEmoji
                                ? Icons.keyboard_rounded
                                : Icons.emoji_emotions_outlined,
                            color: _showEmoji
                                ? widget.accent
                                : Colors.white54,
                            onTap: _toggleEmoji,
                          ),
                          const SizedBox(width: 4),
                          _IconBtn(
                            icon: Icons.photo_rounded,
                            color: Colors.white54,
                            onTap: () => ctx
                                .read<TogetherBloc>()
                                .add(TogetherSendImage()),
                          ),
                          const SizedBox(width: 4),
                          _IconBtn(
                            icon: Icons.attach_file_rounded,
                            color: Colors.white54,
                            onTap: () => ctx
                                .read<TogetherBloc>()
                                .add(TogetherSendFile()),
                          ),
                          const SizedBox(width: 4),
                          _IconBtn(
                            icon: Icons.smart_display_rounded,
                            color: const Color(0xFFFF0000),
                            onTap: () {
                              _focusNode.unfocus();
                              setState(() => _showEmoji = false);
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: Colors.transparent,
                                isScrollControlled: true,
                                builder: (_) => BlocProvider.value(
                                  value: ctx.read<TogetherBloc>(),
                                  child: YoutubeSearchSheet(
                                      isOwner: widget.isOwner),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 6),
                          // Text field
                          Expanded(
                            child: TextField(
                              controller: _ctrl,
                              focusNode: _focusNode,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary, fontSize: 14),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendText(),
                              decoration: InputDecoration(
                                hintText: 'Message...',
                                hintStyle: TextStyle(
                                    color:
                                        AppTheme.textSecondary.withValues(alpha: 0.5),
                                    fontSize: 14),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.06),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Send button
                          GestureDetector(
                            onTap: _sendText,
                            child: Container(
                              width: 42, height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [
                                  widget.accent,
                                  widget.accent.withValues(alpha: 0.75),
                                ]),
                              ),
                              child: const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 19),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chat Bubble ───────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final SessionChatMessage msg;
  final bool isMe;
  final Color accent;
  final bool isOwner;
  final void Function(YoutubeTrack track) onPlayYt;

  const _ChatBubble({
    required this.msg,
    required this.isMe,
    required this.accent,
    required this.isOwner,
    required this.onPlayYt,
  });

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(msg.timestampMs);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    switch (msg.type) {
      case ChatMessageType.image:
        return _MediaBubble(
          msg: msg, isMe: isMe, accent: accent, timeStr: timeStr, isImage: true);
      case ChatMessageType.file:
        return _FileBubble(
            msg: msg, isMe: isMe, accent: accent, timeStr: timeStr);
      case ChatMessageType.youtubeTrack:
        return _YoutubeBubble(
          msg:      msg,
          isMe:     isMe,
          accent:   accent,
          timeStr:  timeStr,
          isOwner:  isOwner,
          onPlay:   onPlayYt,
        );
      case ChatMessageType.emoji:
        return _EmojiBubble(msg: msg, isMe: isMe, timeStr: timeStr);
      default:
        return _TextBubble(msg: msg, isMe: isMe, accent: accent, timeStr: timeStr);
    }
  }
}

// Text bubble
class _TextBubble extends StatelessWidget {
  final SessionChatMessage msg;
  final bool isMe;
  final Color accent;
  final String timeStr;
  const _TextBubble({required this.msg, required this.isMe,
      required this.accent, required this.timeStr});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _Avatar(name: msg.displayName, color: AppTheme.accentCyan),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Text(msg.displayName,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.45),
                            fontWeight: FontWeight.w500)),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe
                        ? accent.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(16),
                      topRight:    const Radius.circular(16),
                      bottomLeft:  Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  child: Text(msg.text,
                      style: TextStyle(
                          color: isMe ? Colors.white : AppTheme.textPrimary,
                          fontSize: 14, height: 1.4)),
                ),
                const SizedBox(height: 2),
                Text(timeStr,
                    style: TextStyle(
                        fontSize: 10, color: Colors.white.withValues(alpha: 0.3))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Emoji bubble (large, no bubble background)
class _EmojiBubble extends StatelessWidget {
  final SessionChatMessage msg;
  final bool isMe;
  final String timeStr;
  const _EmojiBubble(
      {required this.msg, required this.isMe, required this.timeStr});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _Avatar(name: msg.displayName, color: AppTheme.accentCyan),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Text(msg.displayName,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.45),
                          fontWeight: FontWeight.w500)),
                Text(msg.text, style: const TextStyle(fontSize: 36)),
                Text(timeStr,
                    style: TextStyle(
                        fontSize: 10, color: Colors.white.withValues(alpha: 0.3))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Image bubble
class _MediaBubble extends StatelessWidget {
  final SessionChatMessage msg;
  final bool isMe;
  final Color accent;
  final String timeStr;
  final bool isImage;
  const _MediaBubble({required this.msg, required this.isMe,
      required this.accent, required this.timeStr, required this.isImage});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _Avatar(name: msg.displayName, color: AppTheme.accentCyan),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Text(msg.displayName,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.45))),
                if (msg.mediaUrl != null)
                  GestureDetector(
                    onTap: () => _openImageFullscreen(context, msg.mediaUrl!),
                    onLongPress: () => _showImageOptions(context, msg.mediaUrl!),
                    child: ClipRRect(
                      borderRadius: BorderRadius.only(
                        topLeft:     const Radius.circular(16),
                        topRight:    const Radius.circular(16),
                        bottomLeft:  Radius.circular(isMe ? 16 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: CachedNetworkImage(
                          imageUrl: msg.mediaUrl!,
                          width: 240,
                          fit: BoxFit.fitWidth,
                          placeholder: (_, __) => Container(
                              width: 240, height: 180, color: Colors.white10,
                              child: const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white54))),
                          errorWidget: (_, __, ___) =>
                              Container(width: 240, height: 180, color: Colors.white10,
                                  child: const Icon(Icons.broken_image_rounded,
                                      color: Colors.white24, size: 36)),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                Text(timeStr,
                    style: TextStyle(
                        fontSize: 10, color: Colors.white.withValues(alpha: 0.3))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Image helper functions ────────────────────────────────────────────────────

void _openImageFullscreen(BuildContext context, String url) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Image', style: TextStyle(fontSize: 14)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6.0,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) =>
                const CircularProgressIndicator(color: Colors.white54),
            errorWidget: (_, __, ___) => const Icon(
                Icons.broken_image_rounded, color: Colors.white38, size: 64),
          ),
        ),
      ),
    ),
  ));
}

void _showImageOptions(BuildContext context, String url) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_full_rounded, color: Colors.white70),
            title: const Text('View Full Image',
                style: TextStyle(color: Colors.white, fontSize: 15)),
            onTap: () {
              Navigator.pop(context);
              _openImageFullscreen(context, url);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded, color: Colors.white70),
            title: const Text('Save to Device',
                style: TextStyle(color: Colors.white, fontSize: 15)),
            onTap: () {
              Navigator.pop(context);
              _downloadImage(context, url);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _downloadImage(BuildContext context, String url) async {
  try {
    // On Android 10+ (API 29+), WRITE_EXTERNAL_STORAGE is not needed for Downloads.
    // On older versions we request it but proceed regardless (graceful degradation).
    if (Platform.isAndroid) {
      final status = await Permission.storage.status;
      if (!status.isGranted) await Permission.storage.request();
    }

    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

    final ts = DateTime.now().millisecondsSinceEpoch;
    final savePath = '/storage/emulated/0/Download/beatflow_$ts.jpg';
    await File(savePath).writeAsBytes(resp.bodyBytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Image saved to Downloads'),
          backgroundColor: Color(0xFF22C55E),
          duration: Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

// File bubble
class _FileBubble extends StatelessWidget {
  final SessionChatMessage msg;
  final bool isMe;
  final Color accent;
  final String timeStr;
  const _FileBubble({required this.msg, required this.isMe,
      required this.accent, required this.timeStr});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _Avatar(name: msg.displayName, color: AppTheme.accentCyan),
            const SizedBox(width: 6),
          ],
          Container(
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 220),
            decoration: BoxDecoration(
              color: isMe
                  ? accent.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insert_drive_file_rounded,
                    color: isMe ? Colors.white : accent, size: 28),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg.fileName ?? 'File',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: isMe ? Colors.white : AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                      Text(timeStr,
                          style: TextStyle(
                              fontSize: 10,
                              color: isMe
                                  ? Colors.white60
                                  : Colors.white.withValues(alpha: 0.3))),
                    ],
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

// YouTube track card in chat
class _YoutubeBubble extends StatelessWidget {
  final SessionChatMessage msg;
  final bool isMe;
  final Color accent;
  final String timeStr;
  final bool isOwner;
  final void Function(YoutubeTrack) onPlay;

  const _YoutubeBubble({
    required this.msg,
    required this.isMe,
    required this.accent,
    required this.timeStr,
    required this.isOwner,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(msg.displayName,
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w500)),
            ),
          Container(
            constraints: const BoxConstraints(maxWidth: 260),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFFFF0000).withValues(alpha: 0.3), width: 1),
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                if (msg.ytThumbnail != null)
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      CachedNetworkImage(
                        imageUrl: msg.ytThumbnail!,
                        width: 260, height: 146,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                            width: 260, height: 146, color: Colors.black26),
                        errorWidget: (_, __, ___) =>
                            Container(width: 260, height: 146, color: Colors.black26),
                      ),
                      // YouTube play overlay
                      Container(
                        width: 48, height: 48,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFF0000),
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 28),
                      ),
                    ],
                  ),
                // Info + play button
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.smart_display_rounded,
                              color: Color(0xFFFF0000), size: 14),
                          const SizedBox(width: 4),
                          const Text('YouTube',
                              style: TextStyle(
                                  color: Color(0xFFFF0000),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        msg.ytTitle ?? msg.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.3),
                      ),
                      if (msg.ytArtist != null) ...[
                        const SizedBox(height: 2),
                        Text(msg.ytArtist!,
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 11)),
                      ],
                      const SizedBox(height: 8),
                      if (isOwner)
                        SizedBox(
                          width: double.infinity,
                          child: GestureDetector(
                            onTap: () {
                              // Build YoutubeTrack from msg
                              final track = YoutubeTrack(
                                videoId:      msg.ytVideoId    ?? '',
                                title:        msg.ytTitle      ?? '',
                                artist:       msg.ytArtist     ?? '',
                                thumbnailUrl: msg.ytThumbnail  ?? '',
                                duration: Duration(milliseconds: msg.ytDurationMs ?? 0),
                                streamUrl:    msg.mediaUrl     ?? '',
                              );
                              onPlay(track);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                gradient: LinearGradient(
                                    colors: [accent, accent.withValues(alpha: 0.7)]),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.play_arrow_rounded,
                                      color: Colors.white, size: 18),
                                  SizedBox(width: 4),
                                  Text('Play for everyone',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(timeStr,
              style: TextStyle(
                  fontSize: 10, color: Colors.white.withValues(alpha: 0.3))),
        ],
      ),
    );
  }
}

// Small helper class for passing to onPlayYt from chat bubble
class _FakeYtTrack {
  final String videoId, title, artist, thumbnail, streamUrl;
  final int durationMs;
  _FakeYtTrack({required this.videoId, required this.title,
      required this.artist, required this.thumbnail,
      required this.durationMs, required this.streamUrl});
}

class _Avatar extends StatelessWidget {
  final String name;
  final Color color;
  const _Avatar({required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.5), AppTheme.bgSurface]),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.06),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}
