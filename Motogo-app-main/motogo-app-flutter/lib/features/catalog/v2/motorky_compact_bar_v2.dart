import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../catalog_provider.dart';
import 'catalog_text.dart';

/// MotoKatalog board "Po posunutí · kompaktní lišta" (CB-07): once the
/// dark header has scrolled away, a night bar keeps the trip and the two
/// tools in reach — compact date pill (+ "3 dny") → [onOpenDates], 44
/// filter disc with the active-filter badge → [onOpenFilters], 44
/// calculator disc → [onCalc]. Every action is the header's own.
class MotorkyCompactBarV2 extends ConsumerWidget {
  final VoidCallback onOpenDates;
  final VoidCallback onOpenFilters;
  final VoidCallback onCalc;

  const MotorkyCompactBarV2({
    super.key,
    required this.onOpenDates,
    required this.onOpenFilters,
    required this.onCalc,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final f = ref.watch(catalogFilterProvider);
    final s = f.startDate, e = f.endDate;
    final hasDates = s != null && e != null;
    final label = hasDates ? catRange(tr, s, e) : tr.tr('v2CatDateEmpty');
    return Container(
      padding: EdgeInsets.fromLTRB(MgSpace.gutter, MediaQuery.paddingOf(context).top + 8, MgSpace.gutter, 10),
      decoration: const BoxDecoration(color: MgColors.night, boxShadow: MgShadows.sticky),
      child: Row(children: [
        Expanded(
          child: Semantics(
            button: true,
            label: hasDates ? '$label, ${catDays(tr, catDayCount(s, e))}' : label,
            excludeSemantics: true,
            onTap: onOpenDates,
            child: MgPress(
              onTap: onOpenDates,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: MgColors.white(0.06),
                  borderRadius: BorderRadius.circular(MgRadius.button),
                  border: Border.all(color: hasDates ? MgColors.neonA(0.55) : MgColors.white(0.25), width: 1.5),
                ),
                child: Row(children: [
                  MgIcon(MgIcons.calendarCheck, size: 18, color: MgColors.neon),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MgWordFit(
                      minScale: 0.75,
                      fitLines: 1,
                      child: Text(label,
                          style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark))),
                    ),
                  ),
                  if (hasDates) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: MgColors.neonA(0.14), borderRadius: BorderRadius.circular(999)),
                      child: Text(catDays(tr, catDayCount(s, e)).replaceAll(' ', ' '),
                          style: MgType.tab(MgType.meta.copyWith(color: MgColors.neonText))),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        MgIconButton(
          icon: MgIcons.filter,
          badge: f.activeCount,
          semanticLabel: tr.trArgs('v2CatFiltersAria', {'n': f.activeCount}),
          onTap: onOpenFilters,
        ),
        MgIconButton(icon: MgIcons.calc, semanticLabel: tr.tr('v2CatModeCalc'), onTap: onCalc),
      ]),
    );
  }
}
