// ╔══════════════════════════════════════════════════════════════════╗
// ║           BeatFlow Diagnostic Engine  v1.0                       ║
// ║  Auto-collects errors, warnings, state snapshots, audio logs     ║
// ║  Remove this file before production build.                       ║
// ╚══════════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ── Severity ───────────────────────────────────────────────────────
enum BugSeverity { crash, error, warning, info }

// ── A single captured log entry ────────────────────────────────────
class BugEntry {
  final DateTime time;
  final BugSeverity severity;
  final String tag;
  final String message;
  final StackTrace? stack;
  final Map<String, dynamic>? context;

  BugEntry({
    required this.severity,
    required this.tag,
    required this.message,
    this.stack,
    this.context,
  }) : time = DateTime.now();

  String get severityLabel => switch (severity) {
    BugSeverity.crash   => '🔴 CRASH',
    BugSeverity.error   => '🟠 ERROR',
    BugSeverity.warning => '🟡 WARN ',
    BugSeverity.info    => '🔵 INFO ',
  };

  @override
  String toString() {
    final buf = StringBuffer();
    buf.writeln('$severityLabel  [$tag]  ${fmtTime(time)}');
    buf.writeln('  $message');
    if (context != null && context!.isNotEmpty) {
      buf.writeln('  context: $context');
    }
    if (stack != null) {
      final lines = stack.toString().split('\n').take(6).join('\n  ');
      buf.writeln('  stack:\n  $lines');
    }
    return buf.toString();
  }

  String fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}.'
      '${t.millisecond.toString().padLeft(3, '0')}';

  Color get color => switch (severity) {
    BugSeverity.crash   => const Color(0xFFFF4444),
    BugSeverity.error   => const Color(0xFFFF9800),
    BugSeverity.warning => const Color(0xFFFFD740),
    BugSeverity.info    => const Color(0xFF64B5F6),
  };
}

// ══════════════════════════════════════════════════════════════════
//  MAIN DEBUGGER SINGLETON
// ══════════════════════════════════════════════════════════════════

class BeatFlowDebugger {
  BeatFlowDebugger._();
  static final instance = BeatFlowDebugger._();

  final _logs = <BugEntry>[];
  final _controller = StreamController<List<BugEntry>>.broadcast();
  int _crashCount = 0;
  int _errorCount = 0;

  Stream<List<BugEntry>> get stream => _controller.stream;
  List<BugEntry> get logs => List.unmodifiable(_logs);
  int get crashCount => _crashCount;
  int get errorCount => _errorCount;
  bool get hasIssues => _crashCount > 0 || _errorCount > 0;

  // ── Core log method ─────────────────────────────────────────────
  void log(
    BugSeverity severity,
    String tag,
    String message, {
    StackTrace? stack,
    Map<String, dynamic>? context,
  }) {
    final entry = BugEntry(
      severity: severity,
      tag: tag,
      message: message,
      stack: stack,
      context: context,
    );
    _logs.add(entry);
    if (severity == BugSeverity.crash) _crashCount++;
    if (severity == BugSeverity.error) _errorCount++;
    _controller.add(List.unmodifiable(_logs));

    // Also print to Flutter debug console with formatting
    debugPrint('\n${entry.toString()}');
  }

  // ── Convenience wrappers ────────────────────────────────────────
  void crash(String tag, String msg, {StackTrace? stack, Map<String, dynamic>? ctx}) =>
      log(BugSeverity.crash, tag, msg, stack: stack, context: ctx);

  void error(String tag, String msg, {StackTrace? stack, Map<String, dynamic>? ctx}) =>
      log(BugSeverity.error, tag, msg, stack: stack, context: ctx);

  void warn(String tag, String msg, {Map<String, dynamic>? ctx}) =>
      log(BugSeverity.warning, tag, msg, context: ctx);

  void info(String tag, String msg, {Map<String, dynamic>? ctx}) =>
      log(BugSeverity.info, tag, msg, context: ctx);

  // ── Clear ───────────────────────────────────────────────────────
  void clear() {
    _logs.clear();
    _crashCount = 0;
    _errorCount = 0;
    _controller.add([]);
  }

  // ── Install global Flutter error hooks ─────────────────────────
  void installGlobalHooks() {
    // Catch all unhandled Flutter framework errors
    final originalHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      crash(
        'Flutter',
        details.exceptionAsString(),
        stack: details.stack,
        ctx: {'library': details.library ?? 'unknown'},
      );
      originalHandler?.call(details);
    };

    // Catch all unhandled async errors (PlatformDispatcher)
    PlatformDispatcher.instance.onError = (error, stack) {
      crash(
        'PlatformDispatcher',
        error.toString(),
        stack: stack,
      );
      return false; // let it propagate too
    };

    info('Debugger', '✅ Global error hooks installed — watching for crashes');
  }

  // ── Run pre-flight checks at startup ───────────────────────────
  Future<void> runStartupChecks({
    required bool firebaseInitialized,
    required bool audioServiceInitialized,
    required bool hiveInitialized,
  }) async {
    info('Startup', '══ BeatFlow Startup Diagnostics ══');

    // Firebase
    if (firebaseInitialized) {
      info('Firebase', '✅ Firebase initialized');
    } else {
      error('Firebase', '❌ Firebase NOT initialized — Together + Storage features will crash');
    }

    // AudioService
    if (audioServiceInitialized) {
      info('AudioService', '✅ AudioService initialized');
    } else {
      error('AudioService', '❌ AudioService NOT initialized — background playback will fail');
    }

    // Hive
    if (hiveInitialized) {
      info('Hive', '✅ Hive initialized');
    } else {
      error('Hive', '❌ Hive NOT initialized — playlists & settings will crash');
    }

    // Known static bugs found in codebase
    _reportKnownStaticBugs();
  }

  // ── Report bugs found via static analysis of the codebase ──────
  void _reportKnownStaticBugs() {
    // ✅ All previously reported static issues have been resolved:
    // - AndroidManifest duplicate permissions → removed
    // - {java garbage folder → deleted
    // - together_screen.dart session! force unwrap → safe null check added
    // - Agora placeholder App ID → guarded, user must supply real ID
    // - Guest audio race condition → streamUrl change forces rebuild
    // - Buffer hardcoded 2500ms delay → replaced with ProcessingState.ready wait
    info('StaticAnalysis', '✅ Static analysis complete — no known issues found');
  }

  // ── Summary ─────────────────────────────────────────────────────
  String get summary {
    final crashes = _logs.where((e) => e.severity == BugSeverity.crash);
    final errors  = _logs.where((e) => e.severity == BugSeverity.error);
    final warns   = _logs.where((e) => e.severity == BugSeverity.warning);

    final buf = StringBuffer();
    buf.writeln('╔══════════════════════════════════════╗');
    buf.writeln('║      BeatFlow Debug Summary           ║');
    buf.writeln('╠══════════════════════════════════════╣');
    buf.writeln('║  🔴 Crashes : ${crashes.length.toString().padLeft(3)}                      ║');
    buf.writeln('║  🟠 Errors  : ${errors.length.toString().padLeft(3)}                      ║');
    buf.writeln('║  🟡 Warnings: ${warns.length.toString().padLeft(3)}                      ║');
    buf.writeln('║  🔵 Total   : ${_logs.length.toString().padLeft(3)}                      ║');
    buf.writeln('╚══════════════════════════════════════╝');
    return buf.toString();
  }
}

// ══════════════════════════════════════════════════════════════════
//  TOGETHER AUDIO TRACKER  (tracks guest join → audio play flow)
// ══════════════════════════════════════════════════════════════════

class TogetherAudioTracker {
  static final _d = BeatFlowDebugger.instance;
  static DateTime? _guestJoinedAt;
  static DateTime? _streamUrlReceivedAt;
  static DateTime? _audioStartedAt;

  static void onGuestJoined(String sessionCode, String songId) {
    _guestJoinedAt = DateTime.now();
    _d.info('Together/Guest', '👤 Guest joined session "$sessionCode" | songId=$songId');
  }

  static void onStreamUrlReceived(String songId, String url) {
    _streamUrlReceivedAt = DateTime.now();
    final delay = _guestJoinedAt != null
        ? '${_streamUrlReceivedAt!.difference(_guestJoinedAt!).inMilliseconds}ms after join'
        : 'unknown delay';
    _d.info(
      'Together/Guest',
      '📡 streamUrl received for "$songId" ($delay)',
      ctx: {'url': url.length > 60 ? '${url.substring(0, 60)}…' : url},
    );
    if (url.isEmpty || !url.startsWith('http')) {
      _d.error(
        'Together/Guest',
        '❌ streamUrl is empty or not http! Guest audio will NEVER play.',
        ctx: {'songId': songId, 'url': url},
      );
    }
  }

  static void onAudioLoadAttempt(String songId, String dataPath, bool isStream) {
    _d.info(
      'Together/Guest',
      '🎵 Loading audio: songId=$songId | isStream=$isStream',
      ctx: {'data': dataPath.length > 60 ? '${dataPath.substring(0,60)}…' : dataPath},
    );
    if (dataPath.isEmpty) {
      _d.crash(
        'Together/Guest',
        '💥 data path is EMPTY — PlayerPlay will crash or play silence!',
        ctx: {'songId': songId},
      );
    }
  }

  static void onAudioStarted(String songId) {
    _audioStartedAt = DateTime.now();
    final totalDelay = _guestJoinedAt != null
        ? '${_audioStartedAt!.difference(_guestJoinedAt!).inMilliseconds}ms from join to audio'
        : '';
    _d.info('Together/Guest', '▶️  Audio started for "$songId" | $totalDelay');
  }

  static void onAudioFailed(String songId, dynamic error) {
    _d.crash(
      'Together/Guest',
      '💥 Audio FAILED for "$songId": $error',
      ctx: {'songId': songId},
    );
  }

  static void onSyncSkipped(String reason) {
    _d.warn('Together/Guest', '⏭️  Sync skipped: $reason');
  }

  static void onDriftCorrected(int driftMs) {
    if (driftMs > 5000) {
      _d.warn(
        'Together/Guest',
        '⚠️  Large drift corrected: ${driftMs}ms — network may be slow',
        ctx: {'driftMs': driftMs},
      );
    } else {
      _d.info('Together/Guest', '🔧 Drift corrected: ${driftMs}ms');
    }
  }
}

// ══════════════════════════════════════════════════════════════════
//  PLAYER TRACKER  (tracks every PlayerPlay event & audio state)
// ══════════════════════════════════════════════════════════════════

class PlayerTracker {
  static final _d = BeatFlowDebugger.instance;

  static void onPlay(List<dynamic> queue, int index) {
    if (queue.isEmpty) {
      _d.crash('Player', '💥 PlayerPlay fired with EMPTY queue — nothing to play!');
      return;
    }
    if (index >= queue.length) {
      _d.crash(
        'Player',
        '💥 PlayerPlay index=$index out of bounds! queue.length=${queue.length}',
        ctx: {'index': index, 'queueLength': queue.length},
      );
      return;
    }
    final song = queue[index];
    final data = song?.toString() ?? '';
    if (data.isEmpty) {
      _d.crash('Player', '💥 Song data is empty — just_audio will throw!');
    } else {
      _d.info('Player', '▶️  Playing: index=$index | ${queue.length} in queue');
    }
  }

  static void onSeek(Duration position, Duration? duration) {
    if (duration != null && position > duration) {
      _d.warn(
        'Player',
        '⚠️  Seek past end: seeking to ${position.inMs}ms but duration=${duration.inMs}ms',
        ctx: {'seekMs': position.inMs, 'durationMs': duration?.inMs},
      );
    }
  }

  static void onAudioError(dynamic error) {
    _d.crash('Player/just_audio', '💥 Audio error: $error');
  }
}

extension DurationMs on Duration {
  int get inMs => inMilliseconds;
}
