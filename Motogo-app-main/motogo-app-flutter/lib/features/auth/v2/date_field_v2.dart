import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../../../core/v2/widgets/mg_text_fit.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../booking/v2/booking_v2_parts.dart' show BkSizeChip;

/// v2 look of `DateDropdownField` (register date of birth / licence
/// validity, profile): three input-like boxes Den · Měsíc · Rok (1 : 1.4 :
/// 1, one row even at 320 dp) instead of the Material dropdown menus; a
/// tap opens a light sheet with the SAME values as the old menu (days
/// 01–31, months "05 — Květen", the field's year list) as the booking
/// chips, the current one selected and scrolled into view. A tap calls the
/// field's own setter (same state + emit) and closes; ✕ / swipe-down keep
/// the value.
class DateFieldRowV2 extends StatelessWidget {
  final int? day;
  final int? month;
  final int? year;
  final List<int> years;
  final List<String> monthNames;
  final List<String> hints;
  final String label;
  final ValueChanged<int> onDay;
  final ValueChanged<int> onMonth;
  final ValueChanged<int> onYear;

  const DateFieldRowV2({
    super.key,
    required this.day,
    required this.month,
    required this.year,
    required this.years,
    required this.monthNames,
    required this.hints,
    required this.label,
    required this.onDay,
    required this.onMonth,
    required this.onYear,
  });

  static String _two(int v) => v.toString().padLeft(2, '0');

  void _open(BuildContext context, String hint, List<(int, String)> items, int? current, ValueChanged<int> onPick) {
    final key = GlobalKey();
    showMgSheet<void>(
      context,
      title: '$label · $hint',
      builder: (c) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = key.currentContext;
          if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, alignment: 0.3);
        });
        return Wrap(spacing: MgSpace.s8, runSpacing: MgSpace.s8, children: [
          for (final (v, text) in items)
            KeyedSubtree(
              key: v == current ? key : null,
              child: BkSizeChip(
                label: text,
                selected: v == current,
                onTap: () {
                  onPick(v);
                  Navigator.of(c).pop();
                },
              ),
            ),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget box(String hint, String? value, String? extra, VoidCallback onTap, {String? key}) => Semantics(
          button: true,
          label: '$label, $hint${value == null ? '' : ', $value${extra ?? ''}'}',
          excludeSemantics: true,
          onTap: onTap,
          child: MgPress(
            key: key == null ? null : ValueKey(key),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: MgColors.surface,
                borderRadius: BorderRadius.circular(MgRadius.button),
                border: Border.all(color: MgColors.lineInput, width: 1.5),
              ),
              child: Row(children: [
                Expanded(
                  child: value == null
                      ? MgWordFit(
                          minScale: 0.75,
                          child: Text(hint, maxLines: 1, style: MgType.body.copyWith(color: MgColors.meta)),
                        )
                      : LayoutBuilder(builder: (context, c) {
                          // The month name only when it fits WHOLE beside the
                          // number ("05 Květen"); never cut — else just "05".
                          final vs = MgType.tab(MgType.title.copyWith(color: MgColors.ink));
                          final es = MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.lead);
                          final e = extra;
                          final showExtra = e != null &&
                              c.maxWidth.isFinite &&
                              mgLineWidth(context, value, vs) + mgLineWidth(context, e, es) + 1 <= c.maxWidth;
                          return Row(children: [
                            Flexible(child: MgWordFit(minScale: 0.75, child: Text(value, maxLines: 1, style: vs))),
                            if (showExtra) Text(e, maxLines: 1, softWrap: false, style: es),
                          ]);
                        }),
                ),
                const MgIcon(MgIcons.chevronDown, size: 16, color: MgColors.link),
              ]),
            ),
          ),
        );
    final d = day, m = month, y = year;
    final dayBox = box(hints[0], d == null ? null : _two(d), null, key: 'date-v2-day', () {
      _open(context, hints[0], [for (var i = 1; i <= 31; i++) (i, _two(i))], d, onDay);
    });
    final monthBox = box(hints[1], m == null ? null : _two(m), m == null ? null : ' ${monthNames[m - 1]}', key: 'date-v2-month', () {
      _open(context, hints[1], [for (var i = 1; i <= 12; i++) (i, '${_two(i)} — ${monthNames[i - 1]}')], m, onMonth);
    });
    final yearBox = box(hints[2], y?.toString(), null, key: 'date-v2-year', () {
      _open(context, hints[2], [for (final v in years) (v, '$v')], y, onYear);
    });
    return LayoutBuilder(builder: (context, c) {
      // One row 1 : 1.4 : 1 while "1990" / the hints fit the year box
      // (320 dp at normal text); very large text → the year under them.
      // Widest of "0000" and the day / year hints ("Année"), each ≤ 75 %,
      // + 2 × 8 padding + chevron 16 + border + slack.
      final text = [
        mgLineWidth(context, '0000', MgType.tab(MgType.title)),
        mgLineWidth(context, hints[0], MgType.body),
        mgLineWidth(context, hints[2], MgType.body),
      ].reduce((a, b) => a > b ? a : b);
      final need = text * 0.75 + 16 + 16 + 3 + 2;
      final unit = (c.maxWidth - 16) / 34;
      if (!c.maxWidth.isFinite || unit * 10 >= need) {
        return Row(children: [
          Expanded(flex: 10, child: dayBox),
          const SizedBox(width: 8),
          Expanded(flex: 14, child: monthBox),
          const SizedBox(width: 8),
          Expanded(flex: 10, child: yearBox),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(flex: 10, child: dayBox),
          const SizedBox(width: 8),
          Expanded(flex: 14, child: monthBox),
        ]),
        const SizedBox(height: 8),
        Row(children: [Expanded(flex: 10, child: yearBox), const Spacer(flex: 14)]),
      ]);
    });
  }
}
