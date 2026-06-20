import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import '../auth/auth_provider.dart';
import 'loyalty_provider.dart' show colorFromHex, loyaltyStatusProvider;

/// Jeden řádek měsíčního žebříčku jezdců — výsledek RPC
/// `get_loyalty_leaderboard`. Jen zákazníci, kteří mají nastavenou přezdívku
/// a NEvypnuli si zobrazování (opt-out). Soukromí: skutečné jméno se nikdy
/// neposílá — pouze zvolený alias.
class LeaderboardEntry {
  final int position;
  final String nickname;
  final int days; // rezervované dny v aktuálním měsíci
  final int level; // aktuální rank jezdce
  final int percent;
  final String colorHex;
  final bool isMe;

  const LeaderboardEntry({
    required this.position,
    required this.nickname,
    required this.days,
    required this.level,
    required this.percent,
    required this.colorHex,
    required this.isMe,
  });

  bool get isLegend => level >= 20;
  Color get color => colorFromHex(colorHex);

  factory LeaderboardEntry.fromJson(Map<dynamic, dynamic> j) => LeaderboardEntry(
        position: (j['rank_pos'] as num?)?.toInt() ?? 0,
        nickname: j['nickname'] as String? ?? 'Pilot',
        days: (j['days'] as num?)?.toInt() ?? 0,
        level: (j['level'] as num?)?.toInt() ?? 1,
        percent: (j['percent'] as num?)?.toInt() ?? 1,
        colorHex: j['color_hex'] as String? ?? '#9CA3AF',
        isMe: j['is_me'] as bool? ?? false,
      );
}

/// Vítěz minulého měsíce (poslední udělená hlavní výhra) — z `last_winner`
/// v odpovědi RPC. Slouží jako motivační banner „minulý měsíc vyhrál …".
class LeaderboardWinner {
  final String nickname;
  final int days;
  final String month; // 'YYYY-MM'

  const LeaderboardWinner({
    required this.nickname,
    required this.days,
    required this.month,
  });

  static LeaderboardWinner? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final nick = raw['nickname'] as String?;
    if (nick == null || nick.trim().isEmpty) return null;
    return LeaderboardWinner(
      nickname: nick,
      days: (raw['days'] as num?)?.toInt() ?? 0,
      month: raw['month'] as String? ?? '',
    );
  }
}

/// Celá odpověď žebříčku.
class LeaderboardData {
  final String month; // aktuální měsíc 'YYYY-MM'
  final List<LeaderboardEntry> entries;
  final LeaderboardWinner? lastWinner;

  const LeaderboardData({
    required this.month,
    required this.entries,
    this.lastWinner,
  });

  bool get isEmpty => entries.isEmpty;
}

/// Měsíční žebříček jezdců.
///
/// Fail-open: když RPC `get_loyalty_leaderboard` ještě neexistuje (SQL nebyl
/// nasazen) nebo selže, vrací null → celá sekce žebříčku se v UI skryje.
final loyaltyLeaderboardProvider =
    FutureProvider.autoDispose<LeaderboardData?>((ref) async {
  ref.watch(profileProvider);
  if (MotoGoSupabase.currentUser == null) return null;
  try {
    final res = await MotoGoSupabase.client.rpc('get_loyalty_leaderboard');
    if (res is! Map) return null;
    final list = (res['entries'] as List? ?? const [])
        .whereType<Map>()
        .map(LeaderboardEntry.fromJson)
        .toList();
    return LeaderboardData(
      month: res['month'] as String? ?? '',
      entries: list,
      lastWinner: LeaderboardWinner.fromJson(res['last_winner']),
    );
  } catch (_) {
    return null;
  }
});

/// Zapne/vypne zobrazování zákazníka ve veřejném žebříčku.
/// Vypnutím ztrácí nárok na hlavní měsíční výhru (postup o 2 ranky).
Future<void> setLeaderboardOptIn(WidgetRef ref, bool optIn) async {
  try {
    await MotoGoSupabase.client
        .rpc('set_loyalty_leaderboard_optin', params: {'p_opt_in': optIn});
  } catch (_) {
    // Fail-open: když RPC chybí, jen tiše ignoruj (UI se vrátí ze stavu).
  }
  ref.invalidate(loyaltyStatusProvider);
  ref.invalidate(loyaltyLeaderboardProvider);
}

/// Uloží přezdívku i na server (pro žebříček). Fire-and-forget, fail-open —
/// lokální přezdívka (SharedPreferences) je zdrojem pravdy pro UI hlavičky.
Future<void> syncLeaderboardNickname(String? nickname) async {
  if (MotoGoSupabase.currentUser == null) return;
  try {
    await MotoGoSupabase.client.rpc('set_loyalty_nickname',
        params: {'p_nickname': nickname ?? ''});
  } catch (_) {
    // RPC ještě neexistuje / offline — ignoruj.
  }
}
