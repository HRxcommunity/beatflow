import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../presentation/settings/settings_bloc.dart';
import '../../core/theme/app_theme.dart';

/// Wraps any screen with the user's custom background image (WhatsApp-style).
/// If no image is set, renders normally with the default app background color.
///
/// Usage — wrap your screen's Scaffold child or the Scaffold body itself:
///   AppBackground(child: YourScreenContent())
///
/// Or wrap whole Scaffold:
///   AppBackground(child: Scaffold(...))
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, c) =>
          p.backgroundType != c.backgroundType ||
          p.backgroundImagePath != c.backgroundImagePath ||
          p.backgroundDimOpacity != c.backgroundDimOpacity,
      builder: (context, state) {
        final hasImage = state.backgroundType == 1 &&
            state.backgroundImagePath != null &&
            state.backgroundImagePath!.isNotEmpty;

        if (!hasImage) return child;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Background image
            Image.file(
              File(state.backgroundImagePath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: AppTheme.bgDeep,
              ),
            ),
            // Dark overlay (adjustable)
            ColoredBox(
              color: Colors.black.withValues(alpha: state.backgroundDimOpacity),
            ),
            // App content on top
            child,
          ],
        );
      },
    );
  }
}
