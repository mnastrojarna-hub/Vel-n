import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pending_booking_fab_provider.dart';
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

  /// Všechna videa této motorky (montáž po sobě). Pořadí = pořadí přehrávání.
  final List<String> videos;

  /// Transparentní výřez motorky bez pozadí (iOS „samolepka") — rezervováno.
  final String? cutoutUrl;

  const CelebrationMoto({
    this.brand,
    this.model,
    this.color,
    this.imageUrl,
    this.videoUrl,
    this.videos = const [],
    this.cutoutUrl,
  });

  /// „Honda Africa Twin" — značka + model, prázdné kusy se vynechají.
  String get title => [brand, model]
      .where((e) => e != null && e.trim().isNotEmpty)
      .join(' ')
      .trim();

  bool get hasCutout => cutoutUrl != null && cutoutUrl!.trim().isNotEmpty;
  bool get hasVideo => videos.isNotEmpty ||
      (videoUrl != null && videoUrl!.trim().isNotEmpty);
  bool get hasImage => imageUrl != null && imageUrl!.trim().isNotEmpty;
  bool get hasMedia => hasCutout || hasVideo || hasImage;

  factory CelebrationMoto.fromJson(Map<dynamic, dynamic> j) {
    final raw = j['videos'];
    final vids = <String>[];
    if (raw is List) {
      for (final v in raw) {
        if (v is String && v.trim().isNotEmpty) vids.add(v);
      }
    }
    final single = j['video_url'] as String?;
    if (vids.isEmpty && single != null && single.trim().isNotEmpty) {
      vids.add(single);
    }
    return CelebrationMoto(
      brand: j['brand'] as String?,
      model: j['model'] as String?,
      color: j['color'] as String?,
      imageUrl: j['image_url'] as String?,
      videoUrl: vids.isNotEmpty ? vids.first : single,
      videos: vids,
      cutoutUrl: j['cutout_url'] as String?,
    );
  }
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

/// Poslední ÚSPĚŠNĚ načtený status daného uživatele (per-uid, aby se rank
/// nikdy nepřelil mezi účty). Slouží jako záchytná síť při selhání RPC.
String? _lastStatusUid;
LoyaltyStatus? _lastGoodStatus;

/// Zapomene nacachovaný status — volat při odhlášení / přepnutí účtu.
void clearLoyaltyStatusCache() {
  _lastStatusUid = null;
  _lastGoodStatus = null;
}

/// Aktuální věrnostní status přihlášeného zákazníka.
///
/// Fail-open vůči NEEXISTUJÍCÍMU RPC: když `get_loyalty_status` v DB ještě
/// není (pořadí nasazení app vs. SQL), vrátí null a celá loyalty feature se
/// v UI tiše skryje — appka funguje jako dřív.
///
/// Fail-SAFE vůči SÍTI: při selhání dotazu vrací POSLEDNÍ ÚSPĚŠNÝ status
/// téhož uživatele, ne null. Bez toho by jeden výpadek na LTE shodil rank na
/// 0 → placená výbava by v půlce rezervace přestala být zdarma a zákazníkovi
/// by před očima vyskočila vyšší cena. Kontrola ranku se navíc od 4.0.0 dělá
/// při každém dotyku, takže by takový výpadek byl kdykoli k mání.
final loyaltyStatusProvider = FutureProvider<LoyaltyStatus?>((ref) async {
  // Obnovuje se spolu s profilem (login / logout / refresh profilu).
  ref.watch(profileProvider);
  final uid = MotoGoSupabase.currentUser?.id;
  if (uid == null) {
    clearLoyaltyStatusCache();
    return null;
  }
  // Jiný účet → zahoď cache, ať se rank nepřelije mezi uživateli.
  if (_lastStatusUid != uid) clearLoyaltyStatusCache();
  // Cache se vrací VÝHRADNĚ vlastníkovi. Riverpod staré tělo providera při
  // invalidaci neruší, takže dotaz spuštěný ještě pod uživatelem A může
  // dobíhat, když je už přihlášený B — bez téhle kontroly by A-ův rank
  // (a jeho sleva i výbava zdarma) skončil u B.
  LoyaltyStatus? cached() => _lastStatusUid == uid ? _lastGoodStatus : null;
  try {
    final res = await MotoGoSupabase.client.rpc('get_loyalty_status');
    // Během dotazu se mohl přepnout účet → tohle pokračování už nic neplatí.
    if (MotoGoSupabase.currentUser?.id != uid) return null;
    if (res is! Map || res['level'] == null) {
      // Validní odpověď „loyalty není k dispozici" — cache NEplníme.
      return cached();
    }
    final status = LoyaltyStatus.fromJson(res);
    _lastStatusUid = uid;
    _lastGoodStatus = status;
    return status;
  } catch (_) {
    // Síť/RPC selhalo → drž posledně známý rank TOHOTO uživatele
    // (null, když žádný nemáme).
    if (MotoGoSupabase.currentUser?.id != uid) return null;
    return cached();
  }
});

// ═══════════════════════════════════════════════════════════════════
// KONTROLA POVÝŠENÍ NA REÁLNOU INTERAKCI
// Rank se mění SERVER-SIDE (obsluha dokončí rezervaci, admin přidá bonusové
// body, výhra v měsíčním žebříčku) — tedy typicky ve chvíli, kdy appka nic
// nedělá. Aby zákazník oslavu VŽDY viděl, kontroluje se rank i při běžném
// používání appky (každý dotyk), ne jen při návratu z pozadí.
// ═══════════════════════════════════════════════════════════════════

/// Jak často nejvíc smí dotyk vyvolat dotaz na rank (ochrana RPC).
const loyaltyPollInterval = Duration(seconds: 45);

DateTime? _lastLoyaltyPoll;

/// `true` po dobu běžící level-up oslavy — během ní se rank NEobnovuje
/// (jinak by `ref.listen` mohl rozjet druhou oslavu přes tu první).
bool loyaltyPollPaused = false;

/// Levná kontrola ranku vyvolaná interakcí uživatele.
///
/// Bezpečná při odhlášení (RPC se vůbec nezavolá), během oslavy (pauza)
/// i při „bušení" do displeje (throttle [loyaltyPollInterval]).
/// [force] obejde throttle — pro návrat z pozadí a periodickou pojistku.
void maybeRefreshLoyalty(WidgetRef ref, {bool force = false}) {
  if (loyaltyPollPaused) return;
  if (MotoGoSupabase.currentUser == null) return;
  // POKLADNA JE ZAMČENÁ: na platební obrazovce rank NEobnovujeme. Cena
  // rezervace je tam už spočítaná a rozpracovaná do payloadu (`total_price`,
  // `extras_price`, `booking_extras`) — kdyby se rank změnil uprostřed, mohla
  // by se účtovaná částka rozejít s tou uloženou. Povýšení se dožene hned po
  // odchodu z platby (oslava se během platby beztak neukazuje).
  if (ref.read(paymentScreenActiveProvider)) return;
  final now = DateTime.now();
  if (!force &&
      _lastLoyaltyPoll != null &&
      now.difference(_lastLoyaltyPoll!) < loyaltyPollInterval) {
    return;
  }
  _lastLoyaltyPoll = now;
  ref.invalidate(loyaltyStatusProvider);
}

/// Vynuluje throttle — návrat z pozadí, přihlášení, dokončená platba.
/// Bez toho by nově přihlášený uživatel čekal až 45 s na první kontrolu.
void resetLoyaltyPollClock() => _lastLoyaltyPoll = null;
