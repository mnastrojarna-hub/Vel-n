// v2.2 PAINTED-TOKEN DISTINCTNESS picks of appdesign/research/rankTheme.js
// (shared fixer 2026-10-16, ported r2 2026-10-29). The DB colours of the
// ramp are ΔE-solved, but the tokens the UI PAINTS (rank text, glass accent,
// chip text, glow, CTA fill, ring) still collided (ΔE00 2.4–8.7). These
// searched picks keep every painted token ΔE00 ≥ 10 for every pair and ≥ 12
// for neighbours, inside each colour's family and with every WCAG target.
// They apply ONLY while a level still carries its ramp (seed) colour — a
// colour edited in Velín falls back to the solver (rank_solver.dart).
library;

/// Rank text on dark (steel cobalt · petrol · royal sapphire · VIP ivory).
const Map<int, String> kRankAccDark = {
  14: '#90A0C3', 15: '#7FB8C5', 16: '#5E8CFF', 17: '#F6E7C9',
};

/// Chip text (≥ 4.5 on the chip and on #1A2E22).
const Map<int, String> kRankChipText = {
  7: '#9E9E9E', 9: '#C1C5D1', 11: '#2CDFE2', 12: '#8ABEFF', 16: '#5792FF',
};

/// Rank text on the hero glass (header rank name, motto, eyebrows).
const Map<int, String> kRankAccGlass = {
  3: '#56E66E', 4: '#22C38E', 5: '#32BEBB', 7: '#ADADAD', 9: '#C9CFDD',
  11: '#1AF0F4', 12: '#99CEFF', 13: '#0CBEDF', 14: '#A5AECF', 15: '#94B8C2',
  16: '#88A9FC',
};

/// Glow colour.
const Map<int, String> kRankGlow = {
  1: '#A6FF8F', 7: '#8E9298', 9: '#C3C9D3', 14: '#118BDF', 15: '#348D79',
  16: '#4773FD', 19: '#FBF7EE',
};

/// Jewel CTA partner hue shift (deg) at matched luminance.
const Map<int, double> kRankCtaSpin = {
  10: 12, 11: 12, 12: -10, 13: -14, 14: 10, 15: -16, 16: 6,
};

/// Silnice CTA: share of the RANK colour in stops 1–4 (1–2 from brand
/// neon-hi, 3–4 from neon-lo) — the neon only tints the first third.
const List<double> kRankRoadW = [0.65, 0.9, 1, 1];

/// Fixed CTA fills (7 silver for its seed only; 17 / 18 for any colour).
const Map<int, List<String>> kRankCtaStops = {
  7: ['#C6C7C8', '#9FA1A3', '#8B8D90', '#7F8184'],
  17: ['#FFF7E6', '#FBE9C9', '#F2D5A6'],
  18: ['#F7E4A8', '#E6BE4E', '#D2A22A', '#9C7818'],
};

/// Jewel ring partner hue shifts (deg).
const Map<int, List<double>> kRankRingSpin = {
  10: [-10, 10], 11: [-10, 10], 12: [-10, 10], 13: [-10, 10],
  14: [-10, 10], 15: [-10, 10], 16: [8, 10],
};

/// Metal ring stops / VIP Gold flat brushed gold (no Legenda stops).
const Map<int, List<String>> kRankRingStops = {
  6: ['#E7CEB7', '#C2844A', '#9C6B3C'],
  7: ['#CDCECF', '#8E9092', '#76787A'],
  9: ['#EEF1F5', '#C3CAD5', '#9AA3B0'],
  18: ['#C8952F', '#DDB862', '#B08429'],
};
