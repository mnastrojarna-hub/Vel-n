import 'package:flutter/foundation.dart' show immutable;

import '../../i18n/i18n_provider.dart';

/// What a calendar day IS (DESIGN_V22 §3.3). Decided by the logic owner
/// (catalog / detail / edit / booking / calculator) — `TripCalendar` only
/// draws it.
enum TripDayKind { free, freeWeekend, past, busy, yourOther, pending, outOfLimit, closed, loading }

/// Where the day sits in the selected range.
enum TripSel { none, start, mid, end, single }

/// Reservation edit marks (V22 §3.4).
enum TripEditMark { none, added, removed }

/// Light (default; light sheets / white cards) or dark skin (dark sheets).
enum TripSkin { light, dark }

@immutable
class TripDayState {
  final DateTime date;
  final TripDayKind kind;
  final TripSel selected;
  final bool today;

  /// Pre-formatted day price (hidden for non-free days), e.g. "3 514".
  final String? price;
  final TripEditMark editMark;

  /// Start chosen, end not yet → ring + ping on the start capsule.
  final bool pendingStart;

  /// Whether a tap means something (owner decides; drives semantics).
  final bool enabled;

  const TripDayState({
    required this.date,
    this.kind = TripDayKind.free,
    this.selected = TripSel.none,
    this.today = false,
    this.price,
    this.editMark = TripEditMark.none,
    this.pendingStart = false,
    this.enabled = true,
  });

  bool get isSelected => selected != TripSel.none;

  /// Price shows only on free days (and inside the band).
  bool get showsPrice =>
      price != null &&
      (isSelected || kind == TripDayKind.free || kind == TripDayKind.freeWeekend);

  TripDayState copyWith({
    TripDayKind? kind,
    TripSel? selected,
    bool? today,
    String? price,
    TripEditMark? editMark,
    bool? pendingStart,
    bool? enabled,
  }) =>
      TripDayState(
        date: date,
        kind: kind ?? this.kind,
        selected: selected ?? this.selected,
        today: today ?? this.today,
        price: price ?? this.price,
        editMark: editMark ?? this.editMark,
        pendingStart: pendingStart ?? this.pendingStart,
        enabled: enabled ?? this.enabled,
      );
}

/// Calendar day (date only) helpers.
DateTime tripDay(DateTime d) => DateTime(d.year, d.month, d.day);
bool tripSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Selection of [date] within [start]..[end] (end null = start only).
TripSel tripSelOf(DateTime date, DateTime? start, DateTime? end) {
  if (start == null) return TripSel.none;
  final d = tripDay(date), s = tripDay(start);
  if (end == null) return tripSameDay(d, s) ? TripSel.single : TripSel.none;
  final e = tripDay(end);
  if (d.isBefore(s) || d.isAfter(e)) return TripSel.none;
  if (tripSameDay(s, e)) return TripSel.single;
  if (tripSameDay(d, s)) return TripSel.start;
  if (tripSameDay(d, e)) return TripSel.end;
  return TripSel.mid;
}

/// "pá 23. 10." in the app language.
String tripShortDate(AppTranslations tr, DateTime d) =>
    '${tr.tr('v2CalWdAbbr${d.weekday}')} ${tr.trArgs('v2CalDateShort', {'d': d.day, 'm': d.month})}';

/// "23. 10. 2026" in the app language.
String tripDate(AppTranslations tr, DateTime d) =>
    tr.trArgs('v2CalDate', {'d': d.day, 'm': d.month, 'y': d.year});

/// "Říjen 2026".
String tripMonthTitle(AppTranslations tr, DateTime month) =>
    '${tr.tr('v2CalMonth${month.month}')} ${month.year}';

/// Screen-reader label of a day: "pátek 23. 10. 2026, 3 514 Kč, vybráno, vyzvednutí".
String tripDayA11y(AppTranslations tr, TripDayState s, {String? currency}) {
  final parts = <String>['${tr.tr('v2CalWdFull${s.date.weekday}')} ${tripDate(tr, s.date)}'];
  if (s.today) parts.add(tr.tr('v2CalToday'));
  if (s.showsPrice) parts.add(currency == null ? s.price! : '${s.price} $currency');
  switch (s.kind) {
    case TripDayKind.busy:
    case TripDayKind.closed:
      parts.add(tr.tr('v2CalLegBusy'));
    case TripDayKind.pending:
      parts.add(tr.tr('v2CalLegPending'));
    case TripDayKind.yourOther:
      parts.add(tr.tr('v2CalLegOther'));
    case TripDayKind.past:
    case TripDayKind.outOfLimit:
    case TripDayKind.loading:
      parts.add(tr.tr('v2CalUnavailable'));
    case TripDayKind.free:
    case TripDayKind.freeWeekend:
      break;
  }
  if (s.isSelected) parts.add(tr.tr('v2CalSelected'));
  if (s.selected == TripSel.start || s.selected == TripSel.single) parts.add(tr.tr('v2CalPickup'));
  if (s.selected == TripSel.end || (s.selected == TripSel.single && !s.pendingStart)) {
    parts.add(tr.tr('v2CalReturn'));
  }
  if (s.editMark == TripEditMark.added) parts.add(tr.tr('v2CalLegAdded'));
  if (s.editMark == TripEditMark.removed) parts.add(tr.tr('v2CalLegRemoved'));
  return parts.join(', ');
}
