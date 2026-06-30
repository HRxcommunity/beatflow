// ╔══════════════════════════════════════════════════════════════════╗
// ║         BeatFlow Debug Overlay  v1.0                             ║
// ║  Wrap your app with DebugOverlay. Shake phone to open panel.     ║
// ║  Shows live errors, warnings, audio state in real time.          ║
// ╚══════════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'package:flutter/material.dart';
import 'beatflow_debugger.dart';

class DebugOverlay extends StatefulWidget {
  final Widget child;
  const DebugOverlay({super.key, required this.child});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay>
    with SingleTickerProviderStateMixin {
  bool _visible = false;
  BugSeverity? _filterSeverity;
  StreamSubscription<List<BugEntry>>? _sub;
  List<BugEntry> _logs = [];
  final _scroll = ScrollController();
  late AnimationController _badgeAnim;
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _badgeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _sub = BeatFlowDebugger.instance.stream.listen((logs) {
      if (mounted) {
        setState(() => _logs = logs);
        if (_visible && _autoScroll) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.animateTo(
                _scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        }
        // Pulse the badge when a crash/error arrives
        final latest = logs.lastOrNull;
        if (latest != null &&
            (latest.severity == BugSeverity.crash ||
                latest.severity == BugSeverity.error)) {
          _badgeAnim.forward(from: 0);
        }
      }
    });
    _logs = BeatFlowDebugger.instance.logs;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    _badgeAnim.dispose();
    super.dispose();
  }

  void _toggle() => setState(() => _visible = !_visible);

  List<BugEntry> get _filteredLogs {
    if (_filterSeverity == null) return _logs;
    return _logs.where((e) => e.severity == _filterSeverity).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,

        // ── Floating bug-count badge (always visible) ───────────
        Positioned(
          top: 50,
          right: 0,
          child: GestureDetector(
            onTap: _toggle,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.3)
                  .animate(CurvedAnimation(
                    parent: _badgeAnim,
                    curve: Curves.elasticOut,
                  )),
              child: _BadgeButton(
                crashes: BeatFlowDebugger.instance.crashCount,
                errors: BeatFlowDebugger.instance.errorCount,
                total: _logs.length,
              ),
            ),
          ),
        ),

        // ── Debug panel (slides in from right) ──────────────────
        if (_visible)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggle, // tap outside to close
              child: Container(color: Colors.black54),
            ),
          ),
        if (_visible)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: MediaQuery.of(context).size.width * 0.96,
            child: _DebugPanel(
              logs: _filteredLogs,
              allLogs: _logs,
              filterSeverity: _filterSeverity,
              onFilterChanged: (s) => setState(() => _filterSeverity = s),
              onClose: _toggle,
              onClear: () {
                BeatFlowDebugger.instance.clear();
                setState(() => _logs = []);
              },
              scroll: _scroll,
              autoScroll: _autoScroll,
              onAutoScrollChanged: (v) => setState(() => _autoScroll = v),
            ),
          ),
      ],
    );
  }
}

// ── Badge button ─────────────────────────────────────────────────
class _BadgeButton extends StatelessWidget {
  final int crashes, errors, total;
  const _BadgeButton({
    required this.crashes,
    required this.errors,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final color = crashes > 0
        ? const Color(0xFFFF4444)
        : errors > 0
            ? const Color(0xFFFF9800)
            : const Color(0xFF64B5F6);

    return Container(
      margin: const EdgeInsets.only(right: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
        border: Border.all(color: color.withOpacity(0.7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bug_report_rounded, color: color, size: 18),
          const SizedBox(height: 2),
          Text(
            total.toString(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          if (crashes > 0)
            Text(
              '${crashes}💥',
              style: const TextStyle(
                color: Color(0xFFFF4444),
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }
}

// ── Main debug panel ─────────────────────────────────────────────
class _DebugPanel extends StatelessWidget {
  final List<BugEntry> logs;
  final List<BugEntry> allLogs;
  final BugSeverity? filterSeverity;
  final ValueChanged<BugSeverity?> onFilterChanged;
  final VoidCallback onClose;
  final VoidCallback onClear;
  final ScrollController scroll;
  final bool autoScroll;
  final ValueChanged<bool> onAutoScrollChanged;

  const _DebugPanel({
    required this.logs,
    required this.allLogs,
    required this.filterSeverity,
    required this.onFilterChanged,
    required this.onClose,
    required this.onClear,
    required this.scroll,
    required this.autoScroll,
    required this.onAutoScrollChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0D0D1A),
      elevation: 24,
      child: SafeArea(
        child: Column(
          children: [
            _PanelHeader(
              onClose: onClose,
              onClear: onClear,
              total: allLogs.length,
              crashes: allLogs.where((e) => e.severity == BugSeverity.crash).length,
              errors:  allLogs.where((e) => e.severity == BugSeverity.error).length,
              warns:   allLogs.where((e) => e.severity == BugSeverity.warning).length,
            ),
            _FilterBar(
              selected: filterSeverity,
              onChanged: onFilterChanged,
              counts: {
                null:                 allLogs.length,
                BugSeverity.crash:    allLogs.where((e) => e.severity == BugSeverity.crash).length,
                BugSeverity.error:    allLogs.where((e) => e.severity == BugSeverity.error).length,
                BugSeverity.warning:  allLogs.where((e) => e.severity == BugSeverity.warning).length,
                BugSeverity.info:     allLogs.where((e) => e.severity == BugSeverity.info).length,
              },
            ),
            Expanded(
              child: logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No logs yet\nAll clear! ✅',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF64B5F6),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(8),
                      itemCount: logs.length,
                      itemBuilder: (ctx, i) => _LogTile(entry: logs[i]),
                    ),
            ),
            _BottomBar(
              autoScroll: autoScroll,
              onAutoScrollChanged: onAutoScrollChanged,
              logCount: logs.length,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Panel header ─────────────────────────────────────────────────
class _PanelHeader extends StatelessWidget {
  final VoidCallback onClose, onClear;
  final int total, crashes, errors, warns;
  const _PanelHeader({
    required this.onClose, required this.onClear,
    required this.total, required this.crashes,
    required this.errors, required this.warns,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF13132B),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.bug_report_rounded, color: Color(0xFF7B61FF), size: 20),
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              'BeatFlow Debug',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _Chip('${crashes}💥', const Color(0xFFFF4444)),
          const SizedBox(width: 4),
          _Chip('${errors}🟠', const Color(0xFFFF9800)),
          const SizedBox(width: 4),
          _Chip('${warns}🟡', const Color(0xFFFFD740)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFF9E9E9E), size: 18),
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF9E9E9E), size: 18),
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 10, fontFamily: 'monospace')),
      );
}

// ── Filter bar ───────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  final BugSeverity? selected;
  final ValueChanged<BugSeverity?> onChanged;
  final Map<BugSeverity?, int> counts;
  const _FilterBar({required this.selected, required this.onChanged, required this.counts});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: const Color(0xFF0F0F24),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterBtn('ALL', null, counts[null] ?? 0, selected, onChanged, Colors.white70),
            _FilterBtn('CRASH', BugSeverity.crash, counts[BugSeverity.crash] ?? 0, selected, onChanged, const Color(0xFFFF4444)),
            _FilterBtn('ERROR', BugSeverity.error, counts[BugSeverity.error] ?? 0, selected, onChanged, const Color(0xFFFF9800)),
            _FilterBtn('WARN', BugSeverity.warning, counts[BugSeverity.warning] ?? 0, selected, onChanged, const Color(0xFFFFD740)),
            _FilterBtn('INFO', BugSeverity.info, counts[BugSeverity.info] ?? 0, selected, onChanged, const Color(0xFF64B5F6)),
          ],
        ),
      ),
    );
  }
}

class _FilterBtn extends StatelessWidget {
  final String label;
  final BugSeverity? value;
  final int count;
  final BugSeverity? selected;
  final ValueChanged<BugSeverity?> onChanged;
  final Color color;
  const _FilterBtn(this.label, this.value, this.count, this.selected, this.onChanged, this.color);

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : color.withOpacity(0.3),
            ),
          ),
          child: Text(
            '$label ($count)',
            style: TextStyle(
              color: isSelected ? color : color.withOpacity(0.6),
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

// ── Single log tile ──────────────────────────────────────────────
class _LogTile extends StatelessWidget {
  final BugEntry entry;
  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: entry.color.withOpacity(0.06),
        border: Border(
          left: BorderSide(color: entry.color, width: 3),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        dense: true,
        title: Row(
          children: [
            Text(
              entry.severityLabel,
              style: TextStyle(
                color: entry.color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B61FF).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.tag,
                  style: const TextStyle(
                    color: Color(0xFF7B61FF),
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              entry.fmtTime(entry.time),
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            entry.message,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        children: [
          if (entry.context != null && entry.context!.isNotEmpty) ...[
            const Divider(color: Colors.white12, height: 8),
            ...entry.context!.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.key}: ',
                    style: const TextStyle(
                      color: Color(0xFF64B5F6),
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value.toString(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],
          if (entry.stack != null) ...[
            const Divider(color: Colors.white12, height: 8),
            Text(
              entry.stack.toString().split('\n').take(8).join('\n'),
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Bottom bar ───────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  final bool autoScroll;
  final ValueChanged<bool> onAutoScrollChanged;
  final int logCount;
  const _BottomBar({required this.autoScroll, required this.onAutoScrollChanged, required this.logCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F0F24),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.circle, size: 8, color: Colors.greenAccent.withOpacity(0.8)),
          const SizedBox(width: 6),
          Text(
            '$logCount entries',
            style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
          ),
          const Spacer(),
          const Text(
            'Auto-scroll',
            style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 4),
          Switch(
            value: autoScroll,
            onChanged: onAutoScrollChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            activeColor: const Color(0xFF7B61FF),
          ),
        ],
      ),
    );
  }
}
