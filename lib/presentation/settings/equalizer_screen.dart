import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'settings_bloc.dart';
import '../../core/constants/app_constants.dart';

class EqualizerScreen extends StatelessWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Equalizer')),
      body: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // BUG-MED-03 FIX: EQ values save to Hive but just_audio has no
              // built-in EQ API — audio DSP requires a native plugin. Show a
              // disclaimer so users know sliders are visual-only for now.
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'EQ presets are saved but audio DSP processing requires '
                        'a native plugin. Visual only for now — full EQ coming soon.',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              // Enable toggle
              SwitchListTile(
                title: const Text('Equalizer'),
                value: state.eqEnabled,
                onChanged: (v) => context.read<SettingsBloc>().add(SettingsEqToggled(v)),
              ),

              const SizedBox(height: 16),

              // Preset chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppConstants.eqPresets.keys.map((preset) {
                  final selected = state.eqPreset == preset;
                  return FilterChip(
                    label: Text(preset),
                    selected: selected,
                    onSelected: (_) => context.read<SettingsBloc>().add(SettingsEqPresetChanged(preset)),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // EQ sliders
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(5, (i) {
                  return Column(
                    children: [
                      Text('${state.eqBands[i].round()} dB',
                          style: const TextStyle(fontSize: 11, color: Colors.white60)),
                      SizedBox(
                        height: 200,
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            value: state.eqBands[i],
                            min: -15,
                            max: 15,
                            divisions: 30,
                            onChanged: state.eqEnabled
                                ? (v) => context.read<SettingsBloc>().add(SettingsEqBandChanged(i, v))
                                : null,
                          ),
                        ),
                      ),
                      Text(AppConstants.eqBandLabels[i],
                          style: const TextStyle(fontSize: 11, color: Colors.white60)),
                    ],
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}
