import '../../../core/i18n/i18n_provider.dart';

/// Plural helper for the v2 Trasy strings: keys `<base>One/Few/Many` with
/// `{n}` (Few only differs in cs / pl / uk). Same rule as `daysWord`.
String rtPlural(AppTranslations tr, String base, int n) {
  final a = n.abs();
  final lang = tr.lang;
  String suffix;
  if (lang == 'cs') {
    suffix = a == 1 ? 'One' : (a >= 2 && a <= 4 ? 'Few' : 'Many');
  } else if (lang == 'pl' || lang == 'uk') {
    final m10 = a % 10, m100 = a % 100;
    if (a == 1 || (lang == 'uk' && m10 == 1 && m100 != 11)) {
      suffix = 'One';
    } else {
      suffix = (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) ? 'Few' : 'Many';
    }
  } else {
    suffix = a == 1 ? 'One' : 'Many';
  }
  return tr.trArgs('$base$suffix', {'n': rtThousands(n)});
}

/// "12 345" — thousands separated by a no-break space (as the old headers).
String rtThousands(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// Ride time as the old route cards print it: "55 min", "2 h", "2 h 54 min".
String rtDur(int min) {
  if (min < 60) return '$min min';
  final h = min ~/ 60;
  final m = min % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Difficulty label (same keys as the old detail).
String rtDifficulty(AppTranslations tr, String d) => switch (d) {
      'easy' => tr.tr('routeDiffEasy'),
      'medium' => tr.tr('routeDiffMedium'),
      'hard' => tr.tr('routeDiffHard'),
      _ => d,
    };
