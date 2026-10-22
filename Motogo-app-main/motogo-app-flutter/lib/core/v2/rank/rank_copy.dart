import '../../i18n/i18n_provider.dart';
import '../../../features/loyalty/rank_names.dart';
import 'rank_tokens.dart';

/// Rank copy for the v2 look (tier names, mottos, step labels, a11y). The
/// strings live in `translations_ext_50_v2_core_c.dart`; rank NAMES keep
/// using the existing `localizedRankName` (DB name, translated seed names).
abstract final class RankCopy {
  /// Rank name in the app language ([dbName] = Czech name from the DB/RPC).
  static String name(AppTranslations tr, int level, [String? dbName]) {
    if (level < 1) return tr.tr('v2RankGuest');
    final seed = loyaltyDefaultRankNamesCs[level] ?? '';
    final n = (dbName == null || dbName.trim().isEmpty) ? seed : dbName;
    return localizedRankName(tr, level, n);
  }

  static String tierName(AppTranslations tr, RankTier tier) =>
      tr.tr('v2RankTier${tier.index}');

  /// One motto per level (Home header line under the greeting).
  static String motto(AppTranslations tr, int level) =>
      level >= 1 && level <= 20 ? tr.tr('v2RankMotto$level') : '';

  /// "Silnice 3/5" (single-level tiers: just the tier name).
  static String stepLabel(AppTranslations tr, RankTokens r) =>
      r.steps > 1 ? '${tierName(tr, r.tier)} ${r.step}/${r.steps}' : tierName(tr, r.tier);

  /// "Silnice, stupeň 3 z 5" — for screen readers and the ladder.
  static String stepLine(AppTranslations tr, RankTokens r) {
    final t = tierName(tr, r.tier);
    if (r.steps <= 1) return '$t, ${tr.tr('v2RankSingle')}';
    return '$t, ${tr.trArgs('v2RankStepOf', {'step': r.step, 'steps': r.steps})}';
  }

  /// Screen-reader name of the logo ring / rank chip.
  static String aria(AppTranslations tr, int level, String name, [int? pct]) => tr.trArgs(
      'v2RankAria', {'name': name, 'level': level, 'pct': pct ?? level});

  /// Motto + tier step for screen readers.
  static String mottoAria(AppTranslations tr, RankTokens r, String name) =>
      '$name · ${stepLine(tr, r)}. ${motto(tr, r.level)}';

  /// "Motorkář · −3 %".
  static String chip(AppTranslations tr, String name, int pct) =>
      tr.trArgs('v2RankChip', {'name': name, 'pct': pct});

  /// "Level 3 z 20 · sleva 3 % na každou jízdu v appce".
  static String levelLine(AppTranslations tr, int level, [int? pct]) =>
      tr.trArgs('v2RankLevelLine', {'level': level, 'pct': pct ?? level});

  /// "Ještě 1 bod → Stálý jezdec (4 %)" or "Máš nejvyšší rank".
  static String nextLine(AppTranslations tr, {required bool isMax, int? toNext, String? nextName, int? nextPct}) {
    if (isMax || toNext == null || nextName == null) return tr.tr('v2RankMax');
    return tr.trArgs('v2RankNextLine', {
      'n': toNext,
      'points': points(tr, toNext),
      'name': nextName,
      'pct': nextPct ?? '',
    });
  }

  /// bod / body / bodů (3 forms in cs, pl, uk; 2 elsewhere).
  static String points(AppTranslations tr, int n) {
    final a = n.abs();
    final lang = tr.lang;
    if (lang == 'cs') {
      return tr.tr(a == 1 ? 'v2RankPointOne' : (a >= 2 && a <= 4 ? 'v2RankPointFew' : 'v2RankPointMany'));
    }
    if (lang == 'pl' || lang == 'uk') {
      final m10 = a % 10, m100 = a % 100;
      if (a == 1 || (lang == 'uk' && m10 == 1 && m100 != 11)) return tr.tr('v2RankPointOne');
      final few = m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14);
      return tr.tr(few ? 'v2RankPointFew' : 'v2RankPointMany');
    }
    return tr.tr(a == 1 ? 'v2RankPointOne' : 'v2RankPointMany');
  }

  /// Passenger gear line (free from level 3).
  static String gearLine(AppTranslations tr, int level) =>
      tr.tr(level >= 3 ? 'v2RankGearOn' : 'v2RankGearFrom');
}
