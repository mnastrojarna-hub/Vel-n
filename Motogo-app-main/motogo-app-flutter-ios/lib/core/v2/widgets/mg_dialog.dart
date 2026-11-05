import 'package:flutter/material.dart';

import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import 'mg_buttons.dart';
import 'mg_word_fit.dart';

/// T6 confirmation of an irreversible step (storno, end recording, delete):
/// r22, title 20/800, body 14/600, SAFE button left (ghost), ACTION right
/// (ink or red). Returns true = action, false = safe, null = dismissed.
Future<bool?> showMgConfirm(
  BuildContext context, {
  required String title,
  String? body,
  required String safeLabel,
  required String actionLabel,
  bool destructive = false,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
    barrierColor: MgColors.nightA(0.55),
    builder: (ctx) => MgDialogFrame(
      title: title,
      body: body,
      safe: MgBtnGhostLight(label: safeLabel, onTap: () => Navigator.of(ctx).pop(false)),
      action: destructive
          ? MgBtnDestructive(label: actionLabel, onTap: () => Navigator.of(ctx).pop(true))
          : MgBtnInk(label: actionLabel, onTap: () => Navigator.of(ctx).pop(true)),
      safeLabel: safeLabel,
      actionLabel: actionLabel,
    ),
  );
}

/// The v2 dialog body. Buttons sit side by side (safe left, action right)
/// and stack (action on top) when a label would not fit one line — never
/// ellipsized. [content] replaces [body] for custom widgets.
class MgDialogFrame extends StatelessWidget {
  final String? title;
  final String? body;
  final Widget? content;
  final Widget? safe;
  final Widget? action;

  /// Labels used to decide side-by-side vs stacked (optional).
  final String? safeLabel;
  final String? actionLabel;

  /// Extra buttons below (e.g. "Zavolat").
  final List<Widget> extra;

  const MgDialogFrame({
    super.key,
    this.title,
    this.body,
    this.content,
    this.safe,
    this.action,
    this.safeLabel,
    this.actionLabel,
    this.extra = const [],
  });

  bool _fitsSideBySide(BuildContext context, double width) {
    final half = (width - MgSpace.s8) / 2 - 32;
    for (final l in [safeLabel, actionLabel]) {
      if (l == null) continue;
      final tp = TextPainter(
        text: TextSpan(text: l, style: DefaultTextStyle.of(context).style.merge(MgType.button)),
        textDirection: Directionality.of(context),
        maxLines: 1,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final w = tp.width;
      tp.dispose();
      if (w > half) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: MgColors.surface,
      surfaceTintColor: Colors.transparent,
      // Úzký telefon (< 360 dp): víc místa pro titulek a text.
      insetPadding: EdgeInsets.symmetric(horizontal: MediaQuery.sizeOf(context).width < 360 ? 16 : 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MgRadius.sheet)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: LayoutBuilder(builder: (context, c) {
          final buttons = <Widget>[];
          if (safe != null && action != null) {
            if (_fitsSideBySide(context, c.maxWidth)) {
              buttons.add(Row(children: [
                Expanded(child: safe!),
                const SizedBox(width: MgSpace.s8),
                Expanded(child: action!),
              ]));
            } else {
              buttons.addAll([action!, const SizedBox(height: MgSpace.s8), safe!]);
            }
          } else if (action != null) {
            buttons.add(action!);
          } else if (safe != null) {
            buttons.add(safe!);
          }
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  Semantics(
                    header: true,
                    // Titulek: nejdřív zmenšit, nikdy nedělit slovo.
                    child: MgWordFit(minScale: 0.75, child: Text(title!, style: MgType.h3.copyWith(color: MgColors.ink))),
                  ),
                if (body != null) ...[
                  const SizedBox(height: 10),
                  MgWordFit(minScale: 0.85, child: Text(body!, style: MgType.body.copyWith(color: MgColors.body2))),
                ],
                if (content != null) ...[const SizedBox(height: 10), content!],
                if (buttons.isNotEmpty) ...[const SizedBox(height: 20), ...buttons],
                for (final e in extra) ...[const SizedBox(height: MgSpace.s8), e],
              ],
            ),
          );
        }),
      ),
    );
  }
}
