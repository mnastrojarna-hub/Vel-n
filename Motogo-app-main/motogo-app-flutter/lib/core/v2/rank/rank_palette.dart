// Rank colour resolution WITHOUT SQL (PLAN §1.5): the ramp SQL of DESIGN_V22
// §1.7 is not live yet (it waits for both app trees), so the app maps the
// colours still stored in `loyalty_levels.color_hex` to the new ramp itself.
// `loyalty_levels_provider.dart` is NOT changed — the old UI keeps the old
// colours.

/// The v2.2 ramp (DESIGN_V22 §1.1), index = level − 1.
const List<String> kRankRampHex = [
  '#A3B8A8', '#BDF6D1', '#4ADE80', '#00AC7F', '#0AA2A4', // Silnice 1–5
  '#C2844A', '#929496', '#E5D376', '#B9BEC6', // Kovy 6–9
  '#AEE9FF', '#2CD1D4', '#6EAFFF', '#00A1C7', '#5087D4', '#117897', '#165EEB', // Drahokamy 10–16
  '#D42020', '#EDB42D', '#F5F8FB', // VIP 17–19
  '#FF8C1A', // Legenda 20
];

/// Old seed colours (`20260611_loyalty_ranks.sql`, = `_fallbackLevels` in
/// `loyalty_levels_provider.dart`), index = level − 1.
const List<String> kRankOldSeedHex = [
  '#9CA3AF', '#86EFAC', '#4ADE80', '#22C55E', '#14B8A6',
  '#CD7F32', '#C0C0C0', '#FFD700', '#E5E4E2',
  '#7DD3FC', '#38BDF8', '#3B82F6', '#6366F1', '#8B5CF6', '#A855F7', '#D946EF',
  '#EF4444', '#D4AF37', '#F1F5F9',
  '#FFD700',
];

/// The unapplied v2.1 draft (`20261015_loyalty_colors_no_purple.sql`).
const Map<int, String> kRankV21DraftHex = {
  13: '#FF5A0C',
  14: '#8A9A3B',
  15: '#B39E7E',
  16: '#19A2B4',
};

/// Brand colour for level 0 (guest / loyalty not available).
const String kRankBrandHex = '#74FB71';

final RegExp _hexRe = RegExp(r'^#?[0-9a-fA-F]{6}$');

/// Normalises `#rrggbb` / `rrggbb` to `#RRGGBB`; null when invalid.
String? normalizeRankHex(String? hex) {
  final h = hex?.trim();
  if (h == null || !_hexRe.hasMatch(h)) return null;
  return '#${h.replaceAll('#', '').toUpperCase()}';
}

/// Colour the v2 UI draws for [level] when the DB says [dbHex]:
/// * level 0 (or out of range) → brand neon;
/// * null / invalid / old seed / unapplied v2.1 draft / the ramp colour itself
///   → the ramp colour;
/// * anything else = a manual Velín edit → kept (the solver keeps it
///   contrast-safe).
String resolveRankHex(int level, String? dbHex) {
  if (level < 1 || level > 20) return kRankBrandHex;
  final ramp = kRankRampHex[level - 1];
  final h = normalizeRankHex(dbHex);
  if (h == null) return ramp;
  if (h == ramp) return ramp;
  if (h == kRankOldSeedHex[level - 1]) return ramp;
  if (kRankV21DraftHex[level] == h) return ramp;
  return h;
}
