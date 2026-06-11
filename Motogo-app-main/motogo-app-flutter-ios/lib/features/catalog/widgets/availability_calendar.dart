import 'package:flutter/material.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../moto_model.dart';

/// Interactive availability calendar — mirrors genCal() + pickS/pickD
/// from booking-search-cal.js and router.js.
class AvailabilityCalendar extends StatefulWidget {
  final List<BookedDateRange> bookedDates;
  final DateTime? selectedStart;
  final DateTime? selectedEnd;
  final void Function(DateTime start, DateTime end)? onRangeSelected;
  final void Function(DateTime date)? onDateTap;
  final void Function(DateTime date)? onStartSelected;
  final VoidCallback? onReset;
  final bool readOnly;
  final bool showLegend;

  const AvailabilityCalendar({
    super.key,
    this.bookedDates = const [],
    this.selectedStart,
    this.selectedEnd,
    this.onRangeSelected,
    this.onDateTap,
    this.onStartSelected,
    this.onReset,
    this.readOnly = false,
    this.showLegend = true,
  });

  @override
  State<AvailabilityCalendar> createState() => _AvailabilityCalendarState();
}

class _AvailabilityCalendarState extends State<AvailabilityCalendar> {
  late int _year;
  late int _month;
  int _step = 1; // 1 = select start, 2 = select end
  DateTime? _start;
  DateTime? _end;

  List<String> _getDayLabels(BuildContext context) => [
    t(context).tr('calMon'), t(context).tr('calTue'), t(context).tr('calWed'),
    t(context).tr('calThu'), t(context).tr('calFri'), t(context).tr('calSat'),
    t(context).tr('calSun'),
  ];

  List<String> _getMonths(BuildContext context) => [
    t(context).tr('calJan'), t(context).tr('calFeb'), t(context).tr('calMar'),
    t(context).tr('calApr'), t(context).tr('calMay'), t(context).tr('calJun'),
    t(context).tr('calJul'), t(context).tr('calAug'), t(context).tr('calSep'),
    t(context).tr('calOct'), t(context).tr('calNov'), t(context).tr('calDec'),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = widget.selectedStart?.year ?? now.year;
    _month = widget.selectedStart?.month ?? now.month;
    _start = widget.selectedStart;
    _end = widget.selectedEnd;
    if (_start != null && _end != null) _step = 1;
  }

  @override
  void didUpdateWidget(covariant AvailabilityCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedStart != widget.selectedStart ||
        oldWidget.selectedEnd != widget.selectedEnd) {
      _start = widget.selectedStart;
      _end = widget.selectedEnd;
      if (_start != null && _end != null) _step = 1;
    }
  }

  bool _isOccupied(DateTime date) {
    return widget.bookedDates.any((r) => r.containsDate(date));
  }

  bool _isUnconfirmed(DateTime date) {
    return widget.bookedDates.any((r) => r.containsDate(date) && r.status == 'pending');
  }

  bool _isPast(DateTime date) {
    final today = DateTime.now();
    return date.isBefore(DateTime(today.year, today.month, today.day));
  }

  bool _isInRange(DateTime date) {
    if (_start == null || _end == null) return false;
    return !date.isBefore(_start!) && !date.isAfter(_end!);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _onDayTap(DateTime date) {
    if (widget.readOnly) return;
    if (_isPast(date) || _isOccupied(date)) return;

    widget.onDateTap?.call(date);

    if (_step == 1) {
      // 3rd click on same single-day selection → RESET
      if (_start != null &&
          _end != null &&
          _isSameDay(date, _start!) &&
          _isSameDay(date, _end!)) {
        setState(() {
          _start = null;
          _end = null;
          _step = 1;
        });
        widget.onReset?.call();
        return;
      }
      setState(() {
        _start = date;
        _end = null;
        _step = 2;
      });
      widget.onStartSelected?.call(date);
    } else {
      if (date.isBefore(_start!)) return;
      // Check no occupied days in range
      var d = _start!;
      while (!d.isAfter(date)) {
        if (_isOccupied(d)) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t(context).tr('calRangeOccupied')),
            duration: const Duration(seconds: 2),
          ));
          return;
        }
        d = d.add(const Duration(days: 1));
      }
      setState(() {
        _end = date;
        _step = 1;
      });
      widget.onRangeSelected?.call(_start!, date);
    }
  }

  void _prevMonth() {
    setState(() {
      _month--;
      if (_month < 1) { _month = 12; _year--; }
    });
  }

  void _nextMonth() {
    setState(() {
      _month++;
      if (_month > 12) { _month = 1; _year++; }
    });
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final firstWeekday = DateTime(_year, _month, 1).weekday; // 1=Mon
    final offset = firstWeekday - 1;

    return Column(
      children: [
        // Month navigation
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: _prevMonth,
              icon: const Icon(Icons.chevron_left, color: MotoGoColors.black),
            ),
            Text(
              '${_getMonths(context)[_month - 1]} $_year',
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800,
                color: MotoGoColors.black,
              ),
            ),
            IconButton(
              onPressed: _nextMonth,
              icon: const Icon(Icons.chevron_right, color: MotoGoColors.black),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Day name headers
        Row(
          children: _getDayLabels(context).map((l) => Expanded(
            child: Center(
              child: Text(l, style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: MotoGoColors.g400,
              )),
            ),
          )).toList(),
        ),
        const SizedBox(height: 4),
        // Calendar grid
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // Empty cells for offset
            ...List.generate(offset, (_) => const SizedBox.shrink()),
            // Day cells
            ...List.generate(daysInMonth, (i) {
              final day = i + 1;
              final date = DateTime(_year, _month, day);
              return _DayCell(
                day: day,
                isPast: _isPast(date),
                isOccupied: _isOccupied(date),
                isUnconfirmed: _isUnconfirmed(date),
                isStart: _start != null &&
                    date.year == _start!.year &&
                    date.month == _start!.month &&
                    date.day == _start!.day,
                isEnd: _end != null &&
                    date.year == _end!.year &&
                    date.month == _end!.month &&
                    date.day == _end!.day,
                isInRange: _isInRange(date),
                isToday: _isToday(date),
                onTap: () => _onDayTap(date),
              );
            }),
          ],
        ),
        if (widget.showLegend) ...[
          const SizedBox(height: 8),
          // Legend — matches Capacitor: Volné, Obsazené, Nepotvrzené
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Legend(color: MotoGoColors.green, label: t(context).tr('calAvailable')),
              const SizedBox(width: 12),
              _Legend(color: MotoGoColors.dark, label: t(context).tr('calOccupied')),
            ],
          ),
        ],
        // Step indicator
        if (!widget.readOnly)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _step == 1
                  ? (_start == null
                      ? t(context).tr('calSelectPickup')
                      : (_end != null && _isSameDay(_start!, _end!)
                          ? t(context).tr('calClickToReset')
                          : t(context).tr('calClickToChange')))
                  : t(context).tr('calSelectReturn'),
              style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: MotoGoColors.g400,
              ),
            ),
          ),
      ],
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool isPast;
  final bool isOccupied;
  final bool isUnconfirmed;
  final bool isStart;
  final bool isEnd;
  final bool isInRange;
  final bool isToday;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.isPast,
    required this.isOccupied,
    this.isUnconfirmed = false,
    required this.isStart,
    required this.isEnd,
    required this.isInRange,
    required this.isToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color textColor;
    FontWeight weight = FontWeight.w600;
    BorderRadius radius = BorderRadius.circular(9); // .cd default

    if (isStart && isEnd) {
      // Single day selected (same start+end)
      bg = MotoGoColors.dark;
      textColor = Colors.white;
      weight = FontWeight.w900;
      radius = BorderRadius.circular(9);
    } else if (isStart) {
      // .sel-od: border-radius: 50% 0 0 50% (left half-circle)
      bg = MotoGoColors.dark;
      textColor = Colors.white;
      weight = FontWeight.w900;
      radius = const BorderRadius.only(
        topLeft: Radius.circular(50), bottomLeft: Radius.circular(50),
        topRight: Radius.zero, bottomRight: Radius.zero,
      );
    } else if (isEnd) {
      // .sel-do: border-radius: 0 50% 50% 0 (right half-circle)
      bg = MotoGoColors.dark;
      textColor = Colors.white;
      weight = FontWeight.w900;
      radius = const BorderRadius.only(
        topLeft: Radius.zero, bottomLeft: Radius.zero,
        topRight: Radius.circular(50), bottomRight: Radius.circular(50),
      );
    } else if (isInRange) {
      // .in-range: border-radius: 0 (flat rectangle)
      bg = MotoGoColors.dark;
      textColor = Colors.white;
      weight = FontWeight.w700;
      radius = BorderRadius.zero;
    } else if (isOccupied) {
      // occupied (confirmed or pending) — all dark
      bg = MotoGoColors.dark;
      textColor = Colors.white.withValues(alpha: 0.7);
      weight = FontWeight.w700;
    } else if (isPast) {
      // past days — dark
      bg = MotoGoColors.dark;
      textColor = Colors.white.withValues(alpha: 0.7);
      weight = FontWeight.w700;
    } else {
      // .free — bright green
      bg = MotoGoColors.green;
      textColor = Colors.black;
      weight = FontWeight.w600;
    }

    return GestureDetector(
      onTap: (isPast || isOccupied) ? null : onTap,
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: isToday && !isStart && !isEnd && !isInRange
              ? Border.all(color: MotoGoColors.green, width: 2)
              : null,
        ),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(fontSize: 12, fontWeight: weight, color: textColor),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final bool hasBorder;
  const _Legend({required this.color, required this.label, this.hasBorder = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(3),
            border: hasBorder ? Border.all(color: MotoGoColors.g200) : null),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
      ],
    );
  }
}
