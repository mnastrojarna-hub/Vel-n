import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'moto_filter_chips_v2.dart' show MotoFilterClearAllV2;

/// 5.0.1: with real filters on, the Motorky tab says so ABOVE the calendar
/// (the loud filter card sits under it, below the fold): a compact green
/// strip "Filtry zapnuté (n)" — a tap scrolls to the filter card — and
/// "Zrušit vše" (the card's own reset). Nothing without filters.
class MotorkyFilterStripV2 extends StatelessWidget {
  final int active;
  final VoidCallback onShow;
  final VoidCallback onReset;
  const MotorkyFilterStripV2({super.key, required this.active, required this.onShow, required this.onReset});

  @override
  Widget build(BuildContext context) {
    if (active <= 0) return const SizedBox.shrink();
    final tr = t(context);
    final title = tr.trArgs('motoFltOn', {'n': active});
    return Padding(
      key: const ValueKey('motorky-filter-strip'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 10, 4),
        decoration: BoxDecoration(
          color: MgColors.tintOk,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MgColors.link, width: 2),
          boxShadow: MgShadows.card,
        ),
        child: Row(children: [
          Expanded(
            child: Semantics(
              button: true,
              label: title,
              excludeSemantics: true,
              onTap: onShow,
              child: MgPress(
                onTap: onShow,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Row(children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: MgGradients.neon),
                      child: Center(child: MgIcon(MgIcons.filter, size: 16, color: MgColors.onNeon)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MgWordFit(
                        minScale: 0.75,
                        fitLines: 1,
                        child: Text(title, maxLines: 3, style: MgType.title.copyWith(color: MgColors.link)),
                      ),
                    ),
                    MgIcon(MgIcons.chevronDown, size: 18, color: MgColors.link),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.36),
            child: MotoFilterClearAllV2(
                label: tr.tr('motoFltClear'), onTap: onReset, keyName: 'motorky-filter-strip-clear'),
          ),
        ]),
      ),
    );
  }
}
