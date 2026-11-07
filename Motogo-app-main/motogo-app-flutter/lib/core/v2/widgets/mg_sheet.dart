import 'package:flutter/material.dart';

import '../gestures/mg_swipe.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import 'mg_back_v2.dart';
import 'mg_sheet_pull.dart';
import 'mg_word_fit.dart';

/// Opens a v2 bottom sheet (light by default, V22 R5.10): grabber 42×5,
/// ✕ 44 top-right, r22 top, swipe-down + scrim tap close it, content
/// scrolls, [footer] buttons stay pinned. [onClose] = what ✕ does (default
/// `maybePop`, which respects the caller's `PopScope` — dirty forms keep
/// their existing discard confirm). Motion: in 300 emphasized / out 250,
/// none under reduced motion (`MgMotion.sheetStyle`).
Future<T?> showMgSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  Widget? footer,
  bool light = true,
  double maxHeightFactor = 0.86,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = true,
  VoidCallback? onClose,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 4, 16, 16),
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: MgColors.nightA(0.55),
    elevation: 0,
    sheetAnimationStyle: MgMotion.sheetStyle(context),
    builder: (ctx) => MgSheetFrame(
      title: title,
      light: light,
      footer: footer,
      maxHeightFactor: maxHeightFactor,
      onClose: onClose,
      padding: padding,
      child: Builder(builder: builder),
    ),
  );
}

/// The v2 sheet chrome (usable inside an existing `showModalBottomSheet`
/// builder, so old sheet logic keeps its own route / result handling).
///
/// Swipe-down (design G3): the grabber / header drag is the route's own;
/// with [dragToDismiss] a scrolling body pulled down at its scroll top moves
/// the sheet too — release past 25 % of its height or faster than 700 px/s
/// → `Navigator.maybePop` (a `PopScope` keeps it open → springs back), else
/// it springs back over `MgMotion.sheet`. Reduced motion: no follow, same
/// release rule.
class MgSheetFrame extends StatefulWidget {
  final Widget child;
  final String? title;
  final Widget? footer;
  final bool light;
  final double maxHeightFactor;
  final VoidCallback? onClose;
  final bool showClose;
  final bool scrollable;
  final EdgeInsetsGeometry padding;

  /// null = auto: on inside a `ModalBottomSheetRoute` with `enableDrag`.
  final bool? dragToDismiss;

  const MgSheetFrame({
    super.key,
    required this.child,
    this.title,
    this.footer,
    this.light = true,
    this.maxHeightFactor = 0.86,
    this.onClose,
    this.showClose = true,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 16),
    this.dragToDismiss,
  });

  @override
  State<MgSheetFrame> createState() => _MgSheetFrameState();
}

class _MgSheetFrameState extends State<MgSheetFrame> with SingleTickerProviderStateMixin {
  late final MgSheetPull _pull = MgSheetPull(() {
    if (mounted) setState(() {});
  });
  late final MgSheetPullPhysics _physics = MgSheetPullPhysics(_pull);
  late final AnimationController _back = AnimationController(vsync: this, duration: MgMotion.sheet);
  double _from = 0;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _back.addListener(() => _pull.reset(_from * (1 - MgMotion.emphasized.transform(_back.value))));
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  bool _dragOn(BuildContext context) {
    if (widget.dragToDismiss != null) return widget.dragToDismiss!;
    final r = ModalRoute.of(context);
    return r is ModalBottomSheetRoute && r.enableDrag;
  }

  void _springBack() {
    if (_pull.dy <= 0) return;
    if (MgMotion.reduced(context)) {
      _pull.reset(0);
      return;
    }
    _from = _pull.dy;
    _back.forward(from: 0);
  }

  bool _onEnd(ScrollEndNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical || _pull.dy <= 0 || _closing) return false;
    final v = n.dragDetails?.primaryVelocity ?? 0;
    final h = context.size?.height ?? double.infinity;
    if (_pull.dy > h * MgSwipe.sheetDismissFraction || v > MgSwipe.sheetDismissVelocity) {
      _closing = true;
      Navigator.of(context).maybePop().then((popped) {
        if (!mounted) return;
        _closing = false;
        if (!popped) _springBack();
      });
    } else {
      _springBack();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final footer = widget.footer;
    final light = widget.light;
    final padding = widget.padding;
    final child = widget.child;
    final mq = MediaQuery.of(context);
    final maxH = (mq.size.height - mq.padding.top) * widget.maxHeightFactor;
    final fg = light ? MgColors.ink : MgColors.onDark;
    final close = widget.onClose ?? () => Navigator.of(context).maybePop();
    final pull = widget.scrollable && _dragOn(context);
    final body = widget.scrollable
        ? Flexible(
            child: pull
                ? NotificationListener<ScrollEndNotification>(
                    onNotification: _onEnd,
                    child: SingleChildScrollView(physics: _physics, padding: padding, child: child),
                  )
                : SingleChildScrollView(padding: padding, child: child),
          )
        : Flexible(child: Padding(padding: padding, child: child));
    final dy = pull && !MgMotion.reduced(context) ? _pull.dy : 0.0;
    final frame = Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Container(
          decoration: BoxDecoration(
            color: light ? MgColors.surface : null,
            gradient: light ? null : MgGradients.dark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(MgRadius.sheet)),
            boxShadow: MgShadows.sheet,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: DefaultTextStyle.merge(
              style: TextStyle(color: fg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: light ? MgColors.grabberLight : MgColors.white(0.25),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: title == null
                              ? const SizedBox(height: 44)
                              : Semantics(
                                  header: true,
                                  child: MgWordFit(minScale: 0.75, child: Text(title, style: MgType.h3.copyWith(color: fg))),
                                ),
                        ),
                        if (widget.showClose) ...[
                          const SizedBox(width: 8),
                          MgV2Back(
                            close: true,
                            style: light ? MgBackStyle.light : MgBackStyle.dark,
                            onTap: close,
                          ),
                        ],
                      ],
                    ),
                  ),
                  body,
                  if (footer != null)
                    Container(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + mq.padding.bottom),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: light ? MgColors.line : MgColors.white(0.08)),
                        ),
                      ),
                      child: footer,
                    )
                  else
                    SizedBox(height: mq.padding.bottom),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return dy == 0 ? frame : Transform.translate(offset: Offset(0, dy), child: frame);
  }
}

/// Two pinned sheet buttons (primary full width above the secondary) with
/// the v2 spacing.
class MgSheetButtons extends StatelessWidget {
  final Widget primary;
  final Widget? secondary;
  final Widget? tertiary;
  const MgSheetButtons({super.key, required this.primary, this.secondary, this.tertiary});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          if (secondary != null) ...[const SizedBox(height: MgSpace.s8), secondary!],
          if (tertiary != null) ...[const SizedBox(height: MgSpace.s4), Center(child: tertiary!)],
        ],
      );
}
