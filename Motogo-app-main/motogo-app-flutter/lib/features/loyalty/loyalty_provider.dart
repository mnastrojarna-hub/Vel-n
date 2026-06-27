import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import '../auth/auth_provider.dart';

/// Věrnostní rank zákazníka — výsledek RPC `get_loyalty_status`.
///
/// Pravidla: kvalifikační BODY sbírá každá dokončená rezervace z aplikace
/// I z webu (1 bod; rezervace delší než 7 dní = 4 body = postup o 2 ranky),
/// každé 2 body = nový rank. DŮLEŽITÉ: sleva se uplatňuje a zobrazuje
/// POUZE v mobilní aplikaci (`bookings.booking_source = 'app'`) — web ani
/// admin rezervace slevu nikdy nedostanou.
class LoyaltyStatus {
  final int level; // 1–20 (level = procento slevy)
  final int percent; // sleva v %
  final String rankName; // název ranku z `loyalty_levels`
  final String colorHex; // '#RRGGBB' — barva ringu MG loga
  final int qualifyingCount; // kvalifikační BODY (app i web; 7+ dní = 4 body)
  final String? nextRankName;
  final int? nextPercent;
  final String? nextColorHex;
  final int? bookingsToNext; // kolik dokončených rezervací chybí do dalšího ranku
  final int maxLevel;

  /// Zobrazovat zákazníka ve veřejném měsíčním žebříčku (opt-out v nastavení).
  /// Default true. Při false jezdec ztrácí nárok na hlavní měsíční výhru.
  final bool leaderboardOptIn;

  /// Serverová přezdívka pro žebříček (alias, ne skutečné jméno). NULL =
  /// zákazník si přezdívku ještě nenastavil → v žebříčku se neukáže.
  final String? serverNickname;

  /// Bonusové kvalifikační body z měsíční výhry (+4 = postup o 2 ranky).
  final int bonusPoints;

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
    this.leaderboardOptIn = true,
    this.serverNickname,
    this.bonusPoints = 0,
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
      leaderboardOptIn: json['leaderboard_opt_in'] as bool? ?? true,
      serverNickname: json['nickname'] as String?,
      bonusPoints: (json['bonus_points'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Motorka pro level-up oslavu — z RPC `get_loyalty_celebration_motos`.
/// Vybírá se z historie výpůjček zákazníka (nejlepší médium: video → foto).
class CelebrationMoto {
  final String? brand;
  final String? model;
  final String? color;
  final String? imageUrl;
  final String? videoUrl;

  /// Transparentní výřez motorky bez pozadí (iOS „samolepka") — hlavní motiv
  /// oslavy. Když existuje, „nalepí" se na cinematic scénu (přednost před
  /// fotkou/videem). NULL → fallback na video/foto.
  final String? cutoutUrl;

  const CelebrationMoto({
    this.brand,
    this.model,
    this.color,
    this.imageUrl,
    this.videoUrl,
    this.cutoutUrl,
  });

  /// „Honda Africa Twin" — značka + model, prázdné kusy se vynechají.
  String get title => [brand, model]
      .where((e) => e != null && e.trim().isNotEmpty)
      .join(' ')
      .trim();

  bool get hasCutout => cutoutUrl != null && cutoutUrl!.trim().isNotEmpty;
  bool get hasVideo => videoUrl != null && videoUrl!.trim().isNotEmpty;
  bool get hasImage => imageUrl != null && imageUrl!.trim().isNotEmpty;
  bool get hasMedia => hasCutout || hasVideo || hasImage;

  factory CelebrationMoto.fromJson(Map<dynamic, dynamic> j) => CelebrationMoto(
        brand: j['brand'] as String?,
        model: j['model'] as String?,
        color: j['color'] as String?,
        imageUrl: j['image_url'] as String?,
        videoUrl: j['video_url'] as String?,
        cutoutUrl: j['cutout_url'] as String?,
      );
}

/// Fail-open: stáhne personalizované motorky pro level-up oslavu. Když RPC
/// neexistuje / selže / vrátí prázdno, vrátí [] a animace běží bez hero média.
Future<List<CelebrationMoto>> fetchLoyaltyCelebrationMotos() async {
  if (MotoGoSupabase.currentUser == null) return const [];
  try {
    final res =
        await MotoGoSupabase.client.rpc('get_loyalty_celebration_motos');
    if (res is! Map) return const [];
    final list = res['motos'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => CelebrationMoto.fromJson(m))
        .where((m) => m.hasMedia)
        .toList();
  } catch (_) {
    return const [];
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
