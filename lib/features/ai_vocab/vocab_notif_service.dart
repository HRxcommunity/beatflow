// ╔══════════════════════════════════════════════════════════════╗
// ║  Vocab Notification Service                                  ║
// ║  BUG-VN01 FIX: retry logic for word generation              ║
// ║  BUG-VN02 FIX: notification permission only                 ║
// ║  BUG-VN05 FIX: IST timezone explicit set                    ║
// ║  BUG-VN06 FIX: _attemptGenerate complete                    ║
// ║  BUG-VN07 FIX: EXACT alarms — no more batch firing!         ║
// ║  BUG-VN08 FIX: auto word-bank generate on scheduleNext()    ║
// ╚══════════════════════════════════════════════════════════════╝
//
// ⚠️ AndroidManifest.xml mein add karo (before <application> tag):
//
//   <!-- Android 12 (API 31-32): user must grant in system settings -->
//   <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
//   <!-- Android 13+ (API 33+): auto-granted, no user interaction needed -->
//   <uses-permission android:name="android.permission.USE_EXACT_ALARM" />
//
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzData;

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class VocabWord {
  final String word;
  final String hindiSentence;
  final String hindiMeaning;

  const VocabWord({
    required this.word,
    required this.hindiSentence,
    required this.hindiMeaning,
  });

  Map<String, dynamic> toJson() => {
        'word'         : word,
        'hindiSentence': hindiSentence,
        'hindiMeaning' : hindiMeaning,
      };

  factory VocabWord.fromJson(Map<String, dynamic> j) => VocabWord(
        word         : (j['word']          as String? ?? '').trim(),
        hindiSentence: (j['hindiSentence'] as String? ?? '').trim(),
        hindiMeaning : (j['hindiMeaning']  as String? ?? '').trim(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class VocabNotifSettings {
  bool      enabled;
  int       startHour;
  int       startMinute;
  int       endHour;
  int       endMinute;
  int       dailyCount;
  List<int> activeDays;
  String    groqApiKey;

  VocabNotifSettings({
    this.enabled      = false,
    this.startHour    = 6,
    this.startMinute  = 0,
    this.endHour      = 21,
    this.endMinute    = 0,
    this.dailyCount   = 10,
    List<int>? activeDays,
    this.groqApiKey   = '',
  }) : activeDays = activeDays ?? [0, 1, 2, 3, 4];

  Map<String, dynamic> toJson() => {
        'enabled'     : enabled,
        'startHour'   : startHour,
        'startMinute' : startMinute,
        'endHour'     : endHour,
        'endMinute'   : endMinute,
        'dailyCount'  : dailyCount,
        'activeDays'  : activeDays,
        'groqApiKey'  : groqApiKey,
      };

  factory VocabNotifSettings.fromJson(Map<String, dynamic> j) =>
      VocabNotifSettings(
        enabled     : j['enabled']     as bool?   ?? false,
        startHour   : j['startHour']   as int?    ?? 6,
        startMinute : j['startMinute'] as int?    ?? 0,
        endHour     : j['endHour']     as int?    ?? 21,
        endMinute   : j['endMinute']   as int?    ?? 0,
        dailyCount  : j['dailyCount']  as int?    ?? 10,
        activeDays  : (j['activeDays'] as List?)?.cast<int>() ?? [0, 1, 2, 3, 4],
        groqApiKey  : j['groqApiKey']  as String? ?? '',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Service singleton
// ─────────────────────────────────────────────────────────────────────────────

class VocabNotifService {
  static final VocabNotifService instance = VocabNotifService._();
  VocabNotifService._();

  static const _boxName     = 'vocab_notif_data';
  static const _settingsKey = 'settings_v1';
  static const _wordBankKey = 'word_bank_v1';
  static const _kBaseId     = 1000;
  static const _kMaxId      = 1999;
  static const _kGroqUrl    = 'https://api.groq.com/openai/v1/chat/completions';
  static const _kGroqModel  = 'llama-3.3-70b-versatile';

  final _plugin = FlutterLocalNotificationsPlugin();
  VocabNotifSettings settings = VocabNotifSettings();
  List<VocabWord>    _wordBank = [];
  bool               _initialized      = false;

  // BUG-VN07: Tracks whether SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM is granted.
  // When true  → exactAllowWhileIdle  → each notification fires at its exact time
  // When false → inexactAllowWhileIdle → Android batches them (2-3 together) ❌
  bool _exactAlarmsGranted = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Public getters
  // ─────────────────────────────────────────────────────────────────────────

  int             get wordBankSize       => _wordBank.length;
  List<VocabWord> get wordBank           => List.unmodifiable(_wordBank);
  bool            get exactAlarmsGranted => _exactAlarmsGranted;

  // ─────────────────────────────────────────────────────────────────────────
  // Init
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    tzData.initializeTimeZones();

    // BUG-VN05 FIX: Explicitly set IST so zonedSchedule fires at correct
    // Indian time. Without this tz.local defaults to UTC → 5:30 hr offset.
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      debugPrint('[VocabNotif] Timezone → IST (Asia/Kolkata)');
    } catch (e) {
      debugPrint('[VocabNotif] IST set failed, using device default: $e');
    }

    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<String>(_boxName);
    }
    _loadFromHive();

    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'vocab_learning',
            'Vocab Notifications',
            description    : 'BeatFlow daily vocabulary learning',
            importance     : Importance.high,
            playSound      : true,
            enableVibration: true,
          ),
        );

    // BUG-VN07: Check exact alarm permission on startup so _exactAlarmsGranted
    // is always up-to-date before the first scheduleNext() call.
    await _refreshExactAlarmStatus();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUG-VN07: Exact alarm permission helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Silently checks if exact alarms can be scheduled. Updates internal flag.
  Future<void> _refreshExactAlarmStatus() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      _exactAlarmsGranted = true; // Non-Android platform
      return;
    }
    try {
      _exactAlarmsGranted =
          await android.canScheduleExactNotifications() ?? false;
      debugPrint(
          '[VocabNotif] Exact alarms granted: $_exactAlarmsGranted');
    } catch (_) {
      _exactAlarmsGranted = false;
    }
  }

  /// Opens Android system settings so user can grant SCHEDULE_EXACT_ALARM.
  /// Call this from Settings screen when exact alarms are not granted.
  /// After user returns to app, call [recheckExactAlarmPermission()].
  Future<void> requestExactAlarmPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    try {
      await android.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('[VocabNotif] requestExactAlarmsPermission error: $e');
    }
  }

  /// Call this when app resumes (AppLifecycleState.resumed) to re-check
  /// if user granted exact alarm permission in system settings.
  Future<void> recheckExactAlarmPermission() async {
    final before = _exactAlarmsGranted;
    await _refreshExactAlarmStatus();
    // If just granted → reschedule so notifications become exact
    if (!before && _exactAlarmsGranted && settings.enabled) {
      debugPrint(
          '[VocabNotif] Exact alarm just granted → rescheduling...');
      await scheduleNext(daysAhead: 7);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Hive persistence
  // ─────────────────────────────────────────────────────────────────────────

  void _loadFromHive() {
    try {
      final box = Hive.box<String>(_boxName);

      final sJson = box.get(_settingsKey);
      if (sJson != null) {
        settings = VocabNotifSettings.fromJson(
            jsonDecode(sJson) as Map<String, dynamic>);
      }

      final wJson = box.get(_wordBankKey);
      if (wJson != null) {
        final list = jsonDecode(wJson) as List;
        _wordBank = list
            .map((e) => VocabWord.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[VocabNotif] Hive load error: $e');
    }
  }

  Future<void> saveSettings() async {
    final box = Hive.box<String>(_boxName);
    await box.put(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> _saveWordBank() async {
    final box = Hive.box<String>(_boxName);
    await box.put(
      _wordBankKey,
      jsonEncode(_wordBank.map((w) => w.toJson()).toList()),
    );
  }

  /// Clears word bank from memory and Hive.
  Future<void> clearWordBank() async {
    _wordBank = [];
    await _saveWordBank();
    debugPrint('[VocabNotif] Word bank cleared');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUG-VN01 FIX: Word bank generation with retry logic
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns null on success, error string on failure.
  Future<String?> generateWordBank({int count = 60}) async {
    final apiKey = settings.groqApiKey.trim();
    if (apiKey.isEmpty) return 'Pehle Groq API key daalo Settings mein ⬇️';

    final attemptCounts = [count, max(20, count ~/ 2), 20];

    for (int attempt = 0; attempt < 3; attempt++) {
      final tryCount = attemptCounts[attempt];
      debugPrint('[VocabNotif] Attempt ${attempt + 1}/3 ($tryCount words)...');

      try {
        final result = await _attemptGenerate(apiKey, tryCount);
        if (result == null) return null;

        debugPrint('[VocabNotif] Attempt ${attempt + 1} failed: $result');
        if (attempt < 2) await Future.delayed(Duration(seconds: attempt + 1));
        else return result;
      } catch (e) {
        debugPrint('[VocabNotif] Attempt ${attempt + 1} exception: $e');
        if (attempt == 2) return 'Error: $e';
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }
    return 'Word generation failed. Dobara try karo.';
  }

  // BUG-VN06 FIX: Complete implementation — was truncated in original.
  Future<String?> _attemptGenerate(String apiKey, int count) async {
    final prompt = '''
Generate $count English vocabulary words for SSC CGL exam preparation.
Return ONLY a valid JSON array — no markdown fences, no extra text.
The JSON MUST be complete and valid.

Format:
[
  {
    "word": "abate",
    "hindiSentence": "Aaj Motu ne apna gussa abate kiya — thanda pada thoda",
    "hindiMeaning": "kum karna / ghaTana"
  }
]

Rules:
- Mix: synonyms/antonyms vocab, one-word substitutions, SSC previous year words
- hindiSentence: funny/relatable Hinglish sentence using the exact word naturally
- hindiMeaning: 3-5 words max, concise Hindi meaning
- No duplicate words
- RETURN ONLY THE JSON ARRAY. Nothing else.
''';

    try {
      final response = await http
          .post(
            Uri.parse(_kGroqUrl),
            headers: {
              'Content-Type' : 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model'      : _kGroqModel,
              'messages'   : [
                {'role': 'user', 'content': prompt}
              ],
              'max_tokens' : 4096,
              'temperature': 0.7,
              'stream'     : false,
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return 'API Error ${response.statusCode}: '
            '${body['error']?['message'] ?? 'Unknown'}';
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      String raw = (data['choices'][0]['message']['content'] as String).trim();

      // Strip markdown fences if present
      if (raw.startsWith('```')) {
        raw = raw.replaceAll(RegExp(r'```(?:json)?'), '').trim();
      }

      // Extract array if surrounded by other text
      if (!raw.startsWith('[')) {
        final match = RegExp(r'\[[\s\S]*\]').firstMatch(raw);
        if (match == null) return 'JSON array nahi mili response mein.';
        raw = match.group(0)!;
      }

      final List<dynamic> parsed;
      try {
        parsed = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        final preview = raw.length > 100 ? '${raw.substring(0, 100)}...' : raw;
        return 'JSON parse fail: $preview';
      }

      final words = parsed
          .map((e) {
            try {
              return VocabWord.fromJson(e as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<VocabWord>()
          .where((w) => w.word.isNotEmpty && w.hindiMeaning.isNotEmpty)
          .toList();

      if (words.isEmpty) return 'Koi valid word nahi mila. Retry...';

      final existingWords = _wordBank.map((w) => w.word.toLowerCase()).toSet();
      final newWords = words
          .where((w) => !existingWords.contains(w.word.toLowerCase()))
          .toList();
      _wordBank = [..._wordBank, ...newWords];

      await _saveWordBank();
      debugPrint(
          '[VocabNotif] Bank: ${_wordBank.length} total (+${newWords.length} new)');
      return null;
    } on TimeoutException {
      return 'Timeout. Network slow hai, retry karo.';
    } on Exception catch (e) {
      return 'Exception: $e';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Scheduling helpers
  // ─────────────────────────────────────────────────────────────────────────

  List<VocabWord> _pickWords(int count) {
    if (_wordBank.isEmpty) return [];
    final shuffled = List<VocabWord>.from(_wordBank)..shuffle(Random());
    return shuffled.take(min(count, shuffled.length)).toList();
  }

  List<DateTime> _buildTimesForDate(DateTime date) {
    final count    = settings.dailyCount;
    final startMin = settings.startHour   * 60 + settings.startMinute;
    final endMin   = settings.endHour     * 60 + settings.endMinute;
    final window   = endMin - startMin;

    if (window <= 0 || count <= 0) return [];

    // Cap to window capacity — at most 1 notification per minute
    final effectiveCount = min(count, window);
    final interval       = window / effectiveCount;
    final times          = <DateTime>[];

    for (int i = 0; i < effectiveCount; i++) {
      final totalMin = (startMin + i * interval).round();
      times.add(DateTime(
        date.year, date.month, date.day,
        totalMin ~/ 60,
        totalMin  % 60,
      ));
    }
    return times;
  }

  bool _isDayActive(DateTime date) =>
      settings.activeDays.contains(date.weekday - 1);

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  Future<int> getPendingCount() async {
    final all = await _plugin.pendingNotificationRequests();
    return all.where((n) => n.id >= _kBaseId && n.id <= _kMaxId).length;
  }

  Future<void> cancelAll() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      if (n.id >= _kBaseId && n.id <= _kMaxId) {
        await _plugin.cancel(n.id);
      }
    }
    debugPrint('[VocabNotif] All cancelled');
  }

  /// BUG-VN07 FIX + BUG-VN08 FIX:
  ///
  /// VN07 — Exact alarms: When _exactAlarmsGranted is true, each notification
  ///   fires at its own scheduled time (exact). When false, Android batches
  ///   multiple inexact alarms together → 2-3 come at once. ❌
  ///
  /// VN08 — Auto word bank: If word bank is empty and API key exists, auto-
  ///   generate before scheduling. User doesn't need to do it manually.
  Future<int> scheduleNext({int daysAhead = 7}) async {
    // BUG-VN08: Auto-generate word bank if empty — no manual step needed
    if (_wordBank.isEmpty && settings.groqApiKey.trim().isNotEmpty) {
      debugPrint('[VocabNotif] Word bank empty → auto-generating...');
      final err = await generateWordBank(count: 60);
      if (err != null) {
        debugPrint('[VocabNotif] Auto-generate failed: $err');
      }
    }

    if (_wordBank.isEmpty) return 0;

    // Refresh exact alarm status before scheduling
    await _refreshExactAlarmStatus();

    await cancelAll();

    final now   = DateTime.now();
    int   idCtr = _kBaseId;
    int   total = 0;

    debugPrint(
        '[VocabNotif] Scheduling with ${_exactAlarmsGranted ? "EXACT" : "INEXACT"} alarms');

    for (int d = 0; d < daysAhead; d++) {
      final date = now.add(Duration(days: d));
      if (!_isDayActive(date)) continue;

      final times = _buildTimesForDate(date);
      final words = _pickWords(times.length);

      for (int i = 0; i < words.length && i < times.length; i++) {
        final dt = times[i];
        if (dt.isBefore(now)) continue;
        if (idCtr > _kMaxId) break;

        // BUG-VN05 FIX: tz.local is now IST (set in init())
        final tzDt = tz.TZDateTime.from(dt, tz.local);
        final w    = words[i];
        final body = '${w.hindiSentence}\n\n💡 Meaning: ${w.hindiMeaning}';

        try {
          await _plugin.zonedSchedule(
            idCtr++,
            '📚 ${w.word.toUpperCase()}',
            body,
            tzDt,
            NotificationDetails(
              android: AndroidNotificationDetails(
                'vocab_learning',
                'Vocab Notifications',
                channelDescription: 'BeatFlow daily vocabulary',
                importance        : Importance.high,
                priority          : Priority.high,
                icon              : '@drawable/ic_notification',
                styleInformation  : BigTextStyleInformation(
                  body,
                  contentTitle: '📚 ${w.word.toUpperCase()}',
                  summaryText : 'SSC CGL Vocab — BeatFlow',
                ),
                ticker: '${w.word} — ${w.hindiMeaning}',
              ),
            ),
            // BUG-VN07 FIX: Use exact mode when permission granted.
            // exactAllowWhileIdle → fires at precise scheduled time even in Doze
            // inexactAllowWhileIdle → Android batches alarms → 2-3 together ❌
            androidScheduleMode: _exactAlarmsGranted
                ? AndroidScheduleMode.exactAllowWhileIdle
                : AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          total++;
        } catch (e) {
          debugPrint('[VocabNotif] Schedule error id=${idCtr - 1}: $e');
        }
      }
    }

    debugPrint(
        '[VocabNotif] Scheduled $total notifications '
        '(${_exactAlarmsGranted ? "EXACT ✅" : "INEXACT ⚠️"})');
    return total;
  }

  Future<void> sendTestNotification() async {
    if (_wordBank.isEmpty) return;
    final w        = _wordBank[Random().nextInt(_wordBank.length)];
    final testBody = '${w.hindiSentence}\n\n💡 Meaning: ${w.hindiMeaning}';

    await _plugin.show(
      999,
      '📚 Test — ${w.word.toUpperCase()}',
      testBody,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'vocab_learning',
          'Vocab Notifications',
          importance      : Importance.high,
          priority        : Priority.high,
          icon            : '@drawable/ic_notification',
          styleInformation: BigTextStyleInformation(
            testBody,
            contentTitle: '📚 ${w.word.toUpperCase()} (Test)',
            summaryText : 'SSC CGL Vocab — BeatFlow',
          ),
        ),
      ),
    );
  }

  Future<void> refreshIfNeeded() async {
    if (!settings.enabled || _wordBank.isEmpty) return;
    final pending = await getPendingCount();
    if (pending < settings.dailyCount) {
      await scheduleNext(daysAhead: 7);
    }
  }

  // BUG-VN02 FIX: Only request notification permission.
  // BUG-VN07: Also requests exact alarm permission — stores result in
  // _exactAlarmsGranted so scheduleNext() can use the right mode.
  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      _exactAlarmsGranted = true;
      return true;
    }

    // Step 1: Notification permission (Android 13+)
    final notifGranted =
        await android.requestNotificationsPermission() ?? false;

    // Step 2: Exact alarm permission.
    // On Android 12 (API 31-32) → opens system settings page.
    // On Android 13+ with USE_EXACT_ALARM in manifest → auto-granted silently.
    try {
      await android.requestExactAlarmsPermission();
    } catch (_) {
      // Older Android versions → ignore, inexact mode will be used
    }

    // Step 3: Check actual status after request
    await _refreshExactAlarmStatus();

    return notifGranted;
  }

  /// Check if notification permission is granted (without requesting).
  Future<bool> areNotificationsEnabled() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.areNotificationsEnabled() ?? false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Next notification time helpers
  // ─────────────────────────────────────────────────────────────────────────

  DateTime? getNextNotificationTime() {
    if (!settings.enabled || _wordBank.isEmpty) return null;
    final now = DateTime.now();
    for (int d = 0; d < 8; d++) {
      final date  = now.add(Duration(days: d));
      if (!_isDayActive(date)) continue;
      final times = _buildTimesForDate(date);
      for (final time in times) {
        if (time.isAfter(now)) return time;
      }
    }
    return null;
  }

  /// Human-readable label: "Aaj 6:00 AM", "Kal 6:00 AM", "Mangalwar 6:00 AM"
  String getNextNotificationLabel() {
    final next = getNextNotificationTime();
    if (next == null) return '';

    final now     = DateTime.now();
    final h       = next.hour % 12 == 0 ? 12 : next.hour % 12;
    final m       = next.minute.toString().padLeft(2, '0');
    final ampm    = next.hour < 12 ? 'AM' : 'PM';
    final timeStr = '$h:$m $ampm';

    if (next.day == now.day) {
      return 'Aaj $timeStr ko';
    } else if (next.day == now.add(const Duration(days: 1)).day) {
      return 'Kal $timeStr ko';
    } else {
      const days = [
        '', 'Somwar', 'Mangalwar', 'Budhwar',
        'Guruwar', 'Shukrawar', 'Shaniwaar', 'Itwaar',
      ];
      return '${days[next.weekday]} $timeStr ko';
    }
  }
}
