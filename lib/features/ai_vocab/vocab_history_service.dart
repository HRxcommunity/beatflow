// ╔══════════════════════════════════════════════════════════════╗
// ║  Vocab Chat History Service                                  ║
// ║  Hive-based persistence — chat sessions across app restarts  ║
// ║  NEW FILE — add VocabHistoryService.instance.init() in main  ║
// ╚══════════════════════════════════════════════════════════════╝

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'groq_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data Models
// ─────────────────────────────────────────────────────────────────────────────

/// Single message saved in history
class HistoryMessage {
  final String   role;       // 'user' | 'assistant'
  final String   content;
  final DateTime time;
  bool           bookmarked;

  HistoryMessage({
    required this.role,
    required this.content,
    required this.time,
    this.bookmarked = false,
  });

  Map<String, dynamic> toJson() => {
        'role'       : role,
        'content'    : content,
        'time'       : time.millisecondsSinceEpoch,
        'bookmarked' : bookmarked,
      };

  factory HistoryMessage.fromJson(Map<String, dynamic> j) => HistoryMessage(
        role       : j['role']       as String? ?? 'user',
        content    : j['content']    as String? ?? '',
        time       : DateTime.fromMillisecondsSinceEpoch(j['time'] as int? ?? 0),
        bookmarked : j['bookmarked'] as bool?   ?? false,
      );

  /// Convert to API format for resuming conversation
  ChatMessage toChatMessage() => ChatMessage(role: role, content: content);
}

// ─────────────────────────────────────────────────────────────────────────────

/// One complete chat session (can span many messages)
class ChatSession {
  final String   id;
  final DateTime startedAt;
  DateTime       updatedAt;
  String         title;
  List<HistoryMessage> messages;

  ChatSession({
    required this.id,
    required this.startedAt,
    required this.updatedAt,
    required this.title,
    required this.messages,
  });

  int    get messageCount   => messages.length;
  int    get userMsgCount   => messages.where((m) => m.role == 'user').length;
  int    get bookmarkCount  => messages.where((m) => m.bookmarked).length;
  String get previewText    => messages.isNotEmpty ? messages.last.content : '';

  Map<String, dynamic> toJson() => {
        'id'        : id,
        'startedAt' : startedAt.millisecondsSinceEpoch,
        'updatedAt' : updatedAt.millisecondsSinceEpoch,
        'title'     : title,
        'messages'  : messages.map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> j) => ChatSession(
        id        : j['id']        as String? ?? '',
        startedAt : DateTime.fromMillisecondsSinceEpoch(j['startedAt'] as int? ?? 0),
        updatedAt : DateTime.fromMillisecondsSinceEpoch(j['updatedAt'] as int? ?? 0),
        title     : j['title']     as String? ?? 'Chat Session',
        messages  : (j['messages'] as List? ?? [])
            .map((e) => HistoryMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Service Singleton
// ─────────────────────────────────────────────────────────────────────────────

class VocabHistoryService {
  static final VocabHistoryService instance = VocabHistoryService._();
  VocabHistoryService._();

  static const _boxName     = 'vocab_chat_history';
  static const _sessionsKey = 'sessions_v1';
  static const _maxSessions = 60; // Keep last 60 sessions

  List<ChatSession> _sessions = [];
  bool              _initialized = false;

  List<ChatSession> get sessions     => List.unmodifiable(_sessions);
  int               get sessionCount => _sessions.length;

  // ─────────────────────────────────────────────────────────────────────────
  // Init
  // ─────────────────────────────────────────────────────────────────────────

  /// Call once at app start — e.g., in main.dart after Hive.init()
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<String>(_boxName);
    }
    _loadFromHive();
    debugPrint('[VocabHistory] Loaded ${_sessions.length} sessions');
  }

  void _loadFromHive() {
    try {
      final box  = Hive.box<String>(_boxName);
      final json = box.get(_sessionsKey);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _sessions = list
            .map((e) => ChatSession.fromJson(e as Map<String, dynamic>))
            .where((s) => s.id.isNotEmpty)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }
    } catch (e) {
      debugPrint('[VocabHistory] Load error: $e');
      _sessions = [];
    }
  }

  Future<void> _saveToHive() async {
    try {
      final box = Hive.box<String>(_boxName);
      await box.put(
        _sessionsKey,
        jsonEncode(_sessions.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[VocabHistory] Save error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Session Management
  // ─────────────────────────────────────────────────────────────────────────

  String _generateTitle(List<HistoryMessage> messages) {
    final firstUser = messages.firstWhere(
      (m) => m.role == 'user',
      orElse: () => HistoryMessage(role: 'user', content: 'Chat', time: DateTime.now()),
    );
    final t = firstUser.content.trim();
    return t.length <= 45 ? t : '${t.substring(0, 42)}...';
  }

  /// Save or update a session.
  /// - If [sessionId] is null → creates new session, returns new ID
  /// - If [sessionId] exists → updates that session
  Future<String> saveSession({
    String?                sessionId,
    required List<HistoryMessage> messages,
  }) async {
    if (messages.isEmpty) return '';

    final now   = DateTime.now();
    final title = _generateTitle(messages);

    if (sessionId != null) {
      final idx = _sessions.indexWhere((s) => s.id == sessionId);
      if (idx != -1) {
        _sessions[idx]
          ..messages  = List.from(messages)
          ..updatedAt = now
          ..title     = title;
        _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        await _saveToHive();
        return sessionId;
      }
    }

    // New session
    final id = 'sess_${now.millisecondsSinceEpoch}';
    _sessions.insert(
      0,
      ChatSession(
        id        : id,
        startedAt : now,
        updatedAt : now,
        title     : title,
        messages  : List.from(messages),
      ),
    );

    // Trim old sessions
    if (_sessions.length > _maxSessions) {
      _sessions = _sessions.take(_maxSessions).toList();
    }

    await _saveToHive();
    debugPrint('[VocabHistory] Session saved: $id (${messages.length} msgs)');
    return id;
  }

  Future<void> deleteSession(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    await _saveToHive();
    debugPrint('[VocabHistory] Deleted session: $id');
  }

  Future<void> clearAll() async {
    _sessions.clear();
    await _saveToHive();
    debugPrint('[VocabHistory] All sessions cleared');
  }

  ChatSession? getSession(String id) {
    try {
      return _sessions.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bookmarks
  // ─────────────────────────────────────────────────────────────────────────

  List<({ChatSession session, HistoryMessage message, int index})>
      getAllBookmarks() {
    final result = <({ChatSession session, HistoryMessage message, int index})>[];
    for (final session in _sessions) {
      for (int i = 0; i < session.messages.length; i++) {
        if (session.messages[i].bookmarked) {
          result.add((session: session, message: session.messages[i], index: i));
        }
      }
    }
    return result;
  }

  Future<void> toggleBookmark(String sessionId, int messageIndex) async {
    final session = getSession(sessionId);
    if (session == null) return;
    if (messageIndex >= 0 && messageIndex < session.messages.length) {
      session.messages[messageIndex].bookmarked =
          !session.messages[messageIndex].bookmarked;
      await _saveToHive();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stats
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, int> getStats() {
    final now           = DateTime.now();
    final todaySessions = _sessions.where((s) =>
        s.updatedAt.day   == now.day   &&
        s.updatedAt.month == now.month &&
        s.updatedAt.year  == now.year).length;
    final totalMessages = _sessions.fold(0, (sum, s) => sum + s.messageCount);
    final bookmarks     = getAllBookmarks().length;

    return {
      'totalSessions' : _sessions.length,
      'todaySessions' : todaySessions,
      'totalMessages' : totalMessages,
      'bookmarks'     : bookmarks,
    };
  }
}
