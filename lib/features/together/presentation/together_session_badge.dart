import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/together_bloc.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// A floating indicator shown when the user is in a BeatFlow Together session.
/// Tapping it navigates to the Together screen.
class TogetherSessionBadge extends StatefulWidget {
  const TogetherSessionBadge({super.key});

  @override
  State<TogetherSessionBadge> createState() => _TogetherSessionBadgeState();
}

class _TogetherSessionBadgeState extends State<TogetherSessionBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TogetherBloc, TogetherState>(
      buildWhen: (prev, curr) =>
          prev.isInSession != curr.isInSession ||
          prev.session?.memberCount != curr.session?.memberCount,
      builder: (context, state) {
        if (!state.isInSession) return const SizedBox.shrink();

        final accent = Theme.of(context).colorScheme.primary;
        final listenerCount = state.session?.memberCount ?? 0;

        return AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Transform.scale(
            scale: _pulseAnim.value,
            child: child,
          ),
          child: GestureDetector(
            onTap: () => context.push(AppRouter.together),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent, AppTheme.accentCyan.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite_rounded,
                      color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '$listenerCount listening',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
