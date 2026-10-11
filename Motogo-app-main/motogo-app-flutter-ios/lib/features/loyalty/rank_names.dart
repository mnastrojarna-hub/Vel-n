import '../../core/i18n/i18n_provider.dart';

/// Výchozí české názvy ranků (seed `20260611_loyalty_ranks.sql`). Názvy chodí
/// z DB česky (`loyalty_levels.name`, RPC `rank_name`) — appka je v cizím
/// jazyce nahradí přeloženým klíčem `loyaltyRank<level>`. Když majitel název
/// ve Velíně změnil (neodpovídá seedu), zobrazí se tak, jak je.
const loyaltyDefaultRankNamesCs = <int, String>{
  1: 'Startér', 2: 'Jezdec', 3: 'Motorkář', 4: 'Stálý jezdec',
  5: 'Věrný zákazník', 6: 'Bronzový jezdec', 7: 'Stříbrný jezdec',
  8: 'Zlatý jezdec', 9: 'Platinový jezdec', 10: 'Diamantový jezdec',
  11: 'Prémiový zákazník', 12: 'Mistr silnic', 13: 'Šampion',
  14: 'Veterán MotoGo', 15: 'Elitní jezdec', 16: 'Ambasador', 17: 'VIP',
  18: 'VIP Gold', 19: 'VIP Platinum', 20: 'Legenda MotoGo',
};

/// Název ranku [level] v jazyce appky ([name] = český název z DB).
String localizedRankName(AppTranslations tr, int? level, String name) {
  if (tr.lang == 'cs' || level == null) return name;
  final seed = loyaltyDefaultRankNamesCs[level];
  if (seed == null || (name.trim().isNotEmpty && name.trim() != seed)) return name;
  final key = 'loyaltyRank$level';
  final v = tr.tr(key);
  return v == key ? name : v;
}
