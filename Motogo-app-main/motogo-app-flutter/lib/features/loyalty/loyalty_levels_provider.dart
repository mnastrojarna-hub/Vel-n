import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';

/// Jeden věrnostní rank z tabulky `loyalty_levels` (level 1–20).
///
/// `level` = % slevy zároveň. `minBookingOrder` = od kolikáté kvalifikační
/// rezervace zákazník rank získá (1, 3, 5, … = 2·level − 1).
class LoyaltyLevel {
  final int level;
  final int percent;
  final int minBookingOrder;
  final String name;
  final String colorHex;

  const LoyaltyLevel({
    required this.level,
    required this.percent,
    required this.minBookingOrder,
    required this.name,
    required this.colorHex,
  });

  bool get isLegend => level >= 20;

  factory LoyaltyLevel.fromJson(Map<dynamic, dynamic> j) => LoyaltyLevel(
        level: (j['level'] as num?)?.toInt() ?? 1,
        percent: (j['discount_percent'] as num?)?.toInt() ??
            (j['level'] as num?)?.toInt() ??
            1,
        minBookingOrder: (j['min_booking_order'] as num?)?.toInt() ?? 1,
        name: j['name'] as String? ?? 'Rank',
        colorHex: j['color_hex'] as String? ?? '#9CA3AF',
      );
}

/// Statický fallback = přesná kopie seedu z `20260611_loyalty_ranks.sql`.
/// Použije se, když `loyalty_levels` ještě neexistuje nebo síť selže — stránka
/// ranků tak vykreslí vždy (fail-open, stejně jako zbytek loyalty featury).
const _fallbackLevels = <LoyaltyLevel>[
  LoyaltyLevel(level: 1, percent: 1, minBookingOrder: 1, name: 'Startér', colorHex: '#9CA3AF'),
  LoyaltyLevel(level: 2, percent: 2, minBookingOrder: 3, name: 'Jezdec', colorHex: '#86EFAC'),
  LoyaltyLevel(level: 3, percent: 3, minBookingOrder: 5, name: 'Motorkář', colorHex: '#4ADE80'),
  LoyaltyLevel(level: 4, percent: 4, minBookingOrder: 7, name: 'Stálý jezdec', colorHex: '#22C55E'),
  LoyaltyLevel(level: 5, percent: 5, minBookingOrder: 9, name: 'Věrný zákazník', colorHex: '#14B8A6'),
  LoyaltyLevel(level: 6, percent: 6, minBookingOrder: 11, name: 'Bronzový jezdec', colorHex: '#CD7F32'),
  LoyaltyLevel(level: 7, percent: 7, minBookingOrder: 13, name: 'Stříbrný jezdec', colorHex: '#C0C0C0'),
  LoyaltyLevel(level: 8, percent: 8, minBookingOrder: 15, name: 'Zlatý jezdec', colorHex: '#FFD700'),
  LoyaltyLevel(level: 9, percent: 9, minBookingOrder: 17, name: 'Platinový jezdec', colorHex: '#E5E4E2'),
  LoyaltyLevel(level: 10, percent: 10, minBookingOrder: 19, name: 'Diamantový jezdec', colorHex: '#7DD3FC'),
  LoyaltyLevel(level: 11, percent: 11, minBookingOrder: 21, name: 'Prémiový zákazník', colorHex: '#38BDF8'),
  LoyaltyLevel(level: 12, percent: 12, minBookingOrder: 23, name: 'Mistr silnic', colorHex: '#3B82F6'),
  LoyaltyLevel(level: 13, percent: 13, minBookingOrder: 25, name: 'Šampion', colorHex: '#6366F1'),
  LoyaltyLevel(level: 14, percent: 14, minBookingOrder: 27, name: 'Veterán MotoGo', colorHex: '#8B5CF6'),
  LoyaltyLevel(level: 15, percent: 15, minBookingOrder: 29, name: 'Elitní jezdec', colorHex: '#A855F7'),
  LoyaltyLevel(level: 16, percent: 16, minBookingOrder: 31, name: 'Ambasador', colorHex: '#D946EF'),
  LoyaltyLevel(level: 17, percent: 17, minBookingOrder: 33, name: 'VIP', colorHex: '#EF4444'),
  LoyaltyLevel(level: 18, percent: 18, minBookingOrder: 35, name: 'VIP Gold', colorHex: '#D4AF37'),
  LoyaltyLevel(level: 19, percent: 19, minBookingOrder: 37, name: 'VIP Platinum', colorHex: '#F1F5F9'),
  LoyaltyLevel(level: 20, percent: 20, minBookingOrder: 39, name: 'Legenda MotoGo', colorHex: '#FFD700'),
];

/// Všech 20 ranků seřazených podle levelu (1 → 20).
///
/// Načte z `loyalty_levels` (public read). Při jakékoli chybě / prázdné
/// odpovědi vrací statický fallback, takže UI nikdy nespadne.
final loyaltyLevelsProvider = FutureProvider<List<LoyaltyLevel>>((ref) async {
  try {
    final rows = await MotoGoSupabase.client
        .from('loyalty_levels')
        .select('level, discount_percent, min_booking_order, name, color_hex')
        .order('level');
    final list = (rows as List)
        .whereType<Map>()
        .map(LoyaltyLevel.fromJson)
        .toList();
    if (list.isEmpty) return _fallbackLevels;
    list.sort((a, b) => a.level.compareTo(b.level));
    return list;
  } catch (_) {
    return _fallbackLevels;
  }
});
