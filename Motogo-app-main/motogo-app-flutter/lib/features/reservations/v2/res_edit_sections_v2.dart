import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'res_fit_v2.dart';
import 'res_detail_bits_v2.dart';

/// v2 shell of `EditCard` (white card, 1 px line, r16) with the SAME outer
/// gutter, so the edit sections drop into the v2 page unchanged.
class EditCardV2 extends StatelessWidget {
  final Widget child;
  const EditCardV2({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Container(
          // 14 = the old EditCard's inner padding: the sections inside keep
          // exactly the width they were laid out for in all 8 languages.
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MgColors.line),
            boxShadow: MgShadows.card,
          ),
          child: child,
        ),
      );
}

/// v2 look of `EditTimePicker`: the SAME two dropdowns (hours 00–23,
/// minutes by quarter) with the same `onChanged` composition.
class EditTimePickerV2 extends StatelessWidget {
  final String label;
  final String hour;
  final String minute;
  final ValueChanged<String?> onHour;
  final ValueChanged<String?> onMinute;
  const EditTimePickerV2({
    super.key,
    required this.label,
    required this.hour,
    required this.minute,
    required this.onHour,
    required this.onMinute,
  });

  @override
  Widget build(BuildContext context) {
    Widget box(String value, List<String> items, ValueChanged<String?> onChanged) => Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MgColors.lineInput, width: 1.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                dropdownColor: MgColors.surface,
                icon: const MgIcon(MgIcons.chevronDown, size: 18, color: MgColors.link),
                // DropdownButton nahrazuje zděděný styl → bez merge by číslice
                // byly v systémovém písmu (Roboto), ne v Montserratu appky.
                style: DefaultTextStyle.of(context).style.merge(MgType.tab(MgType.h3.copyWith(color: MgColors.ink))),
                items: [for (final v in items) DropdownMenuItem(value: v, child: Center(child: Text(v)))],
                onChanged: onChanged,
              ),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.link)),
      const SizedBox(height: 8),
      Row(children: [
        box(hour, [for (var i = 0; i < 24; i++) i.toString().padLeft(2, '0')], onHour),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(':', style: MgType.h3.copyWith(color: MgColors.ink)),
        ),
        box(minute, const ['00', '15', '30', '45'], onMinute),
      ]),
    ]);
  }
}

/// v2 look of `EditCalendarSection`: Termín + day delta, the shorten
/// direction choice (same callbacks), today's instruction line, the new
/// Vyzvednutí → Vrácení boxes and the calendar (its own V-seam).
class EditCalendarSectionV2 extends StatelessWidget {
  final String tab;
  final bool isActive;
  final DateTime? newStart;
  final DateTime? newEnd;
  final int diffDays;
  final String? shortenDir;
  final String instruction;
  final Widget calendar;
  final VoidCallback onShortenStart;
  final VoidCallback onShortenEnd;

  const EditCalendarSectionV2({
    super.key,
    required this.tab,
    required this.isActive,
    required this.newStart,
    required this.newEnd,
    required this.diffDays,
    required this.shortenDir,
    required this.instruction,
    required this.calendar,
    required this.onShortenStart,
    required this.onShortenEnd,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    String date(DateTime? d) => d == null ? '–' : tripShortDate(tr, d);
    return EditCardV2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: ResSectionEyebrowV2(tr.tr('termLabel'))),
          if (diffDays != 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: diffDays > 0 ? MgColors.tintOk : MgColors.errBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('${diffDays > 0 ? '+' : '−'}${diffDays.abs()} ${tr.daysWord(diffDays.abs())}',
                  style: MgType.tab(MgType.meta.copyWith(
                      fontWeight: FontWeight.w800, color: diffDays > 0 ? MgColors.onTintOk : MgColors.err))),
            ),
        ]),
        if (tab == 'shorten' && !isActive) ...[
          const SizedBox(height: 12),
          // Vedle sebe jen když se popisky vejdou celými slovy (fr / uk na
          // 320 dp s velkým písmem) — jinak pod sebou.
          LayoutBuilder(builder: (context, c) {
            final start = MgChoiceChip(label: tr.tr('shortenStart'), selected: shortenDir == 'start', onTap: onShortenStart);
            final end = MgChoiceChip(label: tr.tr('shortenEnd'), selected: shortenDir == 'end', onTap: onShortenEnd);
            // Chip: padding 2×14 + rámeček + ✓ 16 + 6 (vybraný).
            final w = (c.maxWidth - 8) / 2 - 52;
            final style = MgType.small.copyWith(fontWeight: FontWeight.w800);
            final row = resWordsFit(context, tr.tr('shortenStart'), style, w, minScale: 0.8) &&
                resWordsFit(context, tr.tr('shortenEnd'), style, w, minScale: 0.8);
            if (!row) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [start, const SizedBox(height: 8), end]);
            }
            return Row(children: [Expanded(child: start), const SizedBox(width: 8), Expanded(child: end)]);
          }),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MgColors.well,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MgColors.line),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const MgIcon(MgIcons.info, size: 18, color: MgColors.link),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(instruction, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.body2)),
                if (tab == 'extend')
                  Text(tr.tr('v2BkSingleDayHint'), style: MgType.meta.copyWith(color: MgColors.meta)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _dateBox(tr.tr('pickupEditLabel'), date(newStart))),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: MgIcon(MgIcons.arrowRight, size: 18, color: MgColors.meta),
          ),
          Expanded(child: _dateBox(tr.tr('returnEditLabel'), date(newEnd))),
        ]),
        const SizedBox(height: 12),
        calendar,
      ]),
    );
  }

  Widget _dateBox(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MgColors.lineInput, width: 1.5),
        ),
        // Celá slova (uk „ПОВЕРНЕННЯ", cs „VYZVEDNUTÍ" v půlce 320 dp s
        // velkým písmem): radši menší než rozdělené.
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MgWordFit(
            minScale: 0.7,
            child: Text(label.toUpperCase(), maxLines: 2, style: MgType.micro.copyWith(letterSpacing: 0.4, color: MgColors.meta)),
          ),
          const SizedBox(height: 2),
          MgWordFit(
            minScale: 0.8,
            fitLines: 1,
            child: Text(value, style: MgType.tab(MgType.title.copyWith(color: MgColors.ink))),
          ),
        ]),
      );
}

/// v2 look of the extras section's "ŘIDIČ · zdarma … Mám vlastní výbavu"
/// row: the SAME toggle callback; wraps instead of overflowing when a
/// language is long (de at 360 px overflowed the old single row).
class EditRiderHeaderV2 extends StatelessWidget {
  final String rider;
  final String free;
  final String ownGearLabel;
  final bool ownGear;
  final VoidCallback onToggle;
  const EditRiderHeaderV2({
    super.key,
    required this.rider,
    required this.free,
    required this.ownGearLabel,
    required this.ownGear,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: rider, style: MgType.eyebrow.copyWith(color: MgColors.link)),
          TextSpan(text: '  ·  $free', style: MgType.meta.copyWith(color: MgColors.meta)),
        ])),
        Semantics(
          toggled: ownGear,
          button: true,
          label: ownGearLabel,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                MgIcon(ownGear ? MgIcons.checkCircle : MgIcons.check, size: 18, color: ownGear ? MgColors.link : MgColors.meta),
                const SizedBox(width: 6),
                // Delší popisek (de „Ich habe meine eigene Ausrüstung") se
                // zalomí v mezeře místo přetečení vpravo.
                Flexible(
                  child: MgWordFit(
                    child: Text(ownGearLabel,
                        style: MgType.small.copyWith(
                            fontWeight: FontWeight.w700, color: ownGear ? MgColors.ink : MgColors.lead)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}
