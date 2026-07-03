import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ── Data models ───────────────────────────────────────────────

class SocialUser {
  final String uid;
  final String displayName;
  final bool isOnline;
  final DateTime? lastSeen;
  final int followersCount;
  final int followingCount;

  const SocialUser({
    required this.uid,
    required this.displayName,
    this.isOnline = false,
    this.lastSeen,
    this.followersCount = 0,
    this.followingCount = 0,
  });

  factory SocialUser.fromMap(Map<String, dynamic> map) => SocialUser(
        uid:            map['uid']            as String? ?? '',
        displayName:    map['displayName']    as String? ?? 'Unknown',
        isOnline:       map['isOnline']       as bool?   ?? false,
        lastSeen:       map['lastSeen'] != null
            ? (map['lastSeen'] as Timestamp).toDate()
            : null,
        followersCount: map['followersCount'] as int?    ?? 0,
        followingCount: map['followingCount'] as int?    ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'uid':            uid,
        'displayName':    displayName,
        'isOnline':       isOnline,
        'lastSeen':       lastSeen != null ? Timestamp.fromDate(lastSeen!) : null,
        'followersCount': followersCount,
        'followingCount': followingCount,
      };
}

class SocialActivity {
  final String uid;
  final String displayName;
  final String songTitle;
  final String songArtist;
  final bool isInSession;
  final String? sessionCode;
  final DateTime updatedAt;
  final bool isListening;

  const SocialActivity({
    required this.uid,
    required this.displayName,
    required this.songTitle,
    required this.songArtist,
    this.isInSession = false,
    this.sessionCode,
    required this.updatedAt,
    this.isListening = true,
  });

  factory SocialActivity.fromMap(Map<String, dynamic> map) => SocialActivity(
        uid:          map['uid']          as String? ?? '',
        displayName:  map['displayName']  as String? ?? 'Unknown',
        songTitle:    map['songTitle']    as String? ?? '',
        songArtist:   map['songArtist']   as String? ?? '',
        isInSession:  map['isInSession']  as bool?   ?? false,
        sessionCode:  map['sessionCode']  as String?,
        updatedAt:    map['updatedAt'] != null
            ? (map['updatedAt'] as Timestamp).toDate()
            : DateTime.now(),
        isListening:  map['isListening']  as bool?   ?? true,
      );

  Map<String, dynamic> toMap() => {
        'uid':         uid,
        'displayName': displayName,
        'songTitle':   songTitle,
        'songArtist':  songArtist,
        'isInSession': isInSession,
        if (sessionCode != null) 'sessionCode': sessionCode,
        'updatedAt':   Timestamp.fromDate(updatedAt),
        'isListening': isListening,
      };
}

// ── Service ───────────────────────────────────────────────────

class SocialService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('beatflow_users');

  CollectionReference<Map<String, dynamic>> get _activity =>
      _db.collection('beatflow_activity');

  // ── Profile ───────────────────────────────────────────────────
  Future<void> upsertProfile({
    required String uid,
    required String displayName,
  }) async {
    try {
      await _users.doc(uid).set({
        'uid':            uid,
        'displayName':    displayName,
        'lastSeen':       Timestamp.now(),
        'isOnline':       true,
        'followersCount': FieldValue.increment(0),
        'followingCount': FieldValue.increment(0),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Social] upsertProfile error: $e');
    }
  }

  // ── Follow / Unfollow ─────────────────────────────────────────
  Future<void> followUser({
    required String myUid,
    required String myName,
    required String targetUid,
    required String targetName,
  }) async {
    try {
      final batch = _db.batch();
      batch.set(
        _users.doc(myUid).collection('following').doc(targetUid),
        {'uid': targetUid, 'displayName': targetName, 'followedAt': Timestamp.now()},
      );
      batch.set(
        _users.doc(targetUid).collection('followers').doc(myUid),
        {'uid': myUid, 'displayName': myName, 'followedAt': Timestamp.now()},
      );
      batch.update(_users.doc(myUid), {
        'followingCount': FieldValue.increment(1),
      });
      batch.update(_users.doc(targetUid), {
        'followersCount': FieldValue.increment(1),
      });
      await batch.commit();
    } catch (e) {
      debugPrint('[Social] followUser error: $e');
      rethrow;
    }
  }

  Future<void> unfollowUser({
    required String myUid,
    required String targetUid,
  }) async {
    try {
      final batch = _db.batch();
      batch.delete(_users.doc(myUid).collection('following').doc(targetUid));
      batch.delete(_users.doc(targetUid).collection('followers').doc(myUid));
      batch.update(_users.doc(myUid), {
        'followingCount': FieldValue.increment(-1),
      });
      batch.update(_users.doc(targetUid), {
        'followersCount': FieldValue.increment(-1),
      });
      await batch.commit();
    } catch (e) {
      debugPrint('[Social] unfollowUser error: $e');
      rethrow;
    }
  }

  // ── Get following UIDs ────────────────────────────────────────
  Future<Set<String>> getFollowingUids(String uid) async {
    try {
      final snap = await _users.doc(uid).collection('following').get();
      return snap.docs.map((d) => d.data()['uid'] as String).toSet();
    } catch (e) {
      debugPrint('[Social] getFollowingUids error: $e');
      return {};
    }
  }

  // ── Watch friends list ────────────────────────────────────────
  Stream<List<SocialUser>> watchFollowing(String uid) {
    return _users
        .doc(uid)
        .collection('following')
        .orderBy('followedAt', descending: true)
        .limit(100)
        .snapshots()
        .asyncMap((snap) async {
      final List<SocialUser> users = [];
      for (final doc in snap.docs) {
        try {
          final targetUid = doc.data()['uid'] as String? ?? '';
          if (targetUid.isEmpty) continue;
          final userDoc = await _users.doc(targetUid).get();
          if (userDoc.exists && userDoc.data() != null) {
            users.add(SocialUser.fromMap(userDoc.data()!));
          }
        } catch (_) {}
      }
      return users;
    });
  }

  // ── Activity Feed ─────────────────────────────────────────────
  Future<void> updateActivity({
    required String uid,
    required String displayName,
    required String songTitle,
    required String songArtist,
    bool isInSession = false,
    String? sessionCode,
  }) async {
    try {
      await _activity.doc(uid).set({
        'uid':         uid,
        'displayName': displayName,
        'songTitle':   songTitle,
        'songArtist':  songArtist,
        'isInSession': isInSession,
        'sessionCode': sessionCode,
        'updatedAt':   Timestamp.now(),
        'isListening': true,
      });
    } catch (e) {
      debugPrint('[Social] updateActivity error: $e');
    }
  }

  Future<void> clearActivity(String uid) async {
    try {
      await _activity.doc(uid).set({
        'uid':         uid,
        'isListening': false,
        'updatedAt':   Timestamp.now(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Social] clearActivity error: $e');
    }
  }

  Stream<List<SocialActivity>> watchFriendActivity(String uid) {
    return _users
        .doc(uid)
        .collection('following')
        .snapshots()
        .asyncMap((snap) async {
      final List<SocialActivity> activities = [];
      for (final doc in snap.docs) {
        try {
          final friendUid = doc.data()['uid'] as String? ?? '';
          if (friendUid.isEmpty) continue;
          final actDoc = await _activity.doc(friendUid).get();
          if (actDoc.exists && actDoc.data() != null) {
            final a = SocialActivity.fromMap(actDoc.data()!);
            if (a.isListening) activities.add(a);
          }
        } catch (_) {}
      }
      activities.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return activities;
    });
  }

  // ── Search Users ──────────────────────────────────────────────
  Future<List<SocialUser>> searchUsers({
    required String query,
    required String myUid,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final snap = await _users
          .orderBy('displayName')
          .startAt([q])
          .endAt(['$q\uf8ff'])
          .limit(20)
          .get();
      final results = snap.docs
          .map((d) => SocialUser.fromMap(d.data()))
          .where((u) => u.uid != myUid && u.uid.isNotEmpty)
          .toList();
      if (results.isNotEmpty) return results;
    } catch (_) {}

    try {
      final snap = await _users.limit(60).get();
      final lower = q.toLowerCase();
      return snap.docs
          .map((d) => SocialUser.fromMap(d.data()))
          .where((u) =>
              u.uid != myUid &&
              u.uid.isNotEmpty &&
              u.displayName.toLowerCase().contains(lower))
          .toList();
    } catch (e) {
      debugPrint('[Social] searchUsers fallback error: $e');
      return [];
    }
  }
}
