import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/models/session_model.dart';
import '../domain/entities/session_entity.dart';

class TogetherSessionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('together_sessions');

  // Sub-collection for chat (Fix 1 — no more 1MB limit)
  CollectionReference<Map<String, dynamic>> _chat(String sessionId) =>
      _sessions.doc(sessionId).collection('chat_messages');

  // ── Code generation ───────────────────────────────────────────
  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ── Create ────────────────────────────────────────────────────
  Future<SessionEntity?> createSession({
    required String uid,
    required String ownerName,
    required String songId,
    required String songTitle,
    required String songArtist,
    required String songData,
    required String? streamUrl,
    required int songDurationMs,
    required int positionMs,
    required bool isPlaying,
  }) async {
    try {
      String code;
      do {
        code = _generateCode();
      } while (await _codeExists(code));

      final ownerMember = SessionMember(
        uid: uid,
        displayName: ownerName,
        isOnline: true,
        joinedAt: DateTime.now(),
      );

      final docRef = _sessions.doc();
      final model = SessionModel(
        sessionId:      docRef.id,
        sessionCode:    code,
        ownerId:        uid,
        ownerName:      ownerName,
        songId:         songId,
        songTitle:      songTitle,
        songArtist:     songArtist,
        songData:       songData,
        streamUrl:      streamUrl ?? '',
        songDurationMs: songDurationMs,
        positionMs:     positionMs,
        isPlaying:      isPlaying,
        updatedAt:         Timestamp.now(),
        playbackUpdatedAt: Timestamp.now(), // BUG-S01 FIX
        members:           [ownerMember.toMap()],
        chatMessages:   [], // kept for backward compat, always empty now
      );

      await docRef.set(model.toFirestore());
      return model.toEntity();
    } catch (e) {
      debugPrint('[Together] createSession error: $e');
      return null;
    }
  }

  // ── Update stream URL ─────────────────────────────────────────
  Future<void> updateStreamUrl({
    required String sessionId,
    required String streamUrl,
  }) async {
    try {
      await _sessions.doc(sessionId).update({
        'streamUrl': streamUrl,
        'updatedAt': Timestamp.now(),
      });
      debugPrint('[Together] streamUrl updated in Firestore: $streamUrl');
    } catch (e) {
      debugPrint('[Together] updateStreamUrl error: $e');
    }
  }

  // ── Join ──────────────────────────────────────────────────────
  Future<SessionEntity?> joinSession({
    required String code,
    required String uid,
    required String displayName,
  }) async {
    debugPrint('[Together] joinSession → code="${code.toUpperCase()}" uid=$uid');

    // Fix 4 — Rate limit: max 10 join attempts per minute tracked client-side
    if (!_checkJoinRateLimit()) {
      debugPrint('[Together] joinSession blocked — rate limit exceeded');
      throw Exception('Too many join attempts. Please wait a minute.');
    }

    final snap = await _sessions
        .where('sessionCode', isEqualTo: code.toUpperCase())
        .limit(1)
        .get();

    debugPrint('[Together] joinSession query returned ${snap.docs.length} doc(s)');

    if (snap.docs.isEmpty) return null;

    final doc      = snap.docs.first;
    final existing = SessionModel.fromFirestore(doc).toEntity();
    final isMember = existing.members.any((m) => m.uid == uid);

    if (!isMember) {
      final newMember = SessionMember(
        uid: uid,
        displayName: displayName,
        isOnline: true,
        joinedAt: DateTime.now(),
      );
      await doc.reference.update({
        'members':   FieldValue.arrayUnion([newMember.toMap()]),
        'updatedAt': Timestamp.now(),
      });
    } else {
      await _setMemberOnline(doc.reference, uid, displayName, true);
    }

    final updated = await doc.reference.get();
    return SessionModel.fromFirestore(updated).toEntity();
  }

  // ── Fix 4: Client-side join rate limiter ─────────────────────
  final List<DateTime> _joinAttempts = [];
  bool _checkJoinRateLimit() {
    final now    = DateTime.now();
    final cutoff = now.subtract(const Duration(minutes: 1));
    _joinAttempts.removeWhere((t) => t.isBefore(cutoff));
    if (_joinAttempts.length >= 10) return false;
    _joinAttempts.add(now);
    return true;
  }

  // ── Leave ─────────────────────────────────────────────────────
  Future<void> leaveSession({
    required String sessionId,
    required String uid,
    required bool isOwner,
  }) async {
    try {
      final ref = _sessions.doc(sessionId);
      if (isOwner) {
        // BUG-018: Instant hard-delete gives guests no warning.
        // Fix: mark session as 'isEnding' first so guests can show a graceful
        // "session ending" message, then delete after a 2-second grace period.
        // A full fix also requires a confirmation dialog in the UI before
        // dispatching TogetherLeaveSession.
        try {
          await ref.update({'isEnding': true, 'updatedAt': Timestamp.now()});
        } catch (_) {
          // If the update fails (e.g. doc already deleted), proceed to delete
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        await ref.delete();
      } else {
        final snap = await ref.get();
        if (!snap.exists) return;
        final session = SessionModel.fromFirestore(snap).toEntity();
        final updatedMembers = session.members
            .where((m) => m.uid != uid)
            .map((m) => m.toMap())
            .toList();
        await ref.update({
          'members':   updatedMembers,
          'updatedAt': Timestamp.now(),
        });
      }
    } catch (e) {
      debugPrint('[Together] leaveSession error: $e');
    }
  }

  // ── Push playback state (owner) ───────────────────────────────
  // Fix 2 — Only push on song change / play / pause / seek events.
  // positionMs is ONLY written when something meaningful changed,
  // not on every 2s tick. Client-side calculates position in real-time.
  Future<void> pushPlaybackState({
    required String sessionId,
    required String songId,
    required String songTitle,
    required String songArtist,
    required String songData,
    required String? streamUrl,
    required int songDurationMs,
    required int positionMs,
    required bool isPlaying,
  }) async {
    try {
      // BUG-002: always write streamUrl — if null/empty, write '' to clear the
      // previous song's URL. Skipping this field leaves stale URL in Firestore,
      // causing guests to play the old song's audio under new song's metadata.
      final Map<String, dynamic> data = {
        'songId':         songId,
        'songTitle':      songTitle,
        'songArtist':     songArtist,
        'songData':       songData,
        'streamUrl':      streamUrl ?? '', // always write, '' clears stale URL
        'songDurationMs': songDurationMs,
        'positionMs':     positionMs,
        'isPlaying':      isPlaying,
        'updatedAt':      Timestamp.now(),
        'playbackUpdatedAt': Timestamp.now(), // BUG-S01 FIX: separate playback anchor
      };

      await _sessions.doc(sessionId).update(data);
    } catch (e) {
      debugPrint('[Together] pushPlaybackState error: $e');
    }
  }

  // ── Seek ──────────────────────────────────────────────────────
  Future<void> pushSeek({
    required String sessionId,
    required int positionMs,
  }) async {
    try {
      await _sessions.doc(sessionId).update({
        'positionMs':        positionMs,
        'updatedAt':         Timestamp.now(),
        'playbackUpdatedAt': Timestamp.now(), // BUG-S01 FIX
      });
    } catch (e) {
      debugPrint('[Together] pushSeek error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  CHAT — Fix 1: Sub-collection (no 1MB limit)
  // ══════════════════════════════════════════════════════════════

  /// Send text/emoji — stored in sub-collection, not session document array
  Future<void> sendChatMessage({
    required String sessionId,
    required String uid,
    required String displayName,
    required String text,
    ChatMessageType type = ChatMessageType.text,
  }) async {
    if (text.trim().isEmpty && type == ChatMessageType.text) return;
    final msg = SessionChatMessage(
      uid:         uid,
      displayName: displayName,
      text:        text.trim(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      type:        type,
    );
    try {
      await _chat(sessionId).add(msg.toMap());
    } catch (e) {
      debugPrint('[Together] sendChatMessage error: $e');
    }
  }

  Future<void> sendMediaMessage({
    required String sessionId,
    required String uid,
    required String displayName,
    required String mediaUrl,
    required bool isImage,
    String? fileName,
  }) async {
    final msg = SessionChatMessage(
      uid:         uid,
      displayName: displayName,
      text:        isImage ? '📷 Photo' : '📎 ${fileName ?? 'File'}',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      type:        isImage ? ChatMessageType.image : ChatMessageType.file,
      mediaUrl:    mediaUrl,
      fileName:    fileName,
    );
    try {
      await _chat(sessionId).add(msg.toMap());
    } catch (e) {
      debugPrint('[Together] sendMediaMessage error: $e');
    }
  }

  Future<void> sendYoutubeTrackMessage({
    required String sessionId,
    required String uid,
    required String displayName,
    required String ytVideoId,
    required String ytTitle,
    required String ytArtist,
    required String ytThumbnail,
    required int ytDurationMs,
    required String streamUrl,
  }) async {
    final msg = SessionChatMessage(
      uid:          uid,
      displayName:  displayName,
      text:         '🎵 $ytTitle',
      timestampMs:  DateTime.now().millisecondsSinceEpoch,
      type:         ChatMessageType.youtubeTrack,
      ytVideoId:    ytVideoId,
      ytTitle:      ytTitle,
      ytArtist:     ytArtist,
      ytThumbnail:  ytThumbnail,
      ytDurationMs: ytDurationMs,
      mediaUrl:     streamUrl,
    );
    try {
      await _chat(sessionId).add(msg.toMap());
    } catch (e) {
      debugPrint('[Together] sendYoutubeTrackMessage error: $e');
    }
  }

  /// Real-time stream of chat messages from sub-collection.
  /// BUG-028: Sort is now server-side via orderBy('timestampMs') — avoids
  /// O(n log n) re-sort on every Firestore snapshot in active sessions.
  /// Firestore auto-creates a single-field index for this orderBy.
  Stream<List<SessionChatMessage>> chatStream(String sessionId) {
    return _chat(sessionId)
        .orderBy('timestampMs')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => SessionChatMessage.fromMap(d.data()))
            .toList());
  }

  // ══════════════════════════════════════════════════════════════
  //  VIDEO CALL
  // ══════════════════════════════════════════════════════════════

  Future<void> startVideoCall({
    required String sessionId,
    required String channelId,
  }) async {
    try {
      await _sessions.doc(sessionId).update({
        'agoraChannel': channelId,
        'callActive':   true,
        'updatedAt':    Timestamp.now(),
      });
    } catch (e) {
      debugPrint('[Together] startVideoCall error: $e');
    }
  }

  Future<void> endVideoCall(String sessionId) async {
    try {
      await _sessions.doc(sessionId).update({
        'agoraChannel': FieldValue.delete(),
        'callActive':   false,
        'updatedAt':    Timestamp.now(),
      });
    } catch (e) {
      debugPrint('[Together] endVideoCall error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  HOST CHANGE REQUEST
  // ══════════════════════════════════════════════════════════════

  Future<void> requestHostChange({
    required String sessionId,
    required String requesterUid,
    required String requesterName,
  }) async {
    final req = HostChangeRequest(
      requesterUid:  requesterUid,
      requesterName: requesterName,
      requestedAtMs: DateTime.now().millisecondsSinceEpoch,
      status:        'pending',
    );
    try {
      await _sessions.doc(sessionId).update({
        'pendingHostRequest': req.toMap(),
        'updatedAt':          Timestamp.now(),
      });
    } catch (e) {
      debugPrint('[Together] requestHostChange error: $e');
    }
  }

  Future<void> acceptHostChange({
    required String sessionId,
    required String newOwnerUid,
    required String newOwnerName,
  }) async {
    try {
      await _sessions.doc(sessionId).update({
        'ownerId':            newOwnerUid,
        'ownerName':          newOwnerName,
        'pendingHostRequest': FieldValue.delete(),
        'updatedAt':          Timestamp.now(),
      });
    } catch (e) {
      debugPrint('[Together] acceptHostChange error: $e');
    }
  }

  Future<void> rejectHostChange({required String sessionId}) async {
    try {
      await _sessions.doc(sessionId).update({
        'pendingHostRequest': FieldValue.delete(),
        'updatedAt':          Timestamp.now(),
      });
    } catch (e) {
      debugPrint('[Together] rejectHostChange error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  PRESENCE — Fix 3: TTL-based (crash-safe)
  // ══════════════════════════════════════════════════════════════

  // Fix 3: Instead of setOnlineStatus(false) on disconnect (unreliable),
  // we write a `presenceExpiresAt` timestamp. If it's in the past,
  // the user is considered offline. Refresh every 30s while alive.
  // App crash → no refresh → expires naturally.
  Timer? _presenceTimer;

  void startPresenceHeartbeat({
    required String sessionId,
    required String uid,
    required String displayName,
  }) {
    _presenceTimer?.cancel();
    // Write immediately, then every 30 seconds
    _refreshPresence(sessionId, uid, displayName, true);
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshPresence(sessionId, uid, displayName, true);
    });
    debugPrint('[Together] Presence heartbeat started for $uid');
  }

  void stopPresenceHeartbeat({
    required String sessionId,
    required String uid,
    required String displayName,
  }) {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    // Mark offline explicitly (best-effort — works for clean exits)
    _refreshPresence(sessionId, uid, displayName, false);
    debugPrint('[Together] Presence heartbeat stopped for $uid');
  }

  Future<void> _refreshPresence(
    String sessionId,
    String uid,
    String displayName,
    bool isOnline,
  ) async {
    try {
      final ref = _sessions.doc(sessionId);
      await _setMemberOnline(ref, uid, displayName, isOnline);
    } catch (e) {
      debugPrint('[Together] _refreshPresence error (non-critical): $e');
    }
  }

  // Legacy method — kept for compatibility with existing bloc calls
  Future<void> setOnlineStatus({
    required String sessionId,
    required String uid,
    required String displayName,
    required bool isOnline,
  }) async {
    try {
      final ref = _sessions.doc(sessionId);
      await _setMemberOnline(ref, uid, displayName, isOnline);
    } catch (e) {
      debugPrint('[Together] setOnlineStatus error: $e');
    }
  }

  Future<void> _setMemberOnline(
    DocumentReference ref,
    String uid,
    String displayName,
    bool isOnline,
  ) async {
    // BUG-008: Non-atomic read-then-write causes concurrent heartbeat overwrites
    // (e.g. 5 members all heartbeating every 30s can corrupt each other's status).
    // Fix: wrap in a Firestore transaction so reads and writes are atomic.
    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final membersList = (data['members'] as List? ?? [])
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList();

      // TTL: presence expires 90 seconds from now (3× heartbeat interval)
      final expiresAt = isOnline
          ? DateTime.now()
                .add(const Duration(seconds: 90))
                .millisecondsSinceEpoch
          : 0;

      final updatedMembers = membersList.map((m) {
        if (m['uid'] == uid) {
          return <String, dynamic>{
            ...m,
            'isOnline':          isOnline,
            'presenceExpiresAt': expiresAt,
          };
        }
        return m;
      }).toList();

      txn.update(ref, {'members': updatedMembers});
    });
  }

  // ── Real-time stream ──────────────────────────────────────────
  Stream<SessionEntity?> sessionStream(String sessionId) {
    return _sessions.doc(sessionId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return SessionModel.fromFirestore(snap).toEntity();
    });
  }

  // ── Helpers ───────────────────────────────────────────────────
  Future<bool> _codeExists(String code) async {
    final snap = await _sessions
        .where('sessionCode', isEqualTo: code)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<SessionEntity?> getSession(String sessionId) async {
    try {
      final snap = await _sessions.doc(sessionId).get();
      if (!snap.exists) return null;
      return SessionModel.fromFirestore(snap).toEntity();
    } catch (e) {
      return null;
    }
  }
}
