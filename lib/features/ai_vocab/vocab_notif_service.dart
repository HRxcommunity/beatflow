// ╔══════════════════════════════════════════════════════════════╗
// ║  Vocab Notification Service                                  ║
// ║  AI se words generate karo → din bhar scheduled bhejo       ║
// ╚══════════════════════════════════════════════════════════════╝

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
        'word': word,
        'hindiSentence': hindiSentence,
        'hindiMeaning': hindiMeaning,
      };

  factory VocabWord.fromJson(Map<String, dynamic> j) => VocabWord(
        word: (j['word'] as String? ?? '').trim(),
        hindiSentence: (j['hindiSentence'] as String? ?? '').trim(),
        hindiMeaning: (j['hindiMeaning'] as String? ?? '').trim(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class VocabNotifSettings {
  bool enabled;
  int startHour;    // 0-23
  int startMinute;  // 0-59
  int endHour;      // 0-23
  int endMinute;    // 0-59
  int dailyCount;   // words per day
  List<int> activeDays; // 0=Mon … 6=Sun
  String groqApiKey;

  VocabNotifSettings({
    this.enabled      = false,
    this.startHour    = 6,
    this.startMinute  = 0,
    this.endHour      = 21,
    this.endMinute    = 0,
    this.dailyCount   = 10,
    List<int>? activeDays,
    this.groqApiKey   = '',
  }) : activeDays = activeDays ?? [0, 1, 2, 3, 4]; // Mon-Fri default

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
  // ── Singleton ────────────────────────────────────────────────────────────
  static final VocabNotifService instance = VocabNotifService._();
  VocabNotifService._();

  // ── Constants ────────────────────────────────────────────────────────────
  static const _boxName      = 'vocab_notif_data';
  static const _settingsKey  = 'settings_v1';
  static const _wordBankKey  = 'word_bank_v1';
  static const _kBaseId      = 1000; // IDs 1000-1999 reserved for vocab
  static const _kMaxId       = 1999;
  static const _kGroqUrl     =
      'https://api.groq.com/openai/v1/chat/completions';
  static const _kGroqModel   = 'llama-3.3-70b-versatile';

  // ── State ────────────────────────────────────────────────────────────────
  final _plugin = FlutterLocalNotificationsPlugin();
  VocabNotifSettings settings = VocabNotifSettings();
  List<VocabWord> _wordBank  = [];
  bool _initialized          = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Init
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Timezone setup
    tzData.initializeTimeZones();

    // Hive box
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<String>(_boxName);
    }
    _loadFromHive();

    // Notifications init
    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );

    // Notification channel
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'vocab_learning',
            'Vocab Notifications',
            description : 'BeatFlow daily vocabulary learning',
            importance  : Importance.high,
            playSound   : true,
            enableVibration: true,
          ),
        );
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

  // ─────────────────────────────────────────────────────────────────────────
  // Word bank generation via Groq
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns null on success, error string on failure.
  Future<String?> generateWordBank({int count = 60}) async {
    final apiKey = settings.groqApiKey.trim();
    if (apiKey.isEmpty) return 'Pehle Groq API key daalo Settings mein ⬇️';

    final prompt = '''
Generate $count English vocabulary words for SSC CGL exam preparation.
Return ONLY a valid JSON array — no markdown fences, no extra text.

Format:
[
  {
    "word": "abate",
    "hindiSentence": "Aaj Motu ne apna abate kiya gussa — thoda thanda pada",
    "hindiMeaning": "kum karna / ghaTana"
  }
]

Rules:
• Words must be SSC CGL level (intermediate-advanced)
• hindiSentence: Funny Hinglish sentence using the ENGLISH word naturally
  – Use characters like Motu, Ramu, Seema, Bhai, Teacher, Boss etc.
  – Keep it short (1-2 lines) and relatable/funny
  – Include the English word AS-IS inside the sentence
• hindiMeaning: 2-5 word Hindi translation only
• Mix nouns, verbs, adjectives, adverbs
• No duplicate words
''';

    try {
      final resp = await http
          .post(
            Uri.parse(_kGroqUrl),
            headers: {
              'Content-Type' : 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model'      : _kGroqModel,
              'max_tokens' : 4096,
              'temperature': 0.7,
              'messages'   : [
                {'role': 'user', 'content': prompt}
              ],
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (resp.statusCode != 200) {
        final errBody = jsonDecode(resp.body);
        final msg = errBody['error']?['message'] ?? 'Unknown error';
        return 'Groq API Error ${resp.statusCode}: $msg';
      }

      final data   = jsonDecode(resp.body);
      var   rawText = (data['choices'][0]['message']['content'] as String).trim();

      // Strip markdown fences if present
      rawText = rawText
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'),     '')
          .trim();

      // Find JSON array bounds (robust against trailing prose)
      final start = rawText.indexOf('[');
      final end   = rawText.lastIndexOf(']');
      if (start == -1 || end == -1 || end <= start) {
        return 'Invalid JSON response from Groq';
      }
      rawText = rawText.substring(start, end + 1);

      final list    = jsonDecode(rawText) as List;
      _wordBank = list
          .map((e) => VocabWord.fromJson(e as Map<String, dynamic>))
          .where((w) => w.word.isNotEmpty && w.hindiMeaning.isNotEmpty)
          .toList();

      await _saveWordBank();
      debugPrint('[VocabNotif] Generated ${_wordBank.length} words');
      return null; // success
    } catch (e) {
      debugPrint('[VocabNotif] Generation error: $e');
      return 'Error: $e';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Scheduling helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Pick [count] random words from bank.
  List<VocabWord> _pickWords(int count) {
    if (_wordBank.isEmpty) return [];
    final shuffled = List<VocabWord>.from(_wordBank)..shuffle(Random());
    return shuffled.take(min(count, shuffled.length)).toList();
  }

  /// Build evenly-spaced DateTime list for a given date.
  List<DateTime> _buildTimesForDate(DateTime date) {
    final count    = settings.dailyCount;
    final startMin = settings.startHour   * 60 + settings.startMinute;
    final endMin   = settings.endHour     * 60 + settings.endMinute;
    final window   = endMin - startMin;

    if (window <= 0 || count <= 0) return [];

    final interval = window / count; // fractional minutes between slots
    final times    = <DateTime>[];

    for (int i = 0; i < count; i++) {
      final totalMin = (startMin + i * interval).round();
      times.add(DateTime(
        date.year, date.month, date.day,
        totalMin ~/ 60,
        totalMin  % 60,
      ));
    }
    return times;
  }

  /// settings.activeDays uses 0=Mon…6=Sun; DateTime.weekday uses 1=Mon…7=Sun.
  bool _isDayActive(DateTime date) =>
      settings.activeDays.contains(date.weekday - 1);

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  int get wordBankSize => _wordBank.length;

  Future<int> getPendingCount() async {
    final all = await _plugin.pendingNotificationRequests();
    return all.where((n) => n.id >= _kBaseId && n.id <= _kMaxId).length;
  }

  /// Cancel all scheduled vocab notifications.
  Future<void> cancelAll() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      if (n.id >= _kBaseId && n.id <= _kMaxId) {
        await _plugin.cancel(n.id);
      }
    }
    debugPrint('[VocabNotif] All cancelled');
  }

  /// Schedule vocabulary notifications for the next [daysAhead] days.
  /// Returns total count of successfully scheduled notifications.
  Future<int> scheduleNext({int daysAhead = 7}) async {
    if (_wordBank.isEmpty) return 0;

    await cancelAll();

    final now    = DateTime.now();
    int   idCtr  = _kBaseId;
    int   total  = 0;

    for (int d = 0; d < daysAhead; d++) {
      final date = now.add(Duration(days: d));
      if (!_isDayActive(date)) continue;

      final times = _buildTimesForDate(date);
      final words = _pickWords(times.length);

      for (int i = 0; i < words.length && i < times.length; i++) {
        final dt = times[i];
        if (dt.isBefore(now)) continue; // skip already-past slots

        final tzDt = tz.TZDateTime.from(dt, tz.local);
        final w    = words[i];
        final body = '${w.hindiSentence}\n\n'
                     '💡 ${w.word} = ${w.hindiMeaning}';

        try {
          await _plugin.zonedSchedule(
            idCtr++,
            '📚 ${w.word.toUpperCase()}',
            body,
            tzDt,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'vocab_learning',
                'Vocab Notifications',
                channelDescription: 'BeatFlow daily vocabulary',
                importance        : Importance.high,
                priority          : Priority.high,
                icon              : '@drawable/ic_notification',
                styleInformation  : BigTextStyleInformation(''),
              ),
            ),
            androidScheduleMode:
                AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          total++;
        } catch (e) {
          debugPrint('[VocabNotif] Schedule error id=$idCtr: $e');
        }
      }
    }

    debugPrint('[VocabNotif] Scheduled $total notifications');
    return total;
  }

  /// Send a test notification immediately.
  Future<void> sendTestNotification() async {
    if (_wordBank.isEmpty) return;
    final w = _wordBank[Random().nextInt(_wordBank.length)];
    await _plugin.show(
      999,
      '📚 Test — ${w.word.toUpperCase()}',
      '${w.hindiSentence}\n\n💡 ${w.word} = ${w.hindiMeaning}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'vocab_learning',
          'Vocab Notifications',
          importance       : Importance.high,
          priority         : Priority.high,
          icon             : '@drawable/ic_notification',
          styleInformation : BigTextStyleInformation(''),
        ),
      ),
    );
  }

  /// Called on app open — refreshes schedule if running low.
  Future<void> refreshIfNeeded() async {
    if (!settings.enabled || _wordBank.isEmpty) return;
    final pending = await getPendingCount();
    if (pending < settings.dailyCount) {
      await scheduleNext(daysAhead: 7);
    }
  }

  /// Request notification + exact-alarm permissions (Android 13 / 12+).
  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;

    final notifGranted =
        await android.requestNotificationsPermission() ?? false;
    final alarmGranted =
        await android.requestExactAlarmsPermission()   ?? false;

    return notifGranted && alarmGranted;
  }
}
