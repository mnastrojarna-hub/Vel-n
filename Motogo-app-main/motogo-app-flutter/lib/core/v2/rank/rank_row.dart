/// Raw per-level rank data (one row of the generated ramp table or of the
/// solver output). Colours are ARGB ints so the table can stay `const`.
/// [RankTokens] wraps a row into Flutter types.
library;

/// The five effect tiers (DESIGN_V22 §1.3), decided by the LEVEL number.
enum RankTier { road, metal, jewel, vip, legend }

/// How the logo / avatar ring is painted.
enum RankRingKind { solid, metal, jewel, vip, legend }

class RankRow {
  final RankTier tier;
  final int hex;

  /// Rank-coloured text on dark `#0E2A1C` (≥ 4.5 : 1).
  final int accentDark;

  /// Rank-coloured text on the white .06 glass over a rank hero (≥ 4.6 : 1).
  final int accentGlass;

  /// Solved accent for light surfaces — NOT used for text in v2 (rank text
  /// on light is ink, V22 §1.4); kept for parity with the boards.
  final int accentLight;

  /// Non-text marks on dark (ring, arcs) ≥ 3 : 1.
  final int uiDark;

  /// Non-text marks on white (progress fill) ≥ 3 : 1.
  final int uiLight;
  final int chipBg;
  final int chipText;

  /// First stop of the dark hero gradient (white text stays ≥ 4.5 : 1).
  final int aura;
  final int glow;
  final double glowAlpha;
  final double glowBlur;
  final double haloAlpha;
  final double haloBlur;
  final double pulsePx;

  /// Primary CTA fill, 4 stops at 0 / 33 / 67 / 100 %.
  final List<int> ctaFill;

  /// CSS angle of [ctaFill] in degrees.
  final double ctaAngle;
  final int ctaLabel;

  /// CTA edge (border-box gradient, 135°), 4 stops.
  final List<int> ctaEdge;
  final RankRingKind ringKind;
  final List<int> ring;

  /// VIP outer keyline (gold / cream), null otherwise.
  final int? ring2;

  /// Progress arc colour on dark; null = Legenda (no next level).
  final int? arc;

  const RankRow(
    this.tier,
    this.hex,
    this.accentDark,
    this.accentGlass,
    this.accentLight,
    this.uiDark,
    this.uiLight,
    this.chipBg,
    this.chipText,
    this.aura,
    this.glow,
    this.glowAlpha,
    this.glowBlur,
    this.haloAlpha,
    this.haloBlur,
    this.pulsePx,
    this.ctaFill,
    this.ctaAngle,
    this.ctaLabel,
    this.ctaEdge,
    this.ringKind,
    this.ring,
    this.ring2,
    this.arc,
  );
}
