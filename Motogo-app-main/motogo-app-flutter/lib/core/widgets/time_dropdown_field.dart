import 'package:flutter/material.dart';
import '../theme.dart';

/// Jednotné zadávání času dvěma rozbalovacími nabídkami (hodina : minuta).
/// Stejné UI jako [DateDropdownField] (etalon — nastavení platnosti ŘP / datum
/// narození), jen pro čas. Nahrazuje nativní hodinový `showTimePicker`
/// v rezervaci (krok „Čas vyzvednutí").
///
/// Hodnota se předává jako "HH:mm" (např. "09:00"). `onChanged` dostane vždy
/// validní "HH:mm" string.
class TimeDropdownField extends StatelessWidget {
  final String value; // "HH:mm"
  final ValueChanged<String> onChanged;

  /// Krok minut v nabídce (default 15 → 00/15/30/45). Aktuální minuta se do
  /// nabídky vždy doplní, i když do kroku nespadá.
  final int minuteStep;

  const TimeDropdownField({
    super.key,
    required this.value,
    required this.onChanged,
    this.minuteStep = 15,
  });

  int get _hour {
    final p = value.split(':');
    return p.isNotEmpty ? (int.tryParse(p[0]) ?? 9).clamp(0, 23) : 9;
  }

  int get _minute {
    final p = value.split(':');
    return p.length > 1 ? (int.tryParse(p[1]) ?? 0).clamp(0, 59) : 0;
  }

  void _emit(int h, int m) {
    final hh = h.toString().padLeft(2, '0');
    final mm = m.toString().padLeft(2, '0');
    onChanged('$hh:$mm');
  }

  @override
  Widget build(BuildContext context) {
    final minutes = <int>{
      for (var m = 0; m < 60; m += (minuteStep <= 0 ? 15 : minuteStep)) m,
      _minute, // vždy zachovej aktuální minutu
    }.toList()
      ..sort();

    return Row(
      children: [
        Expanded(
          flex: 1,
          child: _dd<int>(
            value: _hour,
            items: [
              for (var h = 0; h <= 23; h++)
                DropdownMenuItem(
                    value: h, child: Text(h.toString().padLeft(2, '0'))),
            ],
            onChanged: (v) {
              if (v != null) _emit(v, _minute);
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(':',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: MotoGoColors.dark,
                  decoration: TextDecoration.none)),
        ),
        Expanded(
          flex: 1,
          child: _dd<int>(
            value: _minute,
            items: [
              for (final m in minutes)
                DropdownMenuItem(
                    value: m, child: Text(m.toString().padLeft(2, '0'))),
            ],
            onChanged: (v) {
              if (v != null) _emit(_hour, v);
            },
          ),
        ),
      ],
    );
  }

  Widget _dd<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
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
