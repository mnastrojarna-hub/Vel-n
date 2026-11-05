import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

import '../tokens/mg_shadows.dart';
import 'rank_palette.dart';
import 'rank_row.dart';
import 'rank_solver.dart';
import 'rank_table.dart';

export 'rank_row.dart' show RankTier, RankRingKind;

/// Glyph that marks the two top tiers (crown = VIP, laurel = Legenda).
enum RankGlyph { none, crown, laurel }

/// Everything the v2 UI needs to draw a rank ("rank drives the look").
/// Rank NEVER colours prices, ✓/⚠/✕, SOS, focus rings, links or wallet
/// buttons; on light surfaces it shows only as ring / dot / emblem / progress.
@immutable
class RankTokens {
  /// 0 = guest / loyalty not available (pure brand), 1–20 = rank level.
  final int level;
  final RankRow row;

  const RankTokens._(this.level, this.row);

  static final Map<String, RankTokens> _cache = {};

  /// Tokens for [level] whose DB colour is [dbHex] (mapped to the v2.2 ramp
  /// by [resolveRankHex]; manual Velín colours go through the solver).
  factory RankTokens.forLevel(int level, [String? dbHex]) {
    final lv = level.clamp(0, 20);
    final hex = resolveRankHex(lv, dbHex);
    return _cache.putIfAbsent('$lv$hex', () {
      final RankRow row;
      if (lv >= 1 && hex == kRankRampHex[lv - 1]) {
        row = kRankRampTable[lv - 1];
      } else {
        row = solveRankRow(lv, hex);
      }
      return RankTokens._(lv, row);
    });
  }

  /// Pure brand tokens (guest, loyalty RPC failed).
  static final RankTokens brand = RankTokens.forLevel(0);

  bool get isBrand => level == 0;
  RankTier get tier => row.tier;
  int get tierIndex => tier.index;

  static const _tierFrom = [1, 6, 10, 17, 20];
  static const _tierTo = [5, 9, 16, 19, 20];

  /// First / last level of this tier.
  int get tierFrom => _tierFrom[tierIndex];
  int get tierTo => _tierTo[tierIndex];

  /// Step inside the tier (1-based) and the tier size.
  int get step => isBrand ? 1 : level - tierFrom + 1;
  int get steps => tierTo - tierFrom + 1;

  /// 0..1 position inside the tier (1 for single-level tiers).
  double get stepFraction => steps > 1 ? (step - 1) / (steps - 1) : 1;

  Color get hex => Color(row.hex);
  Color get accentOnDark => Color(row.accentDark);
  Color get accentGlass => Color(row.accentGlass);
  Color get uiDark => Color(row.uiDark);
  Color get uiLight => Color(row.uiLight);
  Color get chipBg => Color(row.chipBg);
  Color get chipText => Color(row.chipText);
  Color get chipBorder => hex.withValues(alpha: 0.55);
  Color get aura => Color(row.aura);
  Color get glowColor => Color(row.glow);
  Color get ctaLabel => Color(row.ctaLabel);
  List<Color> get ctaFill => row.ctaFill.map(Color.new).toList();
  List<Color> get ctaEdge => row.ctaEdge.map(Color.new).toList();
  List<Color> get ring => row.ring.map(Color.new).toList();
  Color? get ring2 => row.ring2 == null ? null : Color(row.ring2!);
  Color? get arc => row.arc == null ? null : Color(row.arc!);
  RankRingKind get ringKind => row.ringKind;
  double get ringWidth => const [3.0, 3.0, 3.5, 3.5, 4.0][tierIndex];

  /// White CTA label (deep jewels 15–16): static bands are toned down.
  bool get whiteLabel => row.ctaLabel == 0xFFFFFFFF;

  RankGlyph get glyph => tier == RankTier.vip
      ? RankGlyph.crown
      : (tier == RankTier.legend ? RankGlyph.laurel : RankGlyph.none);

  /// CTA fill (4 stops at 0 / 33 / 67 / 100 %).
  LinearGradient get ctaGradient =>
      cssLinearGradient(row.ctaAngle, ctaFill, const [0, 0.33, 0.67, 1]);

  /// CTA edge (1.5 px border-box gradient, 135°).
  LinearGradient get edgeGradient =>
      cssLinearGradient(135, ctaEdge, const [0, 0.35, 0.7, 1]);

  /// Step halo strength (`--rk-sh`): none on step 1 of a multi-level tier.
  double get _stepHaloAlpha => (step == 1 && steps > 1) ? 0 : 0.12 + 0.2 * stepFraction;
  double get _gx => (12 * stepFraction).roundToDouble();

  /// CTA glow (`.rk-cta` box-shadow). [pulse] 0..1 = the `rkGlow` loop
  /// position (0 = rest; the loop goes 0 → 1 → 0 over 2.2 s).
  List<BoxShadow> ctaGlow([double pulse = 0]) {
    final k = pulse.clamp(0.0, 1.0);
    final gb = row.glowBlur + _gx;
    final glowA = glowColor.withValues(alpha: row.glowAlpha);
    final glowS = glowColor.withValues(alpha: math.min(0.95, row.glowAlpha + 0.3));
    final shb = (10 + 14 * stepFraction).roundToDouble();
    return [
      BoxShadow(
        offset: Offset(0, 8),
        blurRadius: gb + 6 * k,
        spreadRadius: lerpDouble(-8, -6, k)!,
        color: Color.lerp(glowA, glowS, k)!,
      ),
      if (k > 0)
        BoxShadow(
          spreadRadius: (row.pulsePx + _gx / 4) * k,
          color: glowA.withValues(alpha: row.glowAlpha * (1 - k)),
        ),
      if (row.haloAlpha > 0)
        BoxShadow(
          blurRadius: row.haloBlur,
          spreadRadius: 4 * k,
          color: glowColor.withValues(alpha: row.haloAlpha),
        ),
      if (_stepHaloAlpha > 0)
        BoxShadow(
          blurRadius: shb + 8 * k,
          spreadRadius: 2 * k,
          color: glowColor.withValues(alpha: _stepHaloAlpha),
        ),
    ];
  }

  /// Soft static glow for small rank surfaces (nav pill, emblem, FAB ring).
  List<BoxShadow> softGlow({double blur = 16, double dy = 6}) => [
        BoxShadow(
          offset: Offset(0, dy),
          blurRadius: blur + _gx,
          spreadRadius: -6,
          color: glowColor.withValues(alpha: math.min(0.95, row.glowAlpha + 0.3)),
        ),
      ];

  /// Progress inside the level (`arcPct`): [points] = effective loyalty
  /// points (`LoyaltyStatus.qualifyingCount`). 2 points per level.
  double arcPctFor(int? points) {
    if (level >= 20) return 100;
    if (level <= 0) return 0;
    final from = 2 * level - 2;
    final p = (points ?? from + 1) < from ? from : (points ?? from + 1);
    return ((p - from) / 2 * 100).roundToDouble().clamp(4, 100);
  }

  @override
  bool operator ==(Object other) =>
      other is RankTokens && other.level == level && other.row.hex == row.hex;

  @override
  int get hashCode => Object.hash(level, row.hex);
}
