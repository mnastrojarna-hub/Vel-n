import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';

/// Product description (disclosure rule): 3 lines, and when it is longer
/// "Více ▾" opens the whole text in place (`MgAnimatedSize` 300; "Méně ▴"
/// closes it). Short texts show no link.
class ProductDescV2 extends StatefulWidget {
  final String text;
  const ProductDescV2({super.key, required this.text});

  @override
  State<ProductDescV2> createState() => _ProductDescV2State();
}

class _ProductDescV2State extends State<ProductDescV2> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final style = MgType.body.copyWith(color: MgColors.body2);
    return LayoutBuilder(builder: (context, c) {
      final tp = TextPainter(
        text: TextSpan(text: widget.text, style: DefaultTextStyle.of(context).style.merge(style)),
        maxLines: 3,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: c.maxWidth);
      final long = tp.didExceedMaxLines;
      tp.dispose();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MgAnimatedSize(
          duration: MgMotion.sheet,
          curve: MgMotion.emphasized,
          alignment: Alignment.topCenter,
          child: Text(widget.text,
              maxLines: _open || !long ? null : 3, overflow: _open || !long ? null : TextOverflow.ellipsis, style: style),
        ),
        if (long)
          MgBtnText(
            label: tr.tr(_open ? 'v2UxPsLessText' : 'v2UxPsMoreText'),
            icon: _open ? MgIcons.chevronUp : MgIcons.chevronDown,
            onTap: () => setState(() => _open = !_open),
          ),
      ]);
    });
  }
}
