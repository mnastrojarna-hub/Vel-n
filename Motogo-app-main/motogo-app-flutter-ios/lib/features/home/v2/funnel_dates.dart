import '../../../core/i18n/i18n_provider.dart';

const _nb = ' ';

/// "30. 10." in the app language (`v2CalDateShort`), never split inside
/// (its spaces are U+00A0).
String funnelDate(AppTranslations tr, DateTime d) =>
    tr.trArgs('v2CalDateShort', {'d': d.day, 'm': d.month}).replaceAll(' ', _nb);

/// Compact preset range like the board (V22 Main): no weekday (the chip
/// label already says "víkend"), "16.–18. 10." / "16–18/10" within one
/// month, "30. 10. – 1. 11." across months — a line may break only after
/// the dash. Languages whose day is followed by a hyphen ("16-10") keep
/// both full dates (a hyphen beside the dash would read as one number).
String funnelRangeShort(AppTranslations tr, DateTime s, DateTime e) {
  final end = funnelDate(tr, e);
  if (s.year == e.year && s.month == e.month) {
    final f = tr.tr('v2CalDateShort');
    final di = f.indexOf('{d}'), mi = f.indexOf('{m}');
    if (di >= 0 && mi > di) {
      var day = f.substring(di, mi).replaceAll('{d}', '${s.day}').trimRight();
      final sep = day.isEmpty ? '' : day[day.length - 1];
      // cs / de "16." = ordinal dot (the format ends with one too): kept;
      // "16/10", "16.10" = a separator: dropped ("16–18/10").
      final ordinal = sep == '.' && f.trimRight().endsWith('.');
      if (sep != '-') {
        if (!ordinal && (sep == '/' || sep == '.')) day = day.substring(0, day.length - 1);
        return s.day == e.day ? end : '$day–$end';
      }
    }
  }
  return '${funnelDate(tr, s)}$_nb– $end';
}
