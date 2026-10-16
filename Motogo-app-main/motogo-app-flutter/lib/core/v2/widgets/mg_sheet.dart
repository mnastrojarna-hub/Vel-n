import 'package:flutter/material.dart';

import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import 'mg_back_v2.dart';

/// Opens a v2 bottom sheet (light by default, V22 R5.10): grabber 42×5,
/// ✕ 44 top-right, r22 top, swipe-down + scrim tap close it, content
/// scrolls, [footer] buttons stay pinned. [onClose] = what ✕ does (default
/// `maybePop`, which respects the caller's `PopScope` — dirty forms keep
/// their existing discard confirm).
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
class MgSheetFrame extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? footer;
  final bool light;
  final double maxHeightFactor;
  final VoidCallback? onClose;
  final bool showClose;
  final bool scrollable;
  final EdgeInsetsGeometry padding;

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
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = (mq.size.height - mq.padding.top) * maxHeightFactor;
    final fg = light ? MgColors.ink : MgColors.onDark;
    final close = onClose ?? () => Navigator.of(context).maybePop();
    final body = scrollable
        ? Flexible(child: SingleChildScrollView(padding: padding, child: child))
        : Flexible(child: Padding(padding: padding, child: child));
    return Padding(
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
                                  child: Text(title!, style: MgType.h3.copyWith(color: fg)),
                                ),
                        ),
                        if (showClose) ...[
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
