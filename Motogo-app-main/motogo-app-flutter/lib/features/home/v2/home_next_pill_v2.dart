import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../catalog/catalog_provider.dart';
import 'funnel_provider.dart';
import 'home_date_sheet_v2.dart';
import 'home_links.dart';

/// "Kdy jedeš příště?" (S1–S9, V22 `.pw`): white pill → light date sheet →
/// Motorky with the dates (written like the catalogue date picker); 48 ink
/// disc → the price calculator. With catalogue dates set it shows them + ✕.
class HomeNextPillV2 extends ConsumerWidget {
  const HomeNextPillV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final f = ref.watch(catalogFilterProvider);
    final s = f.startDate, e = f.endDate;
    final has = s != null && e != null;
    final current = has ? FunnelRange(s, e) : null;

    Future<void> pick() async {
      final r = await showHomeDateSheet(context, initial: current, applyLabel: tr.tr('v2HomeDateShow'));
      if (r != null && context.mounted) homeOpenBikes(context, ref, range: r);
    }

    void clear() {
      final cur = ref.read(catalogFilterProvider);
      ref.read(catalogFilterProvider.notifier).state = cur.copyWith(startDate: () => null, endDate: () => null);
    }

    final title = has
        ? '${tripShortDate(tr, s)} → ${tripShortDate(tr, e)} · ${current!.days} ${tr.daysWord(current.days)}'
        : tr.tr('v2HomePillTitle');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(children: [
        Expanded(
          child: Semantics(
            button: true,
            label: has ? '${tr.tr('v2HomePillTitle')} $title' : '$title ${tr.tr('v2HomePillSub')}',
            excludeSemantics: true,
            child: MgPress(
              onTap: pick,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: EdgeInsets.only(left: 16, right: has ? 0 : 12, top: 6, bottom: 6),
                decoration: BoxDecoration(
                  color: MgColors.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: has ? MgColors.link : MgColors.lineInput, width: 1.5),
                  boxShadow: MgShadows.card,
                ),
                child: Row(children: [
                  const MgIcon(MgIcons.calendarCheck, size: 20, color: MgColors.link),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(title,
                          maxLines: 2,
                          style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w800, height: 1.25, color: MgColors.ink))),
                      if (!has)
                        Text(tr.tr('v2HomePillSub'),
                            maxLines: 2, style: MgType.small.copyWith(height: 1.25, color: MgColors.lead)),
                    ]),
                  ),
                  if (has)
                    Semantics(
                      button: true,
                      label: tr.tr('v2HomeDateClear'),
                      child: MgPress(
                        onTap: clear,
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(child: MgIcon(MgIcons.close, size: 18, color: MgColors.ink)),
                        ),
                      ),
                    )
                  else
                    const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.lead),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: tr.tr('v2HomeCalcA11y'),
          excludeSemantics: true,
          child: MgPress(
            scale: 0.92,
            onTap: () => homeOpenCalculator(context, ref, range: current),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MgColors.ink,
                boxShadow: [BoxShadow(color: MgColors.nightA(0.8), blurRadius: 18, offset: const Offset(0, 8), spreadRadius: -10)],
              ),
              child: const Center(child: MgIcon(MgIcons.calc, size: 20, color: MgColors.neon)),
            ),
          ),
        ),
      ]),
    );
  }
}
