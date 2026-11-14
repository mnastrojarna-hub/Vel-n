import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/motion/mg_sticky_slide.dart';

/// Builds one v2 status strip (the shell FAB's v2 face). [more] / [onMore]
/// = an optional "+n" chip; [beforeTap] runs right before the strip's own
/// tap action.
typedef ShellStripBuilder = Widget Function({int more, VoidCallback? onMore, VoidCallback? beforeTap});

/// One active strip: [id] = its kind (stable key for the enter / exit).
class ShellStripEntry {
  final String id;
  final ShellStripBuilder build;
  const ShellStripEntry(this.id, this.build);
}

/// EVERY active strip stacked (8 px gap) in the existing priority order,
/// each with its own tap and ✕ — as the old pills and the first v2 shell
/// (owner rule "nothing harder to reach" over v1 C2's one strip + "+n").
/// A strip that appears slides up / fades in, one that goes away slides
/// down / fades out and gives its height back (`MgStickySlide`, `sticky`
/// 300 emphasized); the first frame shows the strips without motion.
/// Reduced motion: instant.
class ShellStripHostV2 extends StatefulWidget {
  final List<ShellStripEntry> entries;
  const ShellStripHostV2({super.key, required this.entries});

  @override
  State<ShellStripHostV2> createState() => _ShellStripHostV2State();
}

class _Slot {
  ShellStripEntry entry;
  bool leaving = false;
  bool entering;
  Timer? removal;
  _Slot(this.entry, {required this.entering});
}

class _ShellStripHostV2State extends State<ShellStripHostV2> {
  final List<_Slot> _slots = [];

  @override
  void initState() {
    super.initState();
    for (final e in widget.entries) {
      _slots.add(_Slot(e, entering: false));
    }
  }

  @override
  void didUpdateWidget(covariant ShellStripHostV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    final d = MgMotion.of(context, MgMotion.sticky);
    final ids = [for (final e in widget.entries) e.id];
    for (final s in _slots) {
      if (ids.contains(s.entry.id) || s.leaving) continue;
      s.leaving = true;
      if (d > Duration.zero) {
        s.removal = Timer(d, () {
          if (mounted) setState(() => _slots.remove(s));
        });
      }
    }
    // The priority order never changes between active strips: update them
    // in place, insert a new one right after its predecessor.
    String? prev;
    for (final e in widget.entries) {
      final i = _slots.indexWhere((s) => s.entry.id == e.id);
      if (i >= 0) {
        final s = _slots[i]
          ..entry = e
          ..leaving = false;
        s.removal?.cancel();
        s.removal = null;
      } else {
        final at = prev == null ? 0 : _slots.indexWhere((s) => s.entry.id == prev) + 1;
        _slots.insert(at, _Slot(e, entering: d > Duration.zero));
      }
      prev = e.id;
    }
    if (d == Duration.zero) _slots.removeWhere((s) => s.leaving);
    if (_slots.any((s) => s.entering)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          for (final s in _slots) {
            s.entering = false;
          }
        });
      });
    }
  }

  @override
  void dispose() {
    for (final s in _slots) {
      s.removal?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < _slots.length; i++)
        KeyedSubtree(
          key: ValueKey('strip-${_slots[i].entry.id}'),
          child: MgStickySlide(
            visible: !_slots[i].leaving && !_slots[i].entering,
            collapse: true,
            // 8 px above every strip but the first (collapses with it).
            child: Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: _slots[i].entry.build(),
            ),
          ),
        ),
    ]);
  }
}
