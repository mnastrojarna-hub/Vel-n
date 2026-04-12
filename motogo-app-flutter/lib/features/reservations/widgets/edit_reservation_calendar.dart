import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../catalog/moto_model.dart';

/// Calendar widget for editing reservations (extend/shorten).
/// Mirrors pickE() + buildECal() + highlightEditResDates() from
/// booking-calendar.js and booking-detail-cal.js in the Capacitor app.
class EditReservationCalendar extends StatefulWidget {
  final List<BookedDateRange> bookedDates;
  final DateTime origStart;
  final DateTime origEnd;
  final DateTime? newStart;
  final DateTime? newEnd;
  final bool isActive;
  final String mode; // 'extend' or 'shorten'
  final String? shortenDir; // 'start' or 'end' (for upcoming shorten)
  final void Function(DateTime newStart, DateTime newEnd) onDatesChanged;
  final void Function(String message) onError;

  const EditReservationCalendar({
    super.key,
    required this.bookedDates,
    required this.origStart,
    required this.origEnd,
    this.newStart,
    this.newEnd,
    required this.isActive,
    required this.mode,
    this.shortenDir,
    required this.onDatesChanged,
    required this.onError,
  });

  @override
  State<EditReservationCalendar> createState() =>
      _EditReservationCalendarState();
}

class _EditReservationCalendarState extends State<EditReservationCalendar> {
  late int _year;
  late int _month;

  static const _dayLabels = ['PO', 'ÚT', 'ST', 'ČT', 'PÁ', 'SO', 'NE'];
  static const _months = [
    'Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen',
    'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec',
  ];

  @override
  void initState() {
    super.initState();
    _year = widget.origStart.year;
    _month = widget.origStart.month;
  }

  DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isPast(DateTime date) => _d(date).isBefore(_d(DateTime.now()));

  bool _isOccupiedOrPending(DateTime date) {
    final d = _d(date);
    return widget.bookedDates.any((r) => r.containsDate(d));
  }

  bool _isInOrigRange(DateTime date) {
    final d = _d(date);
    return !d.isBefore(_d(widget.origStart)) &&
        !d.isAfter(_d(widget.origEnd));
  }

  bool _isInNewRange(DateTime date) {
    if (widget.newStart == null || widget.newEnd == null) return false;
    final d = _d(date);
    return !d.isBefore(_d(widget.newStart!)) &&
        !d.isAfter(_d(widget.newEnd!));
  }

  bool _isRangeFree(DateTime from, DateTime to) {
    var d = _d(from);
    final end = _d(to);
    while (!d.isAfter(end)) {
      if (_isOccupiedOrPending(d) && !_isInOrigRange(d)) return false;
      d = d.add(const Duration(days: 1));
    }
    return true;
  }

  // ── TAP HANDLERS ──

  void _onDayTap(DateTime date) {
    final d = _d(date);
    final origS = _d(widget.origStart);
    final origE = _d(widget.origEnd);

    if (_isPast(d)) {
      widget.onError('Nelze vybrat datum v minulosti');
      return;
    }
    if (_isOccupiedOrPending(d) && !_isInOrigRange(d)) {
      widget.onError('Tento den je obsazený');
      return;
    }

    if (widget.mode == 'shorten') {
      _handleShortenTap(d, origS, origE);
    } else {
      _handleExtendTap(d, origS, origE);
    }
  }

  void _handleExtendTap(DateTime d, DateTime origS, DateTime origE) {
    final today = _d(DateTime.now());

    // Current new range (preserves the other side if already extended)
    final curStart = widget.newStart != null ? _d(widget.newStart!) : origS;
    final curEnd = widget.newEnd != null ? _d(widget.newEnd!) : origE;

    // Re-click on already-extended boundary → RESET to original dates
    final hasExtension = !curStart.isAtSameMomentAs(origS) ||
        !curEnd.isAtSameMomentAs(origE);
    if (hasExtension) {
      final isExtStart = d.isAtSameMomentAs(curStart) && curStart.isBefore(origS);
      final isExtEnd = d.isAtSameMomentAs(curEnd) && curEnd.isAfter(origE);
      if (isExtStart || isExtEnd) {
        widget.onDatesChanged(origS, origE);
        return;
      }
    }

    // Click BEFORE original start → extend start (keep current end)
    if (!widget.isActive && d.isBefore(origS)) {
      if (d.isBefore(today)) {
        widget.onError('Nelze vybrat datum v minulosti');
        return;
      }
      if (!_isRangeFree(d, origS.subtract(const Duration(days: 1)))) {
        widget.onError('Mezi vybraným dnem a začátkem jsou obsazené dny');
        return;
      }
      widget.onDatesChanged(d, curEnd);
      return;
    }

    // Click inside original reservation → block
    if (!d.isBefore(origS) && !d.isAfter(origE)) {
      if (widget.isActive) {
        widget.onError(
            'Klikněte na den po ${origE.day}.${origE.month}. pro prodloužení');
      } else {
        widget.onError(
            'Klikněte na den před ${origS.day}.${origS.month}. nebo po ${origE.day}.${origE.month}.');
      }
      return;
    }

    // Click AFTER original end → extend end (keep current start)
    if (d.isAfter(origE)) {
      if (!_isRangeFree(origE.add(const Duration(days: 1)), d)) {
        widget.onError(
            'Mezi koncem rezervace a vybraným dnem jsou obsazené dny');
        return;
      }
      widget.onDatesChanged(curStart, d);
    }
  }

  void _handleShortenTap(DateTime d, DateTime origS, DateTime origE) {
    final today = _d(DateTime.now());
    final inRes = !d.isBefore(origS) && !d.isAfter(origE);

    if (!inRes) {
      widget.onError('Pro zkrácení klikněte na den uvnitř vaší rezervace');
      return;
    }

    // Re-click on current shortened boundary → RESET to original dates
    final curStart = widget.newStart != null ? _d(widget.newStart!) : origS;
    final curEnd = widget.newEnd != null ? _d(widget.newEnd!) : origE;
    final hasShortened = !curStart.isAtSameMomentAs(origS) ||
        !curEnd.isAtSameMomentAs(origE);
    if (hasShortened) {
      if (widget.isActive && d.isAtSameMomentAs(curEnd)) {
        widget.onDatesChanged(origS, origE);
        return;
      }
      if (!widget.isActive) {
        final dir = widget.shortenDir;
        if (dir == 'start' && d.isAtSameMomentAs(curStart) && curStart.isAfter(origS)) {
          widget.onDatesChanged(origS, origE);
          return;
        }
        if (dir == 'end' && d.isAtSameMomentAs(curEnd) && curEnd.isBefore(origE)) {
          widget.onDatesChanged(origS, origE);
          return;
        }
      }
    }

    if (widget.isActive) {
      if (!d.isBefore(origE)) {
        widget.onError(
            'Klikněte na den před ${origE.day}.${origE.month}. pro zkrácení');
        return;
      }
      if (d.isBefore(today)) {
        widget.onError('Nelze zkrátit do minulosti');
        return;
      }
      widget.onDatesChanged(origS, d);
    } else {
      final totalDays = origE.difference(origS).inDays + 1;
      if (totalDays <= 1) {
        widget.onError('Rezervace je již na minimum (1 den)');
        return;
      }
      final dir = widget.shortenDir;
      if (dir == null) {
        widget.onError('Nejprve vyberte směr zkrácení');
        return;
      }
      if (dir == 'start') {
        widget.onDatesChanged(d.isAfter(origS) ? d : origS, origE);
      } else {
        widget.onDatesChanged(origS, d.isBefore(origE) ? d : origE);
      }
    }
  }

  // ── MONTH NAV ──

  void _prevMonth() => setState(() {
        _month--;
        if (_month < 1) { _month = 12; _year--; }
      });

  void _nextMonth() => setState(() {
        _month++;
        if (_month > 12) { _month = 1; _year++; }
      });

  // ── BUILD ──

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final firstWeekday = DateTime(_year, _month, 1).weekday;
    final offset = firstWeekday - 1;

    return Column(children: [
      // Month nav
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
              onPressed: _prevMonth,
              icon: const Icon(Icons.chevron_left, color: MotoGoColors.black)),
          Text('${_months[_month - 1]} $_year',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: MotoGoColors.black)),
          IconButton(
              onPressed: _nextMonth,
              icon:
                  const Icon(Icons.chevron_right, color: MotoGoColors.black)),
        ],
      ),
      const SizedBox(height: 4),
      // Day labels
      Row(
          children: _dayLabels
              .map((l) => Expanded(
                  child: Center(
                      child: Text(l,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: MotoGoColors.g400)))))
              .toList()),
      const SizedBox(height: 4),
      // Grid
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          ...List.generate(offset, (_) => const SizedBox.shrink()),
          ...List.generate(daysInMonth, (i) {
            final day = i + 1;
            final date = DateTime(_year, _month, day);
            final info = _getCellInfo(date);
            return _EditDayCell(
              day: day,
              cellType: info.type,
              radius: info.radius,
              onTap: () => _onDayTap(date),
            );
          }),
        ],
      ),
    ]);
  }

  // ── CELL TYPE RESOLUTION ──

  _CellInfo _getCellInfo(DateTime date) {
    final d = _d(date);
    final today = _d(DateTime.now());
    final origS = _d(widget.origStart);
    final origE = _d(widget.origEnd);
    final inOrig = _isInOrigRange(d);
    final inNew = _isInNewRange(d);
    final hasNewDates = widget.newStart != null && widget.newEnd != null;
    final newS = hasNewDates ? _d(widget.newStart!) : origS;
    final newE = hasNewDates ? _d(widget.newEnd!) : origE;

    // Past → dark
    if (d.isBefore(today)) {
      return const _CellInfo(_EditCellType.occupied);
    }

    // Occupied by others (not our reservation)
    if (_isOccupiedOrPending(d) && !inOrig) {
      return const _CellInfo(_EditCellType.occupied);
    }

    if (widget.mode == 'extend') {
      return _getExtendCellInfo(d, origS, origE, newS, newE, inOrig, inNew);
    } else {
      return _getShortenCellInfo(d, inOrig, inNew);
    }
  }

  _CellInfo _getExtendCellInfo(DateTime d, DateTime origS, DateTime origE,
      DateTime newS, DateTime newE, bool inOrig, bool inNew) {
    // Original reservation days → dark (occupied look)
    if (inOrig) return const _CellInfo(_EditCellType.occupied);

    // Newly added days (extended range, outside original)
    if (inNew && !inOrig) {
      // Determine shape: is this the start, end, or middle of extension?
      final isStart = d.isAtSameMomentAs(newS);
      final isEnd = d.isAtSameMomentAs(newE);
      final isSingleDay = isStart && isEnd;

      if (isSingleDay) {
        return const _CellInfo(_EditCellType.selected,
            radius: _CellRadius.round);
      } else if (isStart) {
        return const _CellInfo(_EditCellType.selected,
            radius: _CellRadius.leftHalf);
      } else if (isEnd) {
        return const _CellInfo(_EditCellType.selected,
            radius: _CellRadius.rightHalf);
      } else {
        return const _CellInfo(_EditCellType.selected,
            radius: _CellRadius.flat);
      }
    }

    // Free day
    return const _CellInfo(_EditCellType.free);
  }

  _CellInfo _getShortenCellInfo(DateTime d, bool inOrig, bool inNew) {
    if (inOrig && inNew) return const _CellInfo(_EditCellType.existing);
    if (inOrig && !inNew) return const _CellInfo(_EditCellType.shortened);
    if (inOrig && widget.newStart == null) {
      return const _CellInfo(_EditCellType.existing);
    }
    return const _CellInfo(_EditCellType.free);
  }
}

// ── DATA TYPES ──

enum _EditCellType {
  free, // light green — available
  occupied, // dark — occupied/pending/past/orig reservation (extend)
  existing, // light green — current reservation (shorten mode)
  selected, // dark — newly selected/extended days (extend mode)
  shortened, // red — days being removed (shorten mode)
}

enum _CellRadius { normal, round, leftHalf, rightHalf, flat }

class _CellInfo {
  final _EditCellType type;
  final _CellRadius radius;
  const _CellInfo(this.type, {this.radius = _CellRadius.normal});
}

// ── DAY CELL WIDGET ──

class _EditDayCell extends StatelessWidget {
  final int day;
  final _EditCellType cellType;
  final _CellRadius radius;
  final VoidCallback onTap;

  const _EditDayCell({
    required this.day,
    required this.cellType,
    this.radius = _CellRadius.normal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color textColor;
    FontWeight weight = FontWeight.w600;
    TextDecoration? decoration;

    switch (cellType) {
      case _EditCellType.occupied:
        bg = MotoGoColors.dark;
        textColor = Colors.white.withValues(alpha: 0.7);
        weight = FontWeight.w700;
      case _EditCellType.selected:
        bg = MotoGoColors.dark;
        textColor = Colors.white;
        weight = FontWeight.w900;
      case _EditCellType.existing:
        bg = MotoGoColors.green;
        textColor = Colors.white;
        weight = FontWeight.w800;
      case _EditCellType.shortened:
        bg = MotoGoColors.red;
        textColor = Colors.white;
        weight = FontWeight.w800;
        decoration = TextDecoration.lineThrough;
      case _EditCellType.free:
        bg = MotoGoColors.green;
        textColor = Colors.white;
        weight = FontWeight.w600;
    }

    // Compute border radius based on _CellRadius
    BorderRadius br;
    switch (radius) {
      case _CellRadius.leftHalf:
        br = const BorderRadius.only(
          topLeft: Radius.circular(50),
          bottomLeft: Radius.circular(50),
        );
      case _CellRadius.rightHalf:
        br = const BorderRadius.only(
          topRight: Radius.circular(50),
          bottomRight: Radius.circular(50),
        );
      case _CellRadius.flat:
        br = BorderRadius.zero;
      case _CellRadius.round:
        br = BorderRadius.circular(9);
      case _CellRadius.normal:
        br = BorderRadius.circular(9);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(color: bg, borderRadius: br),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 12,
              fontWeight: weight,
              color: textColor,
              decoration: decoration,
              decorationColor: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
