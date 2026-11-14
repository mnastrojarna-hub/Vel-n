import 'package:flutter/material.dart';

import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';

/// Shared pieces of the v2 first-run overlays (board Prihlaseni: Úvod,
/// Jazyk, Oprávnění) — the dark `gDark` page, the logo tile and the drawn
/// language flags (no emoji in the v2 UI, v1 §2.9).

/// Full-screen dark page (`gDark`, brand aura) with light status-bar icons.
class OnbDarkPage extends StatelessWidget {
  final Widget child;
  const OnbDarkPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) => MgStatusBar(
        dark: true,
        child: Material(
          color: MgColors.night,
          child: DecoratedBox(
            decoration: const BoxDecoration(gradient: MgGradients.dark),
            child: child,
          ),
        ),
      );
}

/// The app logo in a dark tile with the neon frame (64 on Jazyk, 40 next
/// to the permission title, 104 + 6 frame on Úvod).
class OnbLogoTile extends StatelessWidget {
  final double size;
  final double frame;
  final double glow;
  const OnbLogoTile({super.key, this.size = 64, this.frame = 2, this.glow = 0.35});

  @override
  Widget build(BuildContext context) {
    final r = size * 0.26;
    return Container(
      padding: EdgeInsets.all(frame),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r + frame),
        color: MgColors.neonA(frame > 3 ? 1 : 0.55),
        boxShadow: [BoxShadow(color: MgColors.neonA(glow), blurRadius: size * 0.3, spreadRadius: 1)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Image.asset(
          'assets/logo.webp',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            color: MgColors.panel,
            child: Center(child: MgIcon(MgIcons.moto, size: size * 0.45, color: MgColors.neon)),
          ),
        ),
      ),
    );
  }
}

/// A small drawn flag (28 × 20, r4) of an app language.
class OnbFlag extends StatelessWidget {
  final String code;
  final double width;
  const OnbFlag(this.code, {super.key, this.width = 28});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: width,
          height: width * 5 / 7,
          child: CustomPaint(painter: _FlagPainter(code)),
        ),
      );
}

class _FlagPainter extends CustomPainter {
  final String code;
  _FlagPainter(this.code);

  static const _red = Color(0xFFD7141A), _blue = Color(0xFF11457E), _white = Color(0xFFFFFFFF);

  void _h(Canvas c, Size s, List<Color> cols) {
    final h = s.height / cols.length;
    for (var i = 0; i < cols.length; i++) {
      c.drawRect(Rect.fromLTWH(0, i * h, s.width, h + 0.5), Paint()..color = cols[i]);
    }
  }

  void _v(Canvas c, Size s, List<Color> cols) {
    final w = s.width / cols.length;
    for (var i = 0; i < cols.length; i++) {
      c.drawRect(Rect.fromLTWH(i * w, 0, w + 0.5, s.height), Paint()..color = cols[i]);
    }
  }

  @override
  void paint(Canvas c, Size s) {
    switch (code) {
      case 'cs':
        _h(c, s, const [_white, _red]);
        c.drawPath(
            Path()
              ..moveTo(0, 0)
              ..lineTo(s.width * 0.5, s.height / 2)
              ..lineTo(0, s.height)
              ..close(),
            Paint()..color = _blue);
      case 'en':
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF012169));
        final w = s.height * 0.2;
        final white = Paint()
          ..color = _white
          ..strokeWidth = w;
        final red = Paint()
          ..color = const Color(0xFFC8102E)
          ..strokeWidth = w * 0.4;
        for (final p in [white, red]) {
          c.drawLine(Offset.zero, Offset(s.width, s.height), p);
          c.drawLine(Offset(s.width, 0), Offset(0, s.height), p);
        }
        c.drawRect(Rect.fromCenter(center: s.center(Offset.zero), width: s.width, height: w * 1.6), Paint()..color = _white);
        c.drawRect(Rect.fromCenter(center: s.center(Offset.zero), width: w * 1.6, height: s.height), Paint()..color = _white);
        final r = Paint()..color = const Color(0xFFC8102E);
        c.drawRect(Rect.fromCenter(center: s.center(Offset.zero), width: s.width, height: w), r);
        c.drawRect(Rect.fromCenter(center: s.center(Offset.zero), width: w, height: s.height), r);
      case 'de':
        _h(c, s, const [Color(0xFF000000), Color(0xFFDD0000), Color(0xFFFFCE00)]);
      case 'pl':
        _h(c, s, const [_white, Color(0xFFDC143C)]);
      case 'fr':
        _v(c, s, const [Color(0xFF0055A4), _white, Color(0xFFEF4135)]);
      case 'es':
        final h = s.height / 4;
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFAA151B));
        c.drawRect(Rect.fromLTWH(0, h, s.width, h * 2), Paint()..color = const Color(0xFFF1BF00));
      case 'nl':
        _h(c, s, const [Color(0xFFAE1C28), _white, Color(0xFF21468B)]);
      case 'uk':
        _h(c, s, const [Color(0xFF0057B7), Color(0xFFFFD700)]);
      default:
        c.drawRect(Offset.zero & s, Paint()..color = MgColors.panel);
    }
    // Hairline edge so a white field never melts into a light surface.
    c.drawRRect(
      RRect.fromRectAndRadius((Offset.zero & s).deflate(0.25), const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = MgColors.white(0.25),
    );
  }

  @override
  bool shouldRepaint(_FlagPainter old) => old.code != code;
}
