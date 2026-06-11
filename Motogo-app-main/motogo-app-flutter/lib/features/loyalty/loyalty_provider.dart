import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import '../auth/auth_provider.dart';

/// Věrnostní rank zákazníka — výsledek RPC `get_loyalty_status`.
///
/// DŮLEŽITÉ: Věrnostní sleva platí POUZE pro rezervace vytvořené
/// v mobilní aplikaci (`bookings.booking_source = 'app'`). Web ani
/// admin rezervace rank nezvyšují a slevu nedostávají.
class LoyaltyStatus {
  final int level; // 1–20 (level = procento slevy)
  final int percent; // sleva v %
  final String rankName; // název ranku z `loyalty_levels`
  final String colorHex; // '#RRGGBB' — barva ringu MG loga
  final int qualifyingCount; // počet dokončených app rezervací
  final String? nextRankName;
  final int? nextPercent;
  final String? nextColorHex;
  final int? bookingsToNext; // kolik dokončených rezervací chybí do dalšího ranku
  final int maxLevel;

  const LoyaltyStatus({
    required this.level,
    required this.percent,
    required this.rankName,
    required this.colorHex,
    required this.qualifyingCount,
    this.nextRankName,
    this.nextPercent,
    this.nextColorHex,
    this.bookingsToNext,
    this.maxLevel = 20,
  });

  bool get isMax => level >= maxLevel;

  /// Level 20 „Legenda MotoGo" — místo plné barvy zlato-oranžový gradient.
  bool get isLegend => level >= 20;

  Color get color => colorFromHex(colorHex);

  factory LoyaltyStatus.fromJson(Map<dynamic, dynamic> json) {
    return LoyaltyStatus(
      level: (json['level'] as num?)?.toInt() ?? 1,
      percent: (json['percent'] as num?)?.toInt() ?? 1,
      rankName: json['rank_name'] as String? ?? 'Startér',
      colorHex: json['color_hex'] as String? ?? '#9CA3AF',
      qualifyingCount: (json['qualifying_count'] as num?)?.toInt() ?? 0,
      nextRankName: json['next_rank_name'] as String?,
      nextPercent: (json['next_percent'] as num?)?.toInt(),
      nextColorHex: json['next_color_hex'] as String?,
      bookingsToNext: (json['bookings_to_next'] as num?)?.toInt(),
      maxLevel: (json['max_level'] as num?)?.toInt() ?? 20,
    );
  }
}

/// '#RRGGBB' → [Color]; při neplatném vstupu vrací MotoGo zelenou.
Color colorFromHex(String hex, {Color fallback = const Color(0xFF74FB71)}) {
  final h = hex.replaceAll('#', '').trim();
  if (h.length != 6) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

/// Gradient Legendy MotoGo (level 20) — zlato → oranžová.
const legendGradientColors = [Color(0xFFFFD700), Color(0xFFFF6B00)];

/// Aktuální věrnostní status přihlášeného zákazníka.
///
/// Fail-open: pokud RPC `get_loyalty_status` v DB ještě neexistuje
/// (pořadí nasazení app vs. SQL) nebo selže, vrací null a celá
/// loyalty feature se v UI tiše skryje — appka funguje jako dřív.
final loyaltyStatusProvider = FutureProvider<LoyaltyStatus?>((ref) async {
  // Obnovuje se spolu s profilem (login / logout / refresh profilu).
  ref.watch(profileProvider);
  if (MotoGoSupabase.currentUser == null) return null;
  try {
    final res = await MotoGoSupabase.client.rpc('get_loyalty_status');
    if (res is! Map || res['level'] == null) return null;
    return LoyaltyStatus.fromJson(res);
  } catch (_) {
    return null;
  }
});
