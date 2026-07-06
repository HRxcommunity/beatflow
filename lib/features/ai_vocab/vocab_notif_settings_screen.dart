// ╔══════════════════════════════════════════════════════════════╗
// ║  Vocab Notification Settings Screen                          ║
// ║  CHANGE-1: Removed API key card, word bank card             ║
// ║            Enable toggle → auto permission + generate        ║
// ║            Set button → auto generate + reschedule           ║
// ╚══════════════════════════════════════════════════════════════╝

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import 'vocab_notif_service.dart';

class VocabNotifSettingsScreen extends StatefulWidget {
  const VocabNotifSettingsScreen({super.key});

  @override
  State<VocabNotifSettingsScreen> createState() =>
      _VocabNotifSettingsScreenState();
}

class _VocabNotifSettingsScreenState extends State<VocabNotifSettingsScreen> {
  final _svc           = VocabNotifService.instance;
  final _customWordCtrl = TextEditingController();

  bool    _loading       = false;
  bool    _scheduling    = false;
  bool    _generating    = false;
  int     _pendingCnt    = 0;
  String? _statusMsg;
  bool    _statusIsError = false;
  bool    _notifEnabled  = true;

  static const _dayLabels  = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _wordCounts = [10, 20, 30, 40];

  @override
  void initState() {
    super.initState();
    _refreshPendingCount();
    _checkSystemPermission();
  }

  @override
  void dispose() {
    _customWordCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshPendingCount() async {
    final cnt = await _svc.getPendingCount();
    if (mounted) setState(() => _pendingCnt = cnt);
  }

  Future<void> _checkSystemPermission() async {
    final enabled = await _svc.areNotificationsEnabled();
    if (mounted) setState(() => _notifEnabled = enabled);
  }

  void _showStatus(String msg, {bool error = false}) {
    setState(() {
      _statusMsg     = msg;
      _statusIsError = error;
    });
  }

  void _openSystemNotifSettings() {
    const channel = MethodChannel('beatflow/settings');
    channel.invokeMethod('openNotificationSettings').catchError((_) {
      _showStatus(
        'System Settings > Apps > BeatFlow > Notifications → Enable karo',
        error: false,
      );
    });
  }

  // ── CHANGE-1: Toggle handler — permission first → auto generate → auto schedule
  Future<void> _onToggleEnabled(bool val) async {
    if (val) {
      // Step 1: Request notification permission
      setState(() {
        _loading   = true;
        _statusMsg = null;
      });
      _showStatus('Permission maang rahe hain...');

      final granted = await _svc.requestPermissions();
      if (!granted) {
        setState(() => _loading = false);
        _showStatus(
          'Notification permission nahi mila.\nSystem Settings se enable karo.',
          error: true,
        );
        await _checkSystemPermission();
        return;
      }

      // Step 2: Auto-generate word bank if needed
      if (_svc.wordBankSize == 0) {
        final targetCount = _svc.settings.dailyCount * 7;
        _showStatus('Word bank generate ho raha hai... ⏳ ($targetCount words)');
        final err = await _svc.generateWordBank(count: targetCount);
        if (err != null) {
          setState(() => _loading = false);
          _showStatus(err, error: true);
          return;
        }
      }

      // Step 3: Auto-schedule
      _svc.settings.enabled = true;
      await _svc.saveSettings();
      final n = await _svc.scheduleNext(daysAhead: 7);
      await _refreshPendingCount();
      await _checkSystemPermission();

      setState(() => _loading = false);

      final nextLabel = _svc.getNextNotificationLabel();
      final nextLine  = nextLabel.isNotEmpty
          ? '\n⏰ $nextLabel pehli notification aayegi!'
          : '';
      _showStatus('$n notifications schedule ho gaye! 🎉$nextLine');
    } else {
      _svc.settings.enabled = false;
      await _svc.saveSettings();
      await _svc.cancelAll();
      await _refreshPendingCount();
      _showStatus('Notifications band kar diye ✅');
    }
    setState(() {});
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart
        ? TimeOfDay(
            hour  : _svc.settings.startHour,
            minute: _svc.settings.startMinute,
          )
        : TimeOfDay(
            hour  : _svc.settings.endHour,
            minute: _svc.settings.endMinute,
          );

    final picked = await showTimePicker(
      context    : context,
      initialTime: current,
      builder    : (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary  : Theme.of(ctx).colorScheme.primary,
            surface  : AppTheme.bgCard,
            onSurface: AppTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null) return;
    setState(() {
      if (isStart) {
        _svc.settings.startHour   = picked.hour;
        _svc.settings.startMinute = picked.minute;
      } else {
        _svc.settings.endHour   = picked.hour;
        _svc.settings.endMinute = picked.minute;
      }
    });
    await _svc.saveSettings();
  }

  // ── CHANGE-1: Set button → save count + generate words + reschedule
  Future<void> _onSetWordCount() async {
    final customText = _customWordCtrl.text.trim();
    final int targetCount;

    if (customText.isNotEmpty) {
      final parsed = int.tryParse(customText);
      if (parsed == null || parsed < 1 || parsed > 200) {
        _showStatus('1 se 200 ke beech number daalo', error: true);
        return;
      }
      targetCount = parsed;
    } else {
      targetCount = _svc.settings.dailyCount;
    }

    setState(() {
      _svc.settings.dailyCount = targetCount;
      _generating = true;
      _statusMsg  = null;
    });
    await _svc.saveSettings();
    FocusScope.of(context).unfocus();

    _showStatus('Words generate ho rahe hain... ⏳');
    final err = await _svc.generateWordBank(count: targetCount * 7);

    setState(() => _generating = false);

    if (err != null) {
      _showStatus(err, error: true);
      return;
    }

    _showStatus('${_svc.wordBankSize} words ready! 🎉');

    // Auto reschedule if enabled
    if (_svc.settings.enabled) {
      await _svc.scheduleNext(daysAhead: 7);
      await _refreshPendingCount();
    }
    setState(() {});
  }

  Future<void> _onSchedule() async {
    setState(() {
      _scheduling = true;
      _statusMsg  = null;
    });

    final granted = await _svc.requestPermissions();
    if (!granted) {
      setState(() => _scheduling = false);
      _showStatus(
        'Notification permission nahi mila.\nSystem Settings se enable karo.',
        error: true,
      );
      await _checkSystemPermission();
      return;
    }

    _svc.settings.enabled = true;
    await _svc.saveSettings();

    final n = await _svc.scheduleNext(daysAhead: 7);
    await _refreshPendingCount();
    await _checkSystemPermission();

    setState(() => _scheduling = false);

    if (n == 0) {
      _showStatus(
        'Koi notification schedule nahi hua.\n'
        'Time range check karo ya koi active day select karo.',
        error: true,
      );
    } else {
      final nextLabel = _svc.getNextNotificationLabel();
      final nextLine  = nextLabel.isNotEmpty
          ? '\n⏰ Pehli notification: $nextLabel aayegi!'
          : '';
      _showStatus('✅ $n notifications schedule ho gaye!$nextLine');
    }
  }

  Future<void> _onTestNotification() async {
    if (_svc.wordBankSize == 0) {
      _showStatus('Pehle word bank generate karo', error: true);
      return;
    }
    await _svc.sendTestNotification();
    _showStatus('Test notification bhej diya! 🔔');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: _buildAppBar(accent),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // CHANGE-1 Layout order:
          // 1. Permission warning banner (if off)
          if (!_notifEnabled) ...[
            _buildPermissionWarningBanner(accent),
            const SizedBox(height: 12),
          ],
          // 2. Status banner
          _buildStatusBanner(accent),
          const SizedBox(height: 12),
          // 3. Enable toggle card
          _buildEnableCard(accent),
          const SizedBox(height: 12),
          // 4. Time range card
          _buildTimeRangeCard(accent),
          const SizedBox(height: 12),
          // 5. Active days card
          _buildActiveDaysCard(accent),
          const SizedBox(height: 12),
          // 6. Words per day card
          _buildWordCountCard(accent),
          const SizedBox(height: 12),
          // 7. Schedule + Test buttons (directly after word count)
          _buildActionButtons(accent),
          // 8. Status message
          if (_statusMsg != null) ...[
            const SizedBox(height: 12),
            _buildStatusMessage(accent),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  AppBar _buildAppBar(Color accent) {
    return AppBar(
      backgroundColor : AppTheme.bgCard,
      elevation       : 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded,
            color: AppTheme.textPrimary, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, accent.withOpacity(0.6)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.notifications_active_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text(
            'Vocab Notifications',
            style: TextStyle(
              fontFamily : 'Poppins',
              fontSize   : 16,
              fontWeight : FontWeight.w700,
              color      : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.white.withOpacity(0.07)),
      ),
    );
  }

  // ── Permission Warning ────────────────────────────────────────────────────

  Widget _buildPermissionWarningBanner(Color accent) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notification_important_rounded,
              color: Colors.orange, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔕 System Notifications OFF',
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 13,
                    fontWeight : FontWeight.w700,
                    color      : Colors.orange,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'BeatFlow notifications system settings mein band hain',
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 11,
                    color      : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _openSystemNotifSettings,
            style: TextButton.styleFrom(
              backgroundColor: Colors.orange.withOpacity(0.2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Fix karo',
              style: TextStyle(
                fontFamily : 'Poppins',
                fontSize   : 12,
                fontWeight : FontWeight.w700,
                color      : Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status Banner ─────────────────────────────────────────────────────────

  Widget _buildStatusBanner(Color accent) {
    final enabled   = _svc.settings.enabled;
    final nextLabel = enabled ? _svc.getNextNotificationLabel() : '';
    final bankSize  = _svc.wordBankSize;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: enabled
            ? accent.withOpacity(0.15)
            : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled ? accent.withOpacity(0.4) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: enabled ? accent.withOpacity(0.2) : Colors.white10,
              shape: BoxShape.circle,
            ),
            child: Icon(
              enabled
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
              color: enabled ? accent : AppTheme.textSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enabled ? 'Notifications Active 🟢' : 'Notifications Band 🔴',
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 14,
                    fontWeight : FontWeight.w700,
                    color      : enabled ? accent : AppTheme.textSecondary,
                  ),
                ),
                if (enabled && nextLabel.isNotEmpty)
                  Text(
                    '⏰ $nextLabel pehli notification',
                    style: TextStyle(
                      fontFamily : 'Poppins',
                      fontSize   : 12,
                      fontWeight : FontWeight.w600,
                      color      : accent.withOpacity(0.9),
                    ),
                  )
                else if (enabled)
                  Text(
                    '$_pendingCnt notifications scheduled | $bankSize words ready',
                    style: const TextStyle(
                      fontFamily : 'Poppins',
                      fontSize   : 12,
                      color      : AppTheme.textSecondary,
                    ),
                  )
                else
                  Text(
                    bankSize > 0
                        ? '$bankSize words ready — Enable karo upar se ⬆️'
                        : 'Toggle ON karo — sab automatic ho jayega!',
                    style: const TextStyle(
                      fontFamily : 'Poppins',
                      fontSize   : 12,
                      color      : AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Enable Card ───────────────────────────────────────────────────────────

  Widget _buildEnableCard(Color accent) {
    return _Card(
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color        : accent.withOpacity(0.12),
              borderRadius : BorderRadius.circular(12),
            ),
            child: Icon(Icons.power_settings_new_rounded,
                color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily Vocab Enable',
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 14,
                    fontWeight : FontWeight.w600,
                    color      : AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'ON karo → permission + words + schedule — sab automatic!',
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 11,
                    color      : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Switch(
              value             : _svc.settings.enabled,
              onChanged         : _onToggleEnabled,
              activeColor       : accent,
              inactiveThumbColor: AppTheme.textSecondary,
            ),
        ],
      ),
    );
  }

  // ── Time Range Card ───────────────────────────────────────────────────────

  Widget _buildTimeRangeCard(Color accent) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            icon : Icons.access_time_rounded,
            label: 'Schedule Time Range',
            accent: accent,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _TimeButton(
                  label : 'Start',
                  hour  : _svc.settings.startHour,
                  minute: _svc.settings.startMinute,
                  accent: accent,
                  onTap : () => _pickTime(isStart: true),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.arrow_forward_rounded,
                    color: accent.withOpacity(0.5), size: 20),
              ),
              Expanded(
                child: _TimeButton(
                  label : 'End',
                  hour  : _svc.settings.endHour,
                  minute: _svc.settings.endMinute,
                  accent: accent,
                  onTap : () => _pickTime(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildIntervalPreview(accent),
        ],
      ),
    );
  }

  Widget _buildIntervalPreview(Color accent) {
    final startMin = _svc.settings.startHour   * 60 + _svc.settings.startMinute;
    final endMin   = _svc.settings.endHour     * 60 + _svc.settings.endMinute;
    final window   = endMin - startMin;
    final count    = _svc.settings.dailyCount;

    if (window <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color        : Colors.red.withOpacity(0.08),
          borderRadius : BorderRadius.circular(8),
        ),
        child: const Text(
          '⚠️ End time, Start time se pehle hai!',
          style: TextStyle(
            fontFamily : 'Poppins', fontSize: 11, color: Colors.redAccent),
        ),
      );
    }

    if (count <= 0) return const SizedBox.shrink();

    final effectiveCount = count > window ? window : count;
    final intervalMins   = window / effectiveCount;
    final tooTight       = count > window;

    String intervalStr;
    if (intervalMins < 1) {
      final secs = (intervalMins * 60).round();
      intervalStr = '${secs}sec';
    } else {
      final mins  = intervalMins.round();
      final hours = mins ~/ 60;
      final rem   = mins  % 60;
      intervalStr = hours > 0 ? '${hours}h ${rem}min' : '${rem}min';
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color        : accent.withOpacity(0.08),
            borderRadius : BorderRadius.circular(8),
          ),
          child: Text(
            '⏱ Har $intervalStr mein ek word notification aayega'
            '${tooTight ? " (${effectiveCount}/${count} words)" : ""}',
            style: TextStyle(
              fontFamily : 'Poppins', fontSize: 11, color: accent.withOpacity(0.9)),
          ),
        ),
        if (tooTight) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color  : Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border : Border.all(color: Colors.orange.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 13),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$count words ke liye ${count} min window chahiye.\n'
                    'Abhi sirf $effectiveCount words schedule honge.\n'
                    'Window badhao ya words kam karo.',
                    style: const TextStyle(
                      fontFamily : 'Poppins', fontSize: 10,
                      color: Colors.orange, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Active Days Card ──────────────────────────────────────────────────────

  Widget _buildActiveDaysCard(Color accent) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            icon : Icons.calendar_month_rounded,
            label: 'Active Days',
            accent: accent,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing   : 8,
            runSpacing: 8,
            children  : List.generate(7, (i) {
              final active = _svc.settings.activeDays.contains(i);
              return GestureDetector(
                onTap: () async {
                  setState(() {
                    if (active) {
                      _svc.settings.activeDays.remove(i);
                    } else {
                      _svc.settings.activeDays.add(i);
                      _svc.settings.activeDays.sort();
                    }
                  });
                  await _svc.saveSettings();
                },
                child: AnimatedContainer(
                  duration   : const Duration(milliseconds: 200),
                  width      : 44,
                  height     : 44,
                  decoration : BoxDecoration(
                    color        : active ? accent : Colors.white.withOpacity(0.07),
                    borderRadius : BorderRadius.circular(12),
                    border       : Border.all(
                      color: active ? accent : Colors.white12),
                  ),
                  child: Center(
                    child: Text(
                      _dayLabels[i],
                      style: TextStyle(
                        fontFamily : 'Poppins',
                        fontSize   : 11,
                        fontWeight : FontWeight.w600,
                        color      : active ? Colors.white : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── CHANGE-1: Word Count Card — "Set" triggers auto-generate ─────────────

  Widget _buildWordCountCard(Color accent) {
    final isCustom = !_wordCounts.contains(_svc.settings.dailyCount);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            icon : Icons.format_list_numbered_rounded,
            label: 'Words Per Day',
            accent: accent,
          ),
          const SizedBox(height: 12),
          // Preset buttons — just select count (no auto-generate)
          Row(
            children: _wordCounts.map((cnt) {
              final selected = _svc.settings.dailyCount == cnt;
              return Expanded(
                child: GestureDetector(
                  onTap: () async {
                    setState(() {
                      _svc.settings.dailyCount = cnt;
                      _customWordCtrl.clear();
                    });
                    await _svc.saveSettings();
                  },
                  child: AnimatedContainer(
                    duration   : const Duration(milliseconds: 200),
                    margin     : const EdgeInsets.symmetric(horizontal: 3),
                    padding    : const EdgeInsets.symmetric(vertical: 10),
                    decoration : BoxDecoration(
                      color        : selected
                          ? accent
                          : Colors.white.withOpacity(0.06),
                      borderRadius : BorderRadius.circular(12),
                      border       : Border.all(
                        color: selected ? accent : Colors.white12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$cnt',
                          style: TextStyle(
                            fontFamily : 'Poppins',
                            fontSize   : 18,
                            fontWeight : FontWeight.w700,
                            color      : selected ? Colors.white : AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'words',
                          style: TextStyle(
                            fontFamily : 'Poppins',
                            fontSize   : 10,
                            color      : selected ? Colors.white70 : AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          // Custom input + Set button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller   : _customWordCtrl,
                  keyboardType : TextInputType.number,
                  style: const TextStyle(
                    fontFamily : 'Poppins', fontSize: 14,
                    color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText : isCustom
                        ? '${_svc.settings.dailyCount} (custom)'
                        : 'Ya apna number likho...',
                    hintStyle: const TextStyle(
                      fontFamily : 'Poppins', fontSize: 12,
                      color: AppTheme.textSecondary),
                    filled        : true,
                    fillColor     : Colors.white.withOpacity(0.05),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border       : OutlineInputBorder(
                      borderRadius : BorderRadius.circular(12),
                      borderSide   : const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius : BorderRadius.circular(12),
                      borderSide   : const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius : BorderRadius.circular(12),
                      borderSide   : BorderSide(color: accent.withOpacity(0.5)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // CHANGE-1: Set button triggers generation
              GestureDetector(
                onTap: _generating ? null : _onSetWordCount,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _generating ? 0.6 : 1.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color        : accent,
                      borderRadius : BorderRadius.circular(12),
                    ),
                    child: _generating
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text(
                            'Set',
                            style: TextStyle(
                              fontFamily : 'Poppins',
                              fontSize   : 14,
                              fontWeight : FontWeight.w700,
                              color      : Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
          if (isCustom) ...[
            const SizedBox(height: 6),
            Text(
              '✏️ Custom: ${_svc.settings.dailyCount} words/day',
              style: TextStyle(
                fontFamily : 'Poppins', fontSize: 11,
                color: accent.withOpacity(0.8)),
            ),
          ],
          if (_generating) ...[
            const SizedBox(height: 8),
            Text(
              'Words generate ho rahe hain... ⏳',
              style: TextStyle(
                fontFamily : 'Poppins', fontSize: 11,
                color: accent.withOpacity(0.7)),
            ),
          ],
          // Word bank size display
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color        : _svc.wordBankSize > 0
                  ? Colors.greenAccent.withOpacity(0.08)
                  : Colors.white.withOpacity(0.04),
              borderRadius : BorderRadius.circular(10),
              border       : Border.all(
                color: _svc.wordBankSize > 0
                    ? Colors.greenAccent.withOpacity(0.25)
                    : Colors.white12),
            ),
            child: Row(
              children: [
                Icon(
                  _svc.wordBankSize > 0
                      ? Icons.check_circle_rounded
                      : Icons.hourglass_empty_rounded,
                  color: _svc.wordBankSize > 0
                      ? Colors.greenAccent
                      : AppTheme.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _svc.wordBankSize > 0
                      ? '${_svc.wordBankSize} words bank mein ready hain ✅'
                      : 'Bank empty — Set dabao ya Toggle ON karo',
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 11,
                    color      : _svc.wordBankSize > 0
                        ? Colors.greenAccent
                        : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── CHANGE-1: Action Buttons — only Schedule + Test ───────────────────────

  Widget _buildActionButtons(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Schedule button — primary
        _ActionButton(
          icon    : Icons.schedule_rounded,
          label   : 'Schedule Karo ✅',
          subLabel: _svc.wordBankSize == 0
              ? 'Words automatically generate + schedule honge'
              : 'Agle 7 dino ke liye set karo (${_svc.wordBankSize} words ready)',
          accent  : accent,
          loading : _scheduling,
          onTap   : _scheduling ? null : _onSchedule,
        ),
        const SizedBox(height: 10),
        // Test notification button — outlined
        OutlinedButton.icon(
          onPressed: _onTestNotification,
          icon : const Icon(Icons.notification_important_rounded, size: 16),
          label: const Text(
            'Abhi Test Notification Bhejo',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor : accent,
            side            : BorderSide(color: accent.withOpacity(0.4)),
            padding         : const EdgeInsets.symmetric(
                vertical: 12, horizontal: 20),
            shape           : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            minimumSize     : const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }

  // ── Status Message ────────────────────────────────────────────────────────

  Widget _buildStatusMessage(Color accent) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _statusIsError
            ? Colors.redAccent.withOpacity(0.12)
            : Colors.greenAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _statusIsError
              ? Colors.redAccent.withOpacity(0.3)
              : Colors.greenAccent.withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _statusIsError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: _statusIsError ? Colors.redAccent : Colors.greenAccent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMsg!,
              style: TextStyle(
                fontFamily : 'Poppins',
                fontSize   : 13,
                color      : _statusIsError
                    ? Colors.redAccent
                    : Colors.greenAccent,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _statusMsg = null),
            child: const Icon(Icons.close_rounded,
                color: Colors.white38, size: 16),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Helper Widgets
// ═══════════════════════════════════════════════════════════════════

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding    : const EdgeInsets.all(16),
      decoration : BoxDecoration(
        color        : AppTheme.bgCard,
        borderRadius : BorderRadius.circular(18),
        border       : Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: child,
    );
  }
}

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
        Icon(icon, color: accent, size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily : 'Poppins',
            fontSize   : 13,
            fontWeight : FontWeight.w700,
            color      : accent,
          ),
        ),
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final int    hour;
  final int    minute;
  final Color  accent;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.hour,
    required this.minute,
    required this.accent,
    required this.onTap,
  });

  String get _formatted {
    final h    = hour % 12 == 0 ? 12 : hour % 12;
    final m    = minute.toString().padLeft(2, '0');
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color        : accent.withOpacity(0.1),
          borderRadius : BorderRadius.circular(14),
          border       : Border.all(color: accent.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily : 'Poppins', fontSize: 11,
                color: accent.withOpacity(0.7)),
            ),
            const SizedBox(height: 4),
            Text(
              _formatted,
              style: const TextStyle(
                fontFamily : 'Poppins', fontSize: 16, fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 2),
            Icon(Icons.access_time_rounded, color: accent, size: 14),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData      icon;
  final String        label;
  final String        subLabel;
  final Color         accent;
  final bool          loading;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.subLabel,
    required this.accent,
    required this.loading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity : loading ? 0.6 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent, accent.withOpacity(0.7)],
              begin : Alignment.topLeft,
              end   : Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color    : accent.withOpacity(0.35),
                blurRadius: 12,
                offset   : const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            children: [
              loading
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                    )
                  : Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily : 'Poppins', fontSize: 14,
                        fontWeight : FontWeight.w700, color: Colors.white),
                    ),
                    Text(
                      loading ? 'Wait karo...' : subLabel,
                      style: const TextStyle(
                        fontFamily : 'Poppins', fontSize: 11,
                        color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white60, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
