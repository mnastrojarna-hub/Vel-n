import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme.dart';
import '../i18n/i18n_provider.dart';
import '../v2/flag/v2_scope.dart';
import '../../features/auth/v2/date_field_v2.dart';

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
    // Uložený rok mimo [firstYear, lastYear] (prošlý ŘP — volající dává
    // firstYear = letošek; ročník nad lastYear) zůstane v nabídce: rozsah se
    // k němu roztáhne (pořadí beze změny), jinak assert dropdownu — hodnota
    // bez položky (pád v debugu, prázdné pole v release).
    final first = math.min(widget.firstYear, _year ?? widget.firstYear);
    final last = math.max(widget.lastYear, _year ?? widget.lastYear);
    final years = <int>[];
    if (widget.yearsDescending) {
      for (var y = last; y >= first; y--) {
        years.add(y);
      }
    } else {
      for (var y = first; y <= last; y++) {
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
            // v2: caps popisek nad polem (11.5/800 #55705F) jako ostatní pole.
            child: MgV2.on(context)
                ? Text(
                    widget.label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      height: 1.3,
                      color: Color(0xFF55705F),
                    ),
                  )
                : Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: MotoGoColors.dark,
                    ),
                  ),
          ),
          // v2: tři pole se světlým sheetem místo Material menu — tytéž
          // hodnoty, týž zápis (setState + _emit) jako dropdowny níže.
          if (MgV2.on(context))
            DateFieldRowV2(
              day: _day,
              month: _month,
              year: _year,
              years: years,
              monthNames: monthNames,
              hints: [tr.tr('dateDay'), tr.tr('dateMonth'), tr.tr('dateYear')],
              label: widget.label,
              onDay: (v) {
                setState(() => _day = v);
                _emit();
              },
              onMonth: (v) {
                setState(() => _month = v);
                _emit();
              },
              onYear: (v) {
                setState(() => _year = v);
                _emit();
              },
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
