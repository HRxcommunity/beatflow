import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'settings_bloc.dart';
import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
// OTA Update
import '../../services/update_service.dart';
import '../../features/update/update_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          return ListView(
            children: [
              // ── Appearance ───────────────────────────────────────
              const _SectionTitle('Appearance'),
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('Theme'),
                trailing: DropdownButton<ThemeMode>(
                  value: state.themeMode,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                    DropdownMenuItem(value: ThemeMode.light,  child: Text('Light')),
                    DropdownMenuItem(value: ThemeMode.dark,   child: Text('Dark')),
                  ],
                  onChanged: (mode) {
                    if (mode != null) {
                      context.read<SettingsBloc>().add(SettingsThemeChanged(mode));
                    }
                  },
                ),
              ),
              const ListTile(
                leading: Icon(Icons.color_lens_outlined),
                title: Text('Accent Color'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(AppConstants.accentColors.length, (i) {
                    final color = AppConstants.accentColors[i];
                    final selected = state.accentColorIndex == i;
                    return GestureDetector(
                      onTap: () =>
                          context.read<SettingsBloc>().add(SettingsAccentChanged(i)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: selected
                              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
                              : null,
                        ),
                        child: selected
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : null,
                      ),
                    );
                  }),
                ),
              ),
              const Divider(),

              // ── Background Theme (WhatsApp-style) ────────────────
              const _SectionTitle('App Background'),
              _BackgroundThemeSection(state: state),
              const Divider(),

              // ── Song Card Style ───────────────────────────────────
              const _SectionTitle('Song Card Style'),
              _SongCardStyleSection(state: state),
              const Divider(),

              // ── Together Background ───────────────────────────────
              const _SectionTitle('Together Screen Background'),
              _TogetherBgSection(state: state),
              const Divider(),

              // ── Playback ─────────────────────────────────────────
              const _SectionTitle('Playback'),
              ListTile(
                leading: const Icon(Icons.equalizer_outlined),
                title: const Text('Equalizer'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRouter.equalizer),
              ),
              const Divider(),

              // ── About ─────────────────────────────────────────────
              const _SectionTitle('About'),
              // BUG-SET01 FIX: Read version dynamically from package_info_plus
              const _VersionTile(),
              const _UpdateCheckTile(),
            ],
          );
        },
      ),
    );
  }
}

// ── Background Theme Section ──────────────────────────────────────────────────

class _BackgroundThemeSection extends StatelessWidget {
  final SettingsState state;
  const _BackgroundThemeSection({required this.state});

  Future<void> _pickImage(BuildContext context) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    if (!context.mounted) return;

    final editedPath = await showDialog<String>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _BgImageEditDialog(imagePath: file.path),
    );
    if (editedPath == null) return;
    if (!context.mounted) return;
    context.read<SettingsBloc>().add(
          SettingsBackgroundImageSet(editedPath,
              dimOpacity: state.backgroundDimOpacity),
        );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final hasImage = state.backgroundType == 1 &&
        state.backgroundImagePath != null &&
        state.backgroundImagePath!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Preview card ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: GestureDetector(
            onTap: () => _pickImage(context),
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppTheme.bgCard,
                border: Border.all(color: Colors.white12),
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasImage)
                    Image.file(
                      File(state.backgroundImagePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppTheme.bgDeep, AppTheme.bgSurface],
                        ),
                      ),
                    ),
                  if (hasImage)
                    Container(color: Colors.black.withValues(alpha: state.backgroundDimOpacity)),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hasImage ? Icons.image_rounded : Icons.wallpaper_rounded,
                          color: Colors.white70,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          hasImage ? 'Tap to change image' : 'Tap to set background image',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Action buttons ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(context),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('From Gallery'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (hasImage) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context
                        .read<SettingsBloc>()
                        .add(SettingsBackgroundReset()),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Remove'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Dim slider ───────────────────────────────────────────
        if (hasImage) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.brightness_low, color: Colors.white54, size: 18),
                Expanded(
                  child: Slider(
                    value: state.backgroundDimOpacity,
                    min: 0.0,
                    max: 0.9,
                    divisions: 18,
                    label: 'Dim ${(state.backgroundDimOpacity * 100).round()}%',
                    onChanged: (v) => context
                        .read<SettingsBloc>()
                        .add(SettingsBackgroundDimChanged(v)),
                  ),
                ),
                const Icon(Icons.brightness_high, color: Colors.white, size: 18),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Dim: ${(state.backgroundDimOpacity * 100).round()}%  —  lower = brighter image',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Song Card Style Section ───────────────────────────────────────────────────

class _SongCardStyleSection extends StatelessWidget {
  final SettingsState state;
  const _SongCardStyleSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    // Card color presets: label + color
    final colorPresets = [
      _CardColorOption('Dark', AppTheme.bgCard, 0),
      _CardColorOption('Accent', accent, 1),
      _CardColorOption('White', Colors.white, 2),
      _CardColorOption('Black', Colors.black, 3),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Live preview ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Preview', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: _SongCardPreview(state: state),
        ),
        const SizedBox(height: 12),

        // ── Color picker ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Card Color', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 10,
            children: colorPresets.map((opt) {
              final selected = state.songCardColorIndex == opt.index;
              return GestureDetector(
                onTap: () => context
                    .read<SettingsBloc>()
                    .add(SettingsSongCardColorChanged(opt.index)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: opt.color,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? accent : Colors.white24,
                          width: selected ? 2.5 : 1,
                        ),
                        boxShadow: selected
                            ? [BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 8)]
                            : null,
                      ),
                      child: selected
                          ? Icon(Icons.check_rounded,
                              color: opt.color == Colors.white ? Colors.black : Colors.white,
                              size: 20)
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(opt.label,
                        style: TextStyle(
                          fontSize: 10,
                          color: selected ? accent : Colors.white54,
                        )),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // ── Opacity / Transparency slider ─────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              Text('Transparency', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const Spacer(),
              Text(
                '${((1 - state.songCardOpacity) * 100).round()}% transparent',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.opacity, color: Colors.white38, size: 18),
              Expanded(
                child: Slider(
                  value: state.songCardOpacity,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: '${(state.songCardOpacity * 100).round()}% opacity',
                  onChanged: (v) => context
                      .read<SettingsBloc>()
                      .add(SettingsSongCardOpacityChanged(v)),
                ),
              ),
              const Icon(Icons.rectangle_rounded, color: Colors.white, size: 18),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Live preview card inside settings
class _SongCardPreview extends StatelessWidget {
  final SettingsState state;
  const _SongCardPreview({required this.state});

  Color _baseColor(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    switch (state.songCardColorIndex) {
      case 1: return accent;
      case 2: return Colors.white;
      case 3: return Colors.black;
      default: return AppTheme.bgCard;
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = _baseColor(context);
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: state.songCardOpacity),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: state.songCardOpacity * 0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Song Title',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text('Artist Name',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          Text('03:45',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          const SizedBox(width: 4),
          Icon(Icons.more_vert_rounded,
              color: AppTheme.textSecondary.withValues(alpha: 0.5), size: 18),
        ],
      ),
    );
  }
}

class _CardColorOption {
  final String label;
  final Color color;
  final int index;
  _CardColorOption(this.label, this.color, this.index);
}

// ── Together Background Section ──────────────────────────────────────────────

class _TogetherBgSection extends StatelessWidget {
  final SettingsState state;
  const _TogetherBgSection({required this.state});

  Future<void> _pickImage(BuildContext context) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file == null) return;
    if (!context.mounted) return;

    // Show in-app crop dialog (no external package)
    final croppedPath = await showDialog<String>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _BgImageEditDialog(imagePath: file.path),
    );
    if (croppedPath == null) return;
    if (!context.mounted) return;
    context.read<SettingsBloc>().add(
          SettingsTogetherBgImageSet(croppedPath,
              dimOpacity: state.togetherBgDimOpacity),
        );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final hasImage = state.togetherBgType == 1 &&
        state.togetherBgImagePath != null &&
        state.togetherBgImagePath!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Set a unique wallpaper for BeatFlow Together screen.',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),

        // ── Preview ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: GestureDetector(
            onTap: () => _pickImage(context),
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppTheme.bgCard,
                border: Border.all(color: Colors.white12),
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasImage)
                    Image.file(
                      File(state.togetherBgImagePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    )
                  else
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0A0A1A), Color(0xFF1A0A2E)],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.favorite_rounded,
                          color: Colors.pinkAccent.withValues(alpha: 0.3),
                          size: 48,
                        ),
                      ),
                    ),
                  if (hasImage)
                    Container(
                        color: Colors.black.withValues(alpha: state.togetherBgDimOpacity)),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hasImage ? Icons.image_rounded : Icons.add_photo_alternate_outlined,
                          color: Colors.white70,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          hasImage
                              ? 'Tap to change Together image'
                              : 'Set Together background image',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Buttons ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(context),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('From Gallery'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (hasImage) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context
                        .read<SettingsBloc>()
                        .add(SettingsTogetherBgReset()),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Remove'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Dim slider ────────────────────────────────────────────
        if (hasImage) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.brightness_low, color: Colors.white54, size: 18),
                Expanded(
                  child: Slider(
                    value: state.togetherBgDimOpacity,
                    min: 0.0,
                    max: 0.9,
                    divisions: 18,
                    label: 'Dim ${(state.togetherBgDimOpacity * 100).round()}%',
                    onChanged: (v) => context
                        .read<SettingsBloc>()
                        .add(SettingsTogetherBgDimChanged(v)),
                  ),
                ),
                const Icon(Icons.brightness_high, color: Colors.white, size: 18),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Dim: ${(state.togetherBgDimOpacity * 100).round()}%  —  lower = brighter',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Section title ─────────────────────────────────────────────────────────────

// ── Version Tile ──────────────────────────────────────────────────────────────
// BUG-SET01 FIX: Reads actual version from package_info_plus instead of
// hardcoded AppConstants.appVersion (which showed blank because the const
// was not rebuilding on theme changes — now dynamic via FutureBuilder).

class _VersionTile extends StatelessWidget {
  const _VersionTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final version  = snap.data?.version     ?? AppConstants.appVersion;
        final build    = snap.data?.buildNumber ?? '1';
        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Version'),
          trailing: Text(
            'v$version ($build)',
            style: TextStyle(
              color      : Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
              fontFamily : 'Poppins',
              fontSize   : 13,
              fontWeight : FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}

// ── Update Check Tile ─────────────────────────────────────────────────────────
// Settings screen mein manually update check karne ka button.
// 3 states: idle → checking → result (up-to-date / dialog)

class _UpdateCheckTile extends StatefulWidget {
  const _UpdateCheckTile();

  @override
  State<_UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends State<_UpdateCheckTile> {
  _CheckState _state = _CheckState.idle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        _state == _CheckState.upToDate
            ? Icons.check_circle_outline_rounded
            : Icons.system_update_alt_rounded,
        color: _state == _CheckState.upToDate
            ? Colors.green
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        _state == _CheckState.upToDate
            ? "You're up to date ✓"
            : 'Check for Updates',
      ),
      subtitle: _state == _CheckState.upToDate
          ? const Text('Latest version installed',
              style: TextStyle(fontSize: 12, color: Colors.white54))
          : null,
      trailing: _state == _CheckState.checking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right_rounded, color: Colors.white38),
      onTap: _state == _CheckState.checking ? null : _onCheck,
    );
  }

  Future<void> _onCheck() async {
    setState(() => _state = _CheckState.checking);

    final info = await UpdateService.instance.checkForUpdate();

    if (!mounted) return;

    if (info != null && info.hasUpdate) {
      setState(() => _state = _CheckState.idle);
      showUpdateDialog(context, info);
    } else {
      setState(() => _state = _CheckState.upToDate);
      // 3 second baad wapas idle ho jao
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) setState(() => _state = _CheckState.idle);
    }
  }
}

enum _CheckState { idle, checking, upToDate }

// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BACKGROUND IMAGE EDIT DIALOG — Fill / Fit / Zoom
//  "Set" captures exactly what the user sees in the viewport via RepaintBoundary.
// ══════════════════════════════════════════════════════════════════════════════

enum _BgEditMode { fill, fit, zoom }

class _BgImageEditDialog extends StatefulWidget {
  final String imagePath;
  const _BgImageEditDialog({required this.imagePath});

  @override
  State<_BgImageEditDialog> createState() => _BgImageEditDialogState();
}

class _BgImageEditDialogState extends State<_BgImageEditDialog> {
  _BgEditMode _mode = _BgEditMode.fill;
  bool _saving = false;
  final GlobalKey _previewKey = GlobalKey();
  final TransformationController _transformCtrl = TransformationController();

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final boundary =
          _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('preview not mounted');

      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final img = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('render failed');

      final dir = await Directory.systemTemp.createTemp('beatflow_bg');
      final path = '${dir.path}/bg_${_mode.name}.png';
      await File(path).writeAsBytes(byteData.buffer.asUint8List());
      if (mounted) Navigator.of(context).pop(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
        setState(() => _saving = false);
      }
    }
  }

  void _setMode(_BgEditMode m) => setState(() {
        _mode = m;
        _transformCtrl.value = Matrix4.identity();
      });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final accent = Theme.of(context).colorScheme.primary;

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: SizedBox(
        width: screenSize.width,
        height: screenSize.height,
        child: Column(
          children: [
            // ── Top bar ────────────────────────────────────────────
            Container(
              color: AppTheme.bgDeep,
              padding: const EdgeInsets.fromLTRB(8, 40, 8, 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.white70)),
                  ),
                  const Expanded(
                    child: Text(
                      'Edit Background',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16),
                    ),
                  ),
                  _saving
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white)),
                        )
                      : TextButton(
                          onPressed: _save,
                          child: Text('Set',
                              style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                        ),
                ],
              ),
            ),

            // ── Mode selector ──────────────────────────────────────
            Container(
              color: AppTheme.bgSurface,
              padding:
                  const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ModePill(
                    icon: '⛶', label: 'Fill',
                    selected: _mode == _BgEditMode.fill,
                    accent: accent,
                    onTap: () => _setMode(_BgEditMode.fill),
                  ),
                  _ModePill(
                    icon: '⊟', label: 'Fit',
                    selected: _mode == _BgEditMode.fit,
                    accent: accent,
                    onTap: () => _setMode(_BgEditMode.fit),
                  ),
                  _ModePill(
                    icon: '⊕', label: 'Zoom',
                    selected: _mode == _BgEditMode.zoom,
                    accent: accent,
                    onTap: () => _setMode(_BgEditMode.zoom),
                  ),
                ],
              ),
            ),

            // ── Image preview (captured on Set) ───────────────────
            Expanded(
              child: RepaintBoundary(
                key: _previewKey,
                child: Container(
                  color: Colors.black,
                  child: _buildPreview(),
                ),
              ),
            ),

            // ── Hint ───────────────────────────────────────────────
            Container(
              color: AppTheme.bgDeep,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _hint => switch (_mode) {
        _BgEditMode.fill => 'Image fills the screen edge-to-edge',
        _BgEditMode.fit  => 'Full image visible · letterbox allowed',
        _BgEditMode.zoom => 'Pinch to zoom  ·  Drag to position',
      };

  Widget _buildPreview() {
    final file = File(widget.imagePath);
    return switch (_mode) {
      _BgEditMode.fill => Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      _BgEditMode.fit => Image.file(
          file,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
        ),
      _BgEditMode.zoom => ClipRect(
          child: InteractiveViewer(
            transformationController: _transformCtrl,
            minScale: 0.5,
            maxScale: 6.0,
            child: Image.file(
              file,
              fit: BoxFit.contain,
              width: double.infinity,
            ),
          ),
        ),
    };
  }
}

// ── Mode pill button ──────────────────────────────────────────────────────────

class _ModePill extends StatelessWidget {
  final String icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _ModePill({
    required this.icon, required this.label,
    required this.selected, required this.accent, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon,
                style: TextStyle(
                    fontSize: 15,
                    color: selected ? accent : Colors.white54)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? accent : Colors.white54)),
          ],
        ),
      ),
    );
  }
}
