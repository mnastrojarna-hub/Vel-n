import 'package:flutter/material.dart';
import '../theme.dart';
import '../i18n/i18n_provider.dart';

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
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _dd<int>(
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
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: _dd<int>(
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
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _dd<int>(
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
                ),
              ),
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
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      hint: Text(hint,
          style: const TextStyle(fontSize: 13, color: MotoGoColors.g500)),
      items: items,
      onChanged: onChanged,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(),
      ),
    );
  }
}
