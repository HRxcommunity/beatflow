// ╔══════════════════════════════════════════════════════════════╗
// ║  Vocab Notification Settings Screen                          ║
// ║  BUG-VN03 FIX: interval display + window warning            ║
// ║  BUG-VN04 FIX: permission denied → open system settings     ║
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
  final _svc        = VocabNotifService.instance;
  final _apiKeyCtrl = TextEditingController();

  bool _loading       = false;
  bool _scheduling    = false;
  bool _showApiKey    = false;
  int  _pendingCnt    = 0;
  String? _statusMsg;
  bool _statusIsError = false;
  bool _notifEnabled  = true; // system-level permission
  final _customWordCtrl = TextEditingController();

  static const _dayLabels  = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _wordCounts = [10, 20, 30, 40];

  @override
  void initState() {
    super.initState();
    _apiKeyCtrl.text = _svc.settings.groqApiKey;
    _refreshPendingCount();
    _checkSystemPermission();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
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

  // ── Open system notification settings ────────────────────────────────────
  void _openSystemNotifSettings() {
    // Open BeatFlow's notification settings page in system settings
    const channel = MethodChannel('beatflow/settings');
    channel.invokeMethod('openNotificationSettings').catchError((_) {
      // Fallback: show instruction
      _showStatus(
        'System Settings > Apps > BeatFlow > Notifications → Enable karo',
        error: false,
      );
    });
  }

  // ── Handlers ─────────────────────────────────────────────────────────────

  Future<void> _onToggleEnabled(bool val) async {
    if (val && _svc.wordBankSize == 0) {
      final key = _apiKeyCtrl.text.trim().isNotEmpty
          ? _apiKeyCtrl.text.trim()
          : _svc.settings.groqApiKey.trim();
      if (key.isEmpty) {
        _showStatus('Pehle Groq API key daalo, phir enable karo ⬆️', error: true);
        return;
      }
      _svc.settings.groqApiKey = key;
      await _svc.saveSettings();
      setState(() {
        _loading   = true;
        _statusMsg = null;
      });
      _showStatus('Word bank generate ho raha hai... ⏳');
      final err = await _svc.generateWordBank(count: 60);
      setState(() => _loading = false);
      if (err != null) {
        _showStatus(err, error: true);
        return;
      }
      _showStatus('${_svc.wordBankSize} words generate ho gaye! 📚');
    }
    _svc.settings.enabled = val;
    await _svc.saveSettings();
    if (!val) {
      await _svc.cancelAll();
      _showStatus('Notifications band kar diye ✅');
    } else {
      final n = await _svc.scheduleNext(daysAhead: 7);
      final nextLabel = _svc.getNextNotificationLabel();
      final nextLine  = nextLabel.isNotEmpty ? '\n⏰ $nextLabel pehli notification aayegi' : '';
      _showStatus('$n notifications schedule ho gaye!$nextLine');
    }
    _refreshPendingCount();
    setState(() {});
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart
        ? TimeOfDay(
            hour:   _svc.settings.startHour,
            minute: _svc.settings.startMinute,
          )
        : TimeOfDay(
            hour:   _svc.settings.endHour,
            minute: _svc.settings.endMinute,
          );

    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (ctx, child) => Theme(
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

  Future<void> _onGenerateWordBank() async {
    _svc.settings.groqApiKey = _apiKeyCtrl.text.trim();
    await _svc.saveSettings();

    if (_svc.settings.groqApiKey.isEmpty) {
      _showStatus('Groq API key daalo pehle ⬆️', error: true);
      return;
    }

    setState(() {
      _loading   = true;
      _statusMsg = null;
    });

    final err = await _svc.generateWordBank(count: 60);

    setState(() => _loading = false);

    if (err != null) {
      _showStatus(err, error: true);
    } else {
      _showStatus('${_svc.wordBankSize} words generate ho gaye! 📚');
    }
  }

  Future<void> _onSchedule() async {
    // BUG-V5 FIX: Auto-generate word bank if empty — user nahi karna chahta manually
    if (_svc.wordBankSize == 0) {
      if (_svc.settings.groqApiKey.isEmpty) {
        _showStatus(
          'Ek baar Groq API key daalo (free hai: console.groq.com) — '
          'phir Schedule press karo, baaki sab automatic hoga! 🔑',
          error: true,
        );
        return;
      }

      setState(() {
        _scheduling = true;
        _statusMsg  = null;
      });
      _showStatus('📚 Words generate ho rahe hain... ek minute');

      final genErr = await _svc.generateWordBank(count: 60);
      if (genErr != null) {
        setState(() => _scheduling = false);
        _showStatus('Word generation fail hua: $genErr', error: true);
        return;
      }
      setState(() {}); // update word count display
    }

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
      // BUG-V5 FIX: Show exactly WHEN the next notification will fire
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
          // BUG-VN04 FIX: Show system permission warning banner
          if (!_notifEnabled) ...[
            _buildPermissionWarningBanner(accent),
            const SizedBox(height: 12),
          ],
          _buildStatusBanner(accent),
          const SizedBox(height: 12),
          _buildEnableCard(accent),
          const SizedBox(height: 12),
          _buildTimeRangeCard(accent),
          const SizedBox(height: 12),
          _buildActiveDaysCard(accent),
          const SizedBox(height: 12),
          _buildWordCountCard(accent),
          const SizedBox(height: 12),
          _buildApiKeyCard(accent),
          const SizedBox(height: 12),
          _buildWordBankCard(accent),
          const SizedBox(height: 12),
          _buildActionButtons(accent),
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

  // ── BUG-VN04 FIX: System permission warning ───────────────────────────────

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
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
                // BUG-V5 FIX: Show next notification time so user knows when to expect it
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
                    '$_pendingCnt notifications scheduled hain',
                    style: const TextStyle(
                      fontFamily : 'Poppins',
                      fontSize   : 12,
                      color      : AppTheme.textSecondary,
                    ),
                  )
                else
                  const Text(
                    'Neeche "Schedule Karo" dabao',
                    style: TextStyle(
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
              color            : accent.withOpacity(0.12),
              borderRadius     : BorderRadius.circular(12),
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
                  'Notifications bhejne shuru / band karo',
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 11,
                    color      : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value          : _svc.settings.enabled,
            onChanged      : _onToggleEnabled,
            activeColor    : accent,
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

  // BUG-VN03 FIX: Show correct interval + warning when window too small
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
            fontFamily : 'Poppins', fontSize: 11,
            color      : Colors.redAccent,
          ),
        ),
      );
    }

    if (count <= 0) {
      return const SizedBox.shrink();
    }

    // BUG-VN03 FIX: effectiveCount is capped to window minutes
    final effectiveCount = count > window ? window : count;
    final intervalMins   = window / effectiveCount; // may be < 1
    final tooTight       = count > window; // user asked for more than window allows

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
              fontFamily : 'Poppins',
              fontSize   : 11,
              color      : accent.withOpacity(0.9),
            ),
          ),
        ),
        // Show warning if count > window
        if (tooTight) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color        : Colors.orange.withOpacity(0.08),
              borderRadius : BorderRadius.circular(8),
              border       : Border.all(color: Colors.orange.withOpacity(0.25)),
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
                      fontFamily : 'Poppins',
                      fontSize   : 10,
                      color      : Colors.orange,
                      height     : 1.4,
                    ),
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
                    color        : active
                        ? accent
                        : Colors.white.withOpacity(0.07),
                    borderRadius : BorderRadius.circular(12),
                    border       : Border.all(
                      color: active ? accent : Colors.white12,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _dayLabels[i],
                      style: TextStyle(
                        fontFamily : 'Poppins',
                        fontSize   : 11,
                        fontWeight : FontWeight.w600,
                        color      : active
                            ? Colors.white
                            : AppTheme.textSecondary,
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

  // ── Word Count Card ───────────────────────────────────────────────────────

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
                        color: selected ? accent : Colors.white12,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$cnt',
                          style: TextStyle(
                            fontFamily : 'Poppins',
                            fontSize   : 18,
                            fontWeight : FontWeight.w700,
                            color      : selected
                                ? Colors.white
                                : AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'words',
                          style: TextStyle(
                            fontFamily : 'Poppins',
                            fontSize   : 10,
                            color      : selected
                                ? Colors.white70
                                : AppTheme.textSecondary,
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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller   : _customWordCtrl,
                  keyboardType : TextInputType.number,
                  style: const TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 14,
                    color      : AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText : isCustom
                        ? '${_svc.settings.dailyCount} (custom)'
                        : 'Ya apna number likho...',
                    hintStyle: const TextStyle(
                      fontFamily : 'Poppins',
                      fontSize   : 12,
                      color      : AppTheme.textSecondary,
                    ),
                    filled        : true,
                    fillColor     : Colors.white.withOpacity(0.05),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border        : OutlineInputBorder(
                      borderRadius : BorderRadius.circular(12),
                      borderSide   : const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder : OutlineInputBorder(
                      borderRadius : BorderRadius.circular(12),
                      borderSide   : const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder : OutlineInputBorder(
                      borderRadius : BorderRadius.circular(12),
                      borderSide   : BorderSide(color: accent.withOpacity(0.5)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  final val = int.tryParse(_customWordCtrl.text.trim());
                  if (val == null || val < 1 || val > 200) {
                    _showStatus('1 se 200 ke beech number daalo', error: true);
                    return;
                  }
                  setState(() => _svc.settings.dailyCount = val);
                  await _svc.saveSettings();
                  _showStatus('$val words/day set ho gaya ✅');
                  FocusScope.of(context).unfocus();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color        : accent,
                    borderRadius : BorderRadius.circular(12),
                  ),
                  child: const Text(
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
            ],
          ),
          if (isCustom) ...[
            const SizedBox(height: 6),
            Text(
              '✏️ Custom: ${_svc.settings.dailyCount} words/day',
              style: TextStyle(
                fontFamily : 'Poppins',
                fontSize   : 11,
                color      : accent.withOpacity(0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── API Key Card ──────────────────────────────────────────────────────────

  Widget _buildApiKeyCard(Color accent) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            icon : Icons.key_rounded,
            label: 'Groq API Key',
            accent: accent,
          ),
          const SizedBox(height: 4),
          Text(
            'Free key milti hai: console.groq.com',
            style: TextStyle(
              fontFamily : 'Poppins',
              fontSize   : 11,
              color      : accent.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller  : _apiKeyCtrl,
            obscureText : !_showApiKey,
            style: const TextStyle(
              fontFamily : 'Poppins',
              fontSize   : 13,
              color      : AppTheme.textPrimary,
            ),
            decoration: InputDecoration(
              hintText      : 'gsk_xxxxxxxxxxxxxxxxxxxxx',
              hintStyle: const TextStyle(
                fontFamily : 'Poppins',
                fontSize   : 12,
                color      : AppTheme.textSecondary,
              ),
              filled        : true,
              fillColor     : Colors.white.withOpacity(0.05),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              border        : OutlineInputBorder(
                borderRadius : BorderRadius.circular(12),
                borderSide   : const BorderSide(color: Colors.white12),
              ),
              enabledBorder : OutlineInputBorder(
                borderRadius : BorderRadius.circular(12),
                borderSide   : const BorderSide(color: Colors.white12),
              ),
              focusedBorder : OutlineInputBorder(
                borderRadius : BorderRadius.circular(12),
                borderSide   : BorderSide(color: accent.withOpacity(0.5)),
              ),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _showApiKey = !_showApiKey),
                icon: Icon(
                  _showApiKey
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppTheme.textSecondary,
                  size: 18,
                ),
              ),
            ),
            onChanged: (v) {
              _svc.settings.groqApiKey = v;
            },
          ),
        ],
      ),
    );
  }

  // ── Word Bank Card ────────────────────────────────────────────────────────

  Widget _buildWordBankCard(Color accent) {
    final size = _svc.wordBankSize;
    return _Card(
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color        : accent.withOpacity(0.12),
              shape        : BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$size',
                style: TextStyle(
                  fontFamily : 'Poppins',
                  fontSize   : 18,
                  fontWeight : FontWeight.w800,
                  color      : accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Word Bank',
                  style: TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 14,
                    fontWeight : FontWeight.w600,
                    color      : AppTheme.textPrimary,
                  ),
                ),
                Text(
                  size == 0
                      ? 'Abhi koi words nahi — Generate karo ⬇️'
                      : '$size words ready hain',
                  style: const TextStyle(
                    fontFamily : 'Poppins',
                    fontSize   : 12,
                    color      : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (size > 0)
            Icon(Icons.check_circle_rounded,
                color: Colors.greenAccent.withOpacity(0.8), size: 22),
        ],
      ),
    );
  }

  // ── Action Buttons ────────────────────────────────────────────────────────

  Widget _buildActionButtons(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // BUG-V5 FIX: Schedule is now the PRIMARY button (top, full gradient)
        // Word bank auto-generates inside _onSchedule if empty
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

        // Test notification — immediate check
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
        const SizedBox(height: 10),

        // Generate Word Bank — secondary (for manual refresh/add more words)
        _ActionButton(
          icon    : Icons.auto_awesome_rounded,
          label   : 'Aur Words Add Karo (AI)',
          subLabel: '60 aur SSC CGL words generate karo',
          accent  : accent,
          loading : _loading,
          onTap   : _loading ? null : _onGenerateWordBank,
          secondary: true,
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
    final h   = hour % 12 == 0 ? 12 : hour % 12;
    final m   = minute.toString().padLeft(2, '0');
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
                fontFamily : 'Poppins',
                fontSize   : 11,
                color      : accent.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatted,
              style: const TextStyle(
                fontFamily : 'Poppins',
                fontSize   : 16,
                fontWeight : FontWeight.w700,
                color      : AppTheme.textPrimary,
              ),
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
  final IconData icon;
  final String   label;
  final String   subLabel;
  final Color    accent;
  final bool     loading;
  final bool     secondary;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.subLabel,
    required this.accent,
    required this.loading,
    this.secondary = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration : const Duration(milliseconds: 200),
        opacity  : loading ? 0.6 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: secondary
                ? null
                : LinearGradient(
                    colors: [accent, accent.withOpacity(0.7)],
                    begin : Alignment.topLeft,
                    end   : Alignment.bottomRight,
                  ),
            color: secondary ? accent.withOpacity(0.12) : null,
            borderRadius: BorderRadius.circular(16),
            border: secondary
                ? Border.all(color: accent.withOpacity(0.3))
                : null,
            boxShadow: secondary
                ? null
                : [
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
                  ? SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(
                        color       : secondary ? accent : Colors.white,
                        strokeWidth : 2.5,
                      ),
                    )
                  : Icon(
                      icon,
                      color: secondary ? accent : Colors.white,
                      size : 22,
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily : 'Poppins',
                        fontSize   : 14,
                        fontWeight : FontWeight.w700,
                        color      : secondary ? accent : Colors.white,
                      ),
                    ),
                    Text(
                      loading ? 'Wait karo...' : subLabel,
                      style: TextStyle(
                        fontFamily : 'Poppins',
                        fontSize   : 11,
                        color      : secondary
                            ? accent.withOpacity(0.7)
                            : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: secondary ? accent.withOpacity(0.5) : Colors.white60,
                size : 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
