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
