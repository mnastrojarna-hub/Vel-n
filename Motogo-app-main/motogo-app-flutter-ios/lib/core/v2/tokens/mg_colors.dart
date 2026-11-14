import 'dart:ui' show Color;

/// v2 colour tokens (PLAN §1.2, DESIGN_V22 §2). The ONLY place where v2 code
/// may spell a hex colour (rank colours live in `rank/`). Meaning colours
/// (✓ ⚠ ✕ SOS price link focus) never take the rank colour.
abstract final class MgColors {
  // ── Dark brand ────────────────────────────────────────────────────────
  static const neon = Color(0xFF74FB71);
  static const neonHi = Color(0xFF8DFF86);
  static const neonLo = Color(0xFF37CF63);
  static const neonText = Color(0xFFA8FF9F);
  static const onNeon = Color(0xFF08230F);
  static const priceOnNeon = Color(0xFF0B3B1A);
  static const night = Color(0xFF0A1F14);
  static const panel = Color(0xFF0E2A1C);
  static const glow = Color(0xFF24563B);
  static const ink = Color(0xFF1A2E22);
  static const borderDark = Color(0xFF2A5A3E);
  static const ctaDarkStop = Color(0xFF2A6A45);

  // ── Text on dark ──────────────────────────────────────────────────────
  static const onDark = Color(0xFFFFFFFF);
  static const onDarkBody = Color(0xFFE8F5EE);
  static const onDarkLead = Color(0xFFCFE7DA);
  static const onDarkSecondary = Color(0xFFB8D4C6);
  static const onDarkMeta = Color(0xFF9FC4B1);
  static const onDarkFloor = Color(0xFF8FB3A1);

  // ── Light surfaces (V22 §2.1) ─────────────────────────────────────────
  static const canvas = Color(0xFFF4F7F5);
  static const surface = Color(0xFFFFFFFF);
  static const well = Color(0xFFF2F5F3);
  static const line = Color(0xFFE2EAE5);
  static const lineInput = Color(0xFF7C958A);
  static const meta = Color(0xFF55705F);
  static const lead = Color(0xFF4A6B5A);
  static const body2 = Color(0xFF2C4A3A);
  static const link = Color(0xFF0D6E0D);
  static const price = link;
  static const focusLight = link;
  static const routeGreen = Color(0xFF1F9A4A);
  static const tintOk = Color(0xFFE8FCE8);
  static const tintOkBorder = Color(0xFF37CF63);
  static const onTintOk = Color(0xFF0D4F1C);
  static const tintFeatureA = Color(0xFFEAFBF0);
  static const tintFeatureB = Color(0xFFD9F5E4);
  static const offerA = Color(0xFFE6FAE2);
  static const offerB = Color(0xFFF6FFF4);
  static const disabled = Color(0xFF9DB3A8);
  static const grabberLight = Color(0xFFCFE3DA);
  static const weekendCell = Color(0xFFF3FBF7);

  // ── Meaning ───────────────────────────────────────────────────────────
  static const warn = Color(0xFF8A4B00);
  static const warnBg = Color(0xFFFFF4E0);
  static const warnBorder = Color(0xFFE9B44C);
  static const warnDark = Color(0xFFFFD36B);
  static const warnDarkBg = Color(0x29FFC857); // rgba(255,200,87,.16)
  static const err = Color(0xFFB42318);
  static const errBg = Color(0xFFFDECEC);
  static const errBorder = Color(0xFFF3B5AF);
  static const errDark = Color(0xFFFFB3B3);
  static const errDarkBg = Color(0x24FF7878); // rgba(255,120,120,.14)
  static const sos = Color(0xFFD92D20);
  static const sosDot = Color(0xFFEF4444);
  static const star = Color(0xFFF59E0B);
  static const starOffLight = Color(0xFFD6DFDA);
  static const starOffDark = Color(0x40FFFFFF);
  static const pending = Color(0xFFA66A00);
  static const petrol = Color(0xFF19A2B4); // non-rank modification history

  // ── Calendar ──────────────────────────────────────────────────────────
  static const calBand = neon;
  static const calContour = routeGreen;
  static const hatchA = Color(0xFFEEF2F0);
  static const hatchB = Color(0xFFFFFFFF);

  // ── Translucent helpers (white / night overlays) ──────────────────────
  static Color white(double a) => Color.fromRGBO(255, 255, 255, a);
  static Color nightA(double a) => Color.fromRGBO(10, 31, 20, a);
  static Color black(double a) => Color.fromRGBO(0, 0, 0, a);
  static Color neonA(double a) => Color.fromRGBO(116, 251, 113, a);
  static Color inkA(double a) => Color.fromRGBO(26, 46, 34, a);
}
