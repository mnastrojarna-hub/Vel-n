import 'package:flutter/material.dart';

import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_type.dart';
import 'mg_ai_fab.dart';
import 'mg_chrome_metrics.dart';

/// Bottom action dock (REZERVOVAT, ZAPLATIT, NAVIGOVAT, ZAZNAMENAT JÍZDU…):
/// solid night (no backdrop blur in Flutter → a translucent fill let the
/// page text show through) + sticky shadow, r20 top, neon hairline, 10 / 16 / safe-area
/// padding (V22 `dock`). [contextLine] = one line above the action (dates,
/// amber blocker), [trailing] = e.g. "Rozpis ▴", [aiDisc] docks the 44 px
/// AI disc into the context row (screens where the floating button is
/// hidden). [light] = white T1 dock with a top hairline. The dock reports
/// its height to the shell so strips / padding sit above it.
class MgDock extends StatefulWidget {
  final Widget child;
  final Widget? contextLine;
  final Widget? trailing;
  final bool aiDisc;
  final VoidCallback? onAi;
  final bool light;

  /// Add the bottom safe area (off when the dock sits above the nav).
  final bool safeArea;

  const MgDock({
    super.key,
    required this.child,
    this.contextLine,
    this.trailing,
    this.aiDisc = false,
    this.onAi,
    this.light = false,
    this.safeArea = true,
  });

  @override
  State<MgDock> createState() => _MgDockState();
}

class _MgDockState extends State<MgDock> {
  MgShellChrome? _chrome;
  ModalRoute<dynamic>? _route;
  bool _covered = false;

  /// A dock under a pushed page is invisible: it must not lift the strips
  /// or the AI button (`MgShellChrome.dockHeight` skips it).
  bool _visible() => mounted && !_covered;

  void _onCover(AnimationStatus status) {
    final covered = status == AnimationStatus.forward || status == AnimationStatus.completed;
    if (covered == _covered) return;
    _covered = covered;
    final c = _chrome;
    WidgetsBinding.instance.addPostFrameCallback((_) => c?.dockVisibilityChanged());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chrome = MgChromeScope.chromeOf(context);
    final r = ModalRoute.of(context);
    if (r != _route) {
      _route?.secondaryAnimation?.removeStatusListener(_onCover);
      _route = r;
      final a = r?.secondaryAnimation;
      a?.addStatusListener(_onCover);
      _covered = a != null && (a.status == AnimationStatus.forward || a.status == AnimationStatus.completed);
    }
  }

  @override
  void dispose() {
    _route?.secondaryAnimation?.removeStatusListener(_onCover);
    final c = _chrome;
    WidgetsBinding.instance.addPostFrameCallback((_) => c?.removeDock(this));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = widget.safeArea ? MediaQuery.paddingOf(context).bottom : 0.0;
    final hasRow = widget.contextLine != null || widget.trailing != null || widget.aiDisc;
    final fg = widget.light ? MgColors.ink : MgColors.onDarkLead;
    final dock = Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottom),
      decoration: BoxDecoration(
        color: widget.light ? MgColors.surface : MgColors.night,
        borderRadius: widget.light ? null : const BorderRadius.vertical(top: Radius.circular(20)),
        border: widget.light ? const Border(top: BorderSide(color: MgColors.line)) : null,
        boxShadow: widget.light ? null : MgShadows.sticky,
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        if (!widget.light)
          Positioned(
            left: 8,
            right: 8,
            top: -10,
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  MgColors.neonA(0),
                  MgColors.neonA(0.38),
                  MgColors.neonA(0),
                ]),
              ),
            ),
          ),
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (hasRow)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 28),
                child: Row(children: [
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: fg),
                      child: widget.contextLine ?? const SizedBox.shrink(),
                    ),
                  ),
                  if (widget.trailing != null) widget.trailing!,
                  if (widget.aiDisc) ...[
                    const SizedBox(width: 8),
                    MgAiDisc(size: 44, glow: false, onTap: widget.onAi),
                  ],
                ]),
              ),
            ),
          widget.child,
        ]),
      ]),
    );
    return MgSizeReporter(
      onSize: (s) => _chrome?.reportDock(this, s.height, visible: _visible),
      child: dock,
    );
  }
}
