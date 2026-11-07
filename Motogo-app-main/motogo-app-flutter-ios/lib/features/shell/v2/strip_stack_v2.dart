import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/widgets/mg_sheet.dart';

/// Builds one v2 status strip (the shell FAB's v2 face). [more] / [onMore]
/// = the "+n" chip of the top strip; [beforeTap] runs right before the
/// strip's own tap action (closes the "+n" sheet).
typedef ShellStripBuilder = Widget Function({int more, VoidCallback? onMore, VoidCallback? beforeTap});

/// One active strip: [id] = its kind (stable key for the enter / exit).
class ShellStripEntry {
  final String id;
  final ShellStripBuilder build;
  const ShellStripEntry(this.id, this.build);
}

/// v1 C2 / V2 §4.4: ONLY the most urgent strip (existing priority order) +
/// a "+n" chip when more are active. A strip change slides / fades in over
/// `sticky` 300 emphasized (instant under reduced motion).
class ShellStripHostV2 extends StatelessWidget {
  final List<ShellStripEntry> entries;
  final VoidCallback onMore;
  const ShellStripHostV2({super.key, required this.entries, required this.onMore});

  @override
  Widget build(BuildContext context) {
    final d = MgMotion.of(context, MgMotion.sticky);
    final top = entries.isEmpty ? null : entries.first;
    final more = entries.length - 1;
    return AnimatedSwitcher(
      duration: d,
      switchInCurve: MgMotion.emphasized,
      switchOutCurve: MgMotion.emphasized,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.bottomCenter,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
      child: top == null
          ? const SizedBox.shrink(key: ValueKey('strip-none'))
          : KeyedSubtree(
              key: ValueKey('strip-${top.id}'),
              child: top.build(more: more, onMore: more > 0 ? onMore : null),
            ),
    );
  }
}

/// "+n" → light sheet listing every active strip (v1 C2) with its own tap /
/// ✕ actions. The list follows the providers live ([entriesOf] re-reads
/// them); a tap closes the sheet first, ✕ keeps it open (its confirm /
/// cancel runs from the row); the sheet closes itself when at most one
/// strip is left.
Future<void> showShellStripsSheet(
  BuildContext context,
  List<ShellStripEntry> Function(WidgetRef ref) entriesOf,
) {
  return showMgSheet<void>(
    context,
    title: t(context).tr('v2UxShStripsTitle'),
    builder: (sheetCtx) => Consumer(builder: (c, ref, _) {
      final list = entriesOf(ref);
      if (list.length <= 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final route = ModalRoute.of(sheetCtx);
          if (sheetCtx.mounted && route != null && route.isCurrent) Navigator.of(sheetCtx).pop();
        });
      }
      void close() => Navigator.of(sheetCtx).pop();
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          KeyedSubtree(key: ValueKey('sheet-strip-${list[i].id}'), child: list[i].build(beforeTap: close)),
        ],
      ]);
    }),
  );
}
