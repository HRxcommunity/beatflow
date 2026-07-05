import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/player_state_entity.dart';
import '../../presentation/player/player_bloc.dart';

class WaveformVisualizer extends StatefulWidget {
  final double height;
  final int barCount;

  const WaveformVisualizer({super.key, this.height = 40, this.barCount = 28});

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer>
    with TickerProviderStateMixin {
  late AnimationController _ctrl;
  final _rng = Random();
  late List<double> _heights;

  @override
  void initState() {
    super.initState();
    _heights = List.generate(widget.barCount, (_) => 0.2 + _rng.nextDouble() * 0.8);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(_randomize);
    _ctrl.repeat();
  }

  void _randomize() {
    if (!mounted) return;
    setState(() {
      _heights = List.generate(widget.barCount, (_) => 0.2 + _rng.nextDouble() * 0.8);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerBloc, PlayerStateEntity>(
      buildWhen: (prev, curr) => prev.isPlaying != curr.isPlaying,
      builder: (context, state) {
        if (!state.isPlaying) _ctrl.stop();
        else if (!_ctrl.isAnimating) _ctrl.repeat();

        final color = Theme.of(context).colorScheme.primary;

        return SizedBox(
          height: widget.height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(widget.barCount, (i) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                width: 3,
                height: state.isPlaying ? widget.height * _heights[i] : widget.height * 0.2,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.7 + 0.3 * _heights[i]),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
