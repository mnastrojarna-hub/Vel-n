import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../catalog_provider.dart';
import '../widgets/availability_calendar.dart';
import 'catalog_date_sheet_v2.dart' show catClearDates, catSetDates;

/// The old search screen's date block INLINE and always open (owner
/// 2026-11-07 "jen upgrade vzhledu"): VYZVEDNUTÍ / VRÁCENÍ tabs (a tap only
/// switches the step line, as `DateTabsSection` did), the "1" step line
/// (informal texts, M3-14), the single-day
/// hint and the SAME `AvailabilityCalendar` with the SAME writes to
/// `catalogFilterProvider` (`_onRangeSelected` / `onReset`) — v2 look.
class MotorkyDatesCardV2 extends ConsumerStatefulWidget {
  const MotorkyDatesCardV2({super.key});

  @override
  ConsumerState<MotorkyDatesCardV2> createState() => _MotorkyDatesCardV2State();
}

class _MotorkyDatesCardV2State extends ConsumerState<MotorkyDatesCardV2> {
  bool _pickingStart = true;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final f = ref.watch(catalogFilterProvider);
    Widget tab(String label, DateTime? d, bool on, VoidCallback onTap) => Expanded(
          child: Semantics(
            button: true,
            selected: on,
            label: '$label ${d == null ? tr.tr('efoSelectDate') : tripShortDate(tr, d)}',
            excludeSemantics: true,
            child: MgPress(
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: BoxDecoration(
                  color: on ? MgColors.tintOk : MgColors.well,
                  borderRadius: BorderRadius.circular(MgRadius.action),
                  border: Border.all(color: on ? MgColors.tintOkBorder : MgColors.line, width: on ? 1.5 : 1),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  // uk "ПОВЕРНЕННЯ" at 320 dp + large text: shrink, never split.
                  MgWordFit(
                    minScale: 0.65,
                    child: Text(label.toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.meta)),
                  ),
                  const SizedBox(height: 2),
                  MgWordFit(
                    minScale: 0.75,
                    child: Text(
                      d == null ? tr.tr('efoSelectDate') : tripShortDate(tr, d).replaceAll(' ', ' '),
                      style: MgType.tab(MgType.title.copyWith(color: d == null ? MgColors.lead : MgColors.ink)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: MgCard(
        key: const ValueKey('motorky-dates'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            tab(tr.tr('dateTabsPickup'), f.startDate, _pickingStart, () => setState(() => _pickingStart = true)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: MgIcon(MgIcons.arrowRight, size: 18, color: MgColors.link),
            ),
            tab(tr.tr('dateTabsReturn'), f.endDate, !_pickingStart, () => setState(() => _pickingStart = false)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle),
              child: Text('1',
                  style: MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.onNeon))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr.tr(_pickingStart ? 'efoCatPickStart' : 'efoCatPickEnd'),
                style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(tr.tr('v2BkSingleDayHint'), style: MgType.small.copyWith(color: MgColors.lead)),
          const SizedBox(height: 8),
          AvailabilityCalendar(
            onRangeSelected: (s, e) {
              setState(() => _pickingStart = true);
              catSetDates(ref, s, e);
            },
            onReset: () {
              setState(() => _pickingStart = true);
              catClearDates(ref);
            },
            selectedStart: f.startDate,
            selectedEnd: f.endDate,
          ),
        ]),
      ),
    );
  }
}
