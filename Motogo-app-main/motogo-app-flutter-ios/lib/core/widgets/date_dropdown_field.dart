import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme.dart';
import '../i18n/i18n_provider.dart';
import '../v2/flag/v2_scope.dart';

/// Jednotné zadávání data 3 rozbalovacími nabídkami (den / měsíc / rok).
/// Etalon UI pro celou appku i web — používá se všude, kde se zadává datum
/// MIMO rezervační kalendář (datum narození, platnost ŘP apod.).
///
/// Dva režimy (zvol jeden):
///  • `controller` — zapisuje hodnotu jako "d. m. yyyy" (kompatibilní s
///    _parseCzDate / _toIsoDate v registraci), navazující validace beze změny.
///  • `value` + `onChanged` — pracuje přímo s DateTime? (profil).
class DateDropdownField extends StatefulWidget {
  final TextEditingController? controller;
  final DateTime? value;
  final ValueChanged<DateTime?>? onChanged;
  final String label;
  final int firstYear;
  final int lastYear;
  final bool yearsDescending;

  const DateDropdownField({
    super.key,
    this.controller,
    this.value,
    this.onChanged,
    required this.label,
    required this.firstYear,
    required this.lastYear,
    this.yearsDescending = false,
  });

  @override
  State<DateDropdownField> createState() => _DateDropdownFieldState();
}

class _DateDropdownFieldState extends State<DateDropdownField> {
  static const List<String> _monthAbbrKeys = [
    'calJan', 'calFeb', 'calMar', 'calApr', 'calMay', 'calJun',
    'calJul', 'calAug', 'calSep', 'calOct', 'calNov', 'calDec',
  ];
  static const _hintStyle = TextStyle(fontSize: 13, color: MotoGoColors.g500);
  int? _day;
  int? _month;
  int? _year;

  @override
  void initState() {
    super.initState();
    _initFromSource();
  }

  @override
  void didUpdateWidget(covariant DateDropdownField old) {
    super.didUpdateWidget(old);
    if (widget.controller == null && widget.value != old.value) {
      _initFromSource();
    }
  }

  void _initFromSource() {
    DateTime? d = widget.value;
    if (d == null && widget.controller != null) {
      final m = RegExp(r'^(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})$')
          .firstMatch(widget.controller!.text.trim());
      if (m != null) {
        d = DateTime(
          int.parse(m.group(3)!),
          int.parse(m.group(2)!),
          int.parse(m.group(1)!),
        );
      }
    }
    if (d != null) {
      _day = d.day;
      _month = d.month;
      _year = d.year;
    }
  }

  void _emit() {
    DateTime? d;
    if (_day != null && _month != null && _year != null) {
      d = DateTime(_year!, _month!, _day!);
    }
    if (widget.controller != null) {
      widget.controller!.text =
          d == null ? '' : '${d.day}. ${d.month}. ${d.year}';
    }
    widget.onChanged?.call(d);
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final monthNames = [for (final k in _monthAbbrKeys) tr.tr(k)];
    final years = <int>[];
    if (widget.yearsDescending) {
      for (var y = widget.lastYear; y >= widget.firstYear; y--) {
        years.add(y);
      }
    } else {
      for (var y = widget.firstYear; y <= widget.lastYear; y++) {
        years.add(y);
      }
    }
    Widget day([double pad = 10]) => _dd<int>(
      pad: pad,
      value: _day,
      hint: tr.tr('dateDay'),
      items: [
        for (var d = 1; d <= 31; d++)
          DropdownMenuItem(
              value: d, child: Text(d.toString().padLeft(2, '0'))),
      ],
      onChanged: (v) {
        setState(() => _day = v);
        _emit();
      },
    );
    Widget month([double pad = 10]) => _dd<int>(
      pad: pad,
      value: _month,
      hint: tr.tr('dateMonth'),
      items: [
        for (var m = 1; m <= 12; m++)
          DropdownMenuItem(
            value: m,
            child: Text(
              '${m.toString().padLeft(2, '0')} — ${monthNames[m - 1]}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        setState(() => _month = v);
        _emit();
      },
    );
    Widget year([double pad = 10]) => _dd<int>(
      pad: pad,
      value: _year,
      hint: tr.tr('dateYear'),
      items: [
        for (final y in years)
          DropdownMenuItem(value: y, child: Text(y.toString())),
      ],
      onChanged: (v) {
        setState(() => _year = v);
        _emit();
      },
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              widget.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MotoGoColors.dark,
              ),
            ),
          ),
          if (MgV2.on(context))
            _DateRowV2(
              day: day,
              month: month,
              year: year,
              values: [_day, _month, _year],
              years: years,
              hints: [tr.tr('dateDay'), tr.tr('dateMonth'), tr.tr('dateYear')],
            )
          else
            Row(
              children: [
                Expanded(flex: 3, child: day()),
                const SizedBox(width: 8),
                Expanded(flex: 5, child: month()),
                const SizedBox(width: 8),
                Expanded(flex: 4, child: year()),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dd<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    double pad = 10,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      hint: Text(hint, style: _hintStyle),
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: pad, vertical: 12),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// v2 look only (verify:render): the 3 : 5 : 4 row of today while the day,
/// month and year fit their share; otherwise one row with tighter padding
/// where day / year get exactly their width and the month the rest; when
/// even that is too narrow (320 dp, large text) the year moves to a second
/// line. A selected "05" / "1990" or a hint is never cut. The dropdowns are
/// the same widgets (only their side padding may be tighter).
class _DateRowV2 extends StatelessWidget {
  final Widget Function([double pad]) day, month, year;
  final List<int?> values;
  final List<int> years;
  final List<String> hints;
  const _DateRowV2({
    required this.day,
    required this.month,
    required this.year,
    required this.values,
    required this.years,
    required this.hints,
  });

  /// Field width around the shown text at side padding [pad] (measured:
  /// pad + 44 — arrow, outline, insets) + ½ px slack.
  static double _chrome(double pad) => pad + 44.5;
  static const _tight = 6.0;
  static const _gap = SizedBox(width: 8);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final style = Theme.of(context).textTheme.titleMedium ?? const TextStyle(fontSize: 16);
        final hint = style.merge(_DateDropdownFieldState._hintStyle);
        final scaler = MediaQuery.textScalerOf(context);
        double w(String s, TextStyle st) {
          final tp = TextPainter(
              text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)
            ..layout();
          final r = tp.width;
          tp.dispose();
          return r;
        }

        // Widest value of each list (digit widths summed — stable while the
        // customer picks), else the hint shown instead; the month name may
        // end in "…" (as today), its number never.
        final dw = [for (var i = 0; i < 10; i++) w('$i', style)];
        double digits(int n, int len) => n.toString().padLeft(len, '0').codeUnits.fold(0.0, (a, c) => a + dw[c - 48]);
        final dayT = values[0] != null ? [for (var d = 1; d <= 31; d++) digits(d, 2)].reduce(math.max) : w(hints[0], hint);
        final monthT = values[1] != null ? w('00 — …', style) : w(hints[1], hint);
        final yearT = values[2] != null && years.isNotEmpty
            ? years.map((y) => digits(y, 4)).reduce(math.max)
            : math.max(w(hints[2], hint), values[2] == null ? 0.0 : digits(values[2]!, 4));
        final avail = box.maxWidth - 16;
        final c = _chrome(10);
        if (avail * 3 / 12 >= dayT + c && avail * 5 / 12 >= monthT + c && avail * 4 / 12 >= yearT + c) {
          return Row(children: [
            Expanded(flex: 3, child: day()),
            _gap,
            Expanded(flex: 5, child: month()),
            _gap,
            Expanded(flex: 4, child: year()),
          ]);
        }
        final t = _chrome(_tight);
        if (dayT + monthT + yearT + 3 * t <= avail) {
          return Row(children: [
            SizedBox(width: dayT + t, child: day(_tight)),
            _gap,
            Expanded(child: month(_tight)),
            _gap,
            SizedBox(width: yearT + t, child: year(_tight)),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [SizedBox(width: dayT + c, child: day()), _gap, Expanded(child: month())]),
          const SizedBox(height: 8),
          SizedBox(width: math.min(yearT + c, box.maxWidth), child: year()),
        ]);
      });
}
