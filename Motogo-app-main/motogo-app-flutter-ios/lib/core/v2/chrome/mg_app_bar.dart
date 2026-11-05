import 'package:flutter/material.dart';

import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_type.dart';
import '../widgets/mg_back_v2.dart';

/// Compact dark app bar (`gDark`, bottom r24) for pushed screens:
/// `MgV2Back` (dark style) + title 17/800 on one line, or 15/800 on two
/// lines when it does not fit — never an ellipsis. [onBack] = the SAME
/// callback the old screen used. [light] = light variant for focused forms.
class MgAppBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final bool close;
  final List<Widget> actions;
  final Widget? bottom;
  final bool light;
  final bool includeStatusBar;

  const MgAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.close = false,
    this.actions = const [],
    this.bottom,
    this.light = false,
    this.includeStatusBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final top = includeStatusBar ? MediaQuery.paddingOf(context).top : 0.0;
    final fg = light ? MgColors.ink : MgColors.onDark;
    return Container(
      decoration: BoxDecoration(
        gradient: light ? null : MgGradients.dark,
        color: light ? MgColors.surface : null,
        borderRadius: light ? null : const BorderRadius.vertical(bottom: Radius.circular(24)),
        border: light ? const Border(bottom: BorderSide(color: MgColors.line)) : null,
      ),
      padding: EdgeInsets.fromLTRB(12, top + 8, 12, bottom == null ? 14 : 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (onBack != null) ...[
            MgV2Back(onTap: onBack, close: close, style: light ? MgBackStyle.light : MgBackStyle.dark),
            const SizedBox(width: 10),
          ] else
            const SizedBox(width: 4),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final base = DefaultTextStyle.of(context).style.merge(MgType.section);
              final tp = TextPainter(
                text: TextSpan(text: title, style: base),
                maxLines: 1,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: c.maxWidth);
              final fits = !tp.didExceedMaxLines;
              tp.dispose();
              return Semantics(
                header: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    title,
                    maxLines: fits ? 1 : 2,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: (fits ? MgType.section : MgType.title).copyWith(color: fg),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: MgType.small.copyWith(color: light ? MgColors.meta : MgColors.onDarkMeta)),
                ]),
              );
            }),
          ),
          for (final a in actions) ...[const SizedBox(width: 6), a],
        ]),
        if (bottom != null) ...[const SizedBox(height: 10), bottom!],
      ]),
    );
  }
}
