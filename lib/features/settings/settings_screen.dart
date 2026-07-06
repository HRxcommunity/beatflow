// lib/features/settings/settings_screen.dart
// FIX: AI Settings section — API key now visible, tappable chip shows masked key,
//      dialog allows view/edit/clear. Layout cleaned up.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/groq_service.dart';
import '../../core/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _groq = GroqService();

  bool _hasCustomKey = false;
  String? _maskedKey;

  @override
  void initState() {
    super.initState();
    _loadKeyStatus();
  }

  Future<void> _loadKeyStatus() async {
    final key = await _groq.getCustomApiKey();
    if (!mounted) return;
    setState(() {
      _hasCustomKey = key != null && key.trim().isNotEmpty;
      _maskedKey = key != null && key.length > 10
          ? '${key.substring(0, 6)}...${key.substring(key.length - 4)}'
          : null;
    });
  }

  // ─── API Key Dialog ───────────────────────────────────────────────────────

  Future<void> _showApiKeyDialog() async {
    final currentKey = await _groq.getCustomApiKey() ?? '';
    final ctrl = TextEditingController(text: currentKey);
    bool obscure = true;
    String? error;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.vpn_key_rounded, color: AppTheme.accentCyan, size: 22),
              SizedBox(width: 10),
              Text(
                'Groq API Key',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info banner
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accentCyan.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentCyan.withOpacity(0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Free key kahan milega?',
                      style: TextStyle(
                        color: AppTheme.accentCyan,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(const ClipboardData(text: 'https://console.groq.com/keys'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('URL copied!'), duration: Duration(seconds: 2)),
                        );
                      },
                      child: const Text(
                        'console.groq.com/keys\n(tap to copy URL)',
                        style: TextStyle(
                          color: Colors.white60,
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Key input field
              TextField(
                controller: ctrl,
                obscureText: obscure,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  letterSpacing: 1,
                ),
                decoration: InputDecoration(
                  hintText: 'gsk_xxxxxxxxxxxxxxxxxxxx',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                  errorText: error,
                  errorStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.accentCyan),
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Show / hide key
                      IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                          color: Colors.white38,
                          size: 18,
                        ),
                        onPressed: () => setDlgState(() => obscure = !obscure),
                      ),
                      // Paste from clipboard
                      IconButton(
                        icon: const Icon(Icons.content_paste_rounded, color: Colors.white38, size: 18),
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            ctrl.text = data!.text!.trim();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),

              if (currentKey.isNotEmpty) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () async {
                    await _groq.clearCustomKey();
                    if (ctx.mounted) Navigator.pop(ctx, 'cleared');
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                  label: const Text(
                    'Custom key hatao (fallback use hoga)',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontFamily: 'Poppins',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54, fontFamily: 'Poppins'),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentViolet,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final newKey = ctrl.text.trim();
                if (newKey.isEmpty) {
                  setDlgState(() => error = 'Key enter karo ya Cancel karo');
                  return;
                }
                if (!newKey.startsWith('gsk_') || newKey.length < 20) {
                  setDlgState(() => error = 'Valid Groq key "gsk_..." se shuru hota hai');
                  return;
                }
                await _groq.setApiKey(newKey);
                if (ctx.mounted) Navigator.pop(ctx, 'saved');
              },
              child: const Text(
                'Save',
                style: TextStyle(color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );

    await _loadKeyStatus(); // Refresh UI after dialog closes
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.black87,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        children: [

          // ── Together Background ──────────────────────────────────────────
          _SectionHeader('Together Background'),
          _SettingsCard(
            children: [
              AspectRatio(
                aspectRatio: 16 / 7,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                    image: const DecorationImage(
                      image: AssetImage('assets/images/default_together_bg.jpg'),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_rounded, size: 32, color: Colors.white.withOpacity(0.7)),
                      const SizedBox(height: 4),
                      Text(
                        'Set Together background image',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontFamily: 'Poppins',
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {/* Gallery picker logic */},
                icon: const Icon(Icons.photo_library_rounded, size: 18),
                label: const Text('From Gallery', style: TextStyle(fontFamily: 'Poppins')),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),

          // ── Playback ─────────────────────────────────────────────────────
          _SectionHeader('Playback'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.equalizer_rounded,
                iconColor: Colors.deepPurple,
                title: 'Equalizer',
                onTap: () {/* open equalizer */},
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black38),
              ),
            ],
          ),

          // ── AI Settings (FIX) ─────────────────────────────────────────────
          _SectionHeader('AI Settings'),
          _SettingsCard(
            children: [
              // FIX: Tappable key status row showing masked key
              GestureDetector(
                onTap: _showApiKeyDialog,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      // Status icon
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _hasCustomKey
                              ? Colors.green.withOpacity(0.12)
                              : Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.vpn_key_rounded,
                          size: 20,
                          color: _hasCustomKey ? Colors.green : Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _hasCustomKey ? 'Custom API Key' : 'Groq API Key',
                              style: const TextStyle(
                                color: Colors.black87,
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              _hasCustomKey && _maskedKey != null
                                  ? _maskedKey!
                                  : 'Using fallback key — tap to add yours',
                              style: TextStyle(
                                color: _hasCustomKey ? Colors.black54 : Colors.orange[700],
                                fontFamily: 'Poppins',
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Status chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _hasCustomKey
                              ? Colors.green.withOpacity(0.12)
                              : Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _hasCustomKey
                                ? Colors.green.withOpacity(0.4)
                                : Colors.orange.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          _hasCustomKey ? '✓ Active' : 'Fallback',
                          style: TextStyle(
                            color: _hasCustomKey ? Colors.green[700] : Colors.orange[800],
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded, color: Colors.black38, size: 20),
                    ],
                  ),
                ),
              ),

              const Divider(height: 20, color: Colors.black12),

              // Info row
              Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: Colors.black38),
                  const SizedBox(width: 6),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Clipboard.setData(const ClipboardData(text: 'https://console.groq.com/keys'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('URL copied!'), duration: Duration(seconds: 2)),
                        );
                      },
                      child: const Text(
                        'Free key: console.groq.com/keys  (tap to copy)',
                        style: TextStyle(
                          color: Colors.black45,
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── About ─────────────────────────────────────────────────────────
          _SectionHeader('About'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.info_rounded,
                iconColor: Colors.blueAccent,
                title: 'Version',
                trailing: const Text(
                  'v1.0.1 (2002)',
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                onTap: null,
              ),
              const Divider(height: 1, color: Colors.black12),
              _SettingsTile(
                icon: Icons.system_update_rounded,
                iconColor: Colors.teal,
                title: 'Check for Updates',
                onTap: () {/* OTA update check */},
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black38),
              ),
            ],
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[600],
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.black87,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
