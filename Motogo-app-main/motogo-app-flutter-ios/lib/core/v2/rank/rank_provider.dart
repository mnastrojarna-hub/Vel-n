import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/loyalty/loyalty_provider.dart';
import 'rank_tokens.dart';

/// Rank tokens of the signed-in customer, from the EXISTING
/// `loyaltyStatusProvider` (level + `color_hex`; the v2.2 ramp is the
/// fallback / mapping, see `rank_palette.dart`). No status (guest, loyalty
/// RPC missing or failed) → level 0 = pure brand. Override in tests.
final rankTokensProvider = Provider<RankTokens>((ref) {
  final st = ref.watch(loyaltyStatusProvider).valueOrNull;
  if (st == null) return RankTokens.brand;
  return RankTokens.forLevel(st.level, st.colorHex);
});

/// Progress inside the current level in % (4–100) for rings / arcs; null
/// when the loyalty status is unknown. Override in tests.
final rankArcPctProvider = Provider<double?>((ref) {
  final st = ref.watch(loyaltyStatusProvider).valueOrNull;
  if (st == null) return null;
  return rankArcPct(st.level, st.qualifyingCount, st.bookingsToNext);
});

/// Tokens for any level (ladder rows, previews).
RankTokens rankTokensForLevel(int level, [String? dbHex]) =>
    RankTokens.forLevel(level, dbHex);

/// Arc % for a level: from `bookingsToNext` when the server sends it (2
/// points per level), else from the effective points.
double rankArcPct(int level, int? points, int? toNext) {
  if (level >= 20) return 100;
  if (level <= 0) return 0;
  if (toNext != null) {
    final done = 2 - toNext.clamp(0, 2);
    return (done / 2 * 100).clamp(4, 100).toDouble();
  }
  return RankTokens.forLevel(level).arcPctFor(points);
}
