import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';

/// Jedna položka rozcestníku (Místa / Trasy / Mapa / Moje zážitky).
class QuickLink {
  final String emoji;
  final String titleKey; // i18n klíč názvu
  final String subtitleKey; // i18n klíč podtitulku
  final Color bg;
  final Color? border;
  final Color fg;
  final Color sub;
  final Color chevron;
  final VoidCallback onTap;

  const QuickLink({
    required this.emoji,
    required this.titleKey,
    required this.subtitleKey,
    required this.bg,
    required this.border,
    required this.fg,
    required this.sub,
    required this.chevron,
    required this.onTap,
  });

  /// Světlá (zelená) dlaždice — primární rozcestník.
  factory QuickLink.light({
    required String emoji,
    required String titleKey,
    required String subtitleKey,
    required VoidCallback onTap,
  }) =>
      QuickLink(
        emoji: emoji,
        titleKey: titleKey,
        subtitleKey: subtitleKey,
        bg: MotoGoColors.greenPale,
        border: MotoGoColors.green,
        fg: MotoGoColors.black,
        sub: MotoGoColors.g600,
        chevron: MotoGoColors.greenDark,
        onTap: onTap,
      );

  /// Tmavá dlaždice — osobní obsah (Moje zážitky).
  factory QuickLink.dark({
    required String emoji,
    required String titleKey,
    required String subtitleKey,
    required VoidCallback onTap,
  }) =>
      QuickLink(
        emoji: emoji,
        titleKey: titleKey,
        subtitleKey: subtitleKey,
        bg: MotoGoColors.dark,
        border: null,
        fg: Colors.white,
        sub: const Color(0xFF8AAB99),
        chevron: MotoGoColors.green,
        onTap: onTap,
      );
}

/// Připnuté rychlé vstupy nad seznamem (Místa ↔ Trasy ↔ Mapa ↔ Moje zážitky).
/// Při scrollování seznamu ZŮSTÁVAJÍ vidět: plné karty pod sebou se plynule
/// (podle posunu) zmenší do kompaktní lišty pilulek vedle sebe. Vodorovným
/// swipem po liště se pořadí cyklicky posune, tapem se položka otevře.
///
/// Zobecněno 2026-09-16 na N položek — dřív uměl delegát přesně dvě dlaždice
/// (slotA/slotB), takže třetí vstup „Mapa" nešlo přidat.
class QuickLinksHeaderDelegate extends SliverPersistentHeaderDelegate {
  /// Posun pořadí 0..N-1 (animovaná hodnota) — kdo je na kolikátém slotu.
  final Animation<double> order;
  final VoidCallback onCycle; // swipe doleva/doprava → posunout pořadí
  final List<QuickLink> links;

  const QuickLinksHeaderDelegate({
    required this.order,
    required this.onCycle,
    required this.links,
  });

  static const double _cardH = 62; // plná karta
  static const double _pillH = 44; // kompaktní pilulka
  static const double _topPad = 10;
  static const double _gap = 8;
  static const double _side = 16;

  int get _n => links.length;

  @override
  double get maxExtent => _topPad + _cardH * _n + _gap * (_n - 1) + 8;

  @override
  double get minExtent => 6 + _pillH + 8;

  @override
  bool shouldRebuild(covariant QuickLinksHeaderDelegate old) =>
      old.order != order || old.links.length != links.length;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = maxExtent - minExtent;
    final raw = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final t = Curves.easeInOutCubic.transform(raw); // 0 = plné karty, 1 = lišta
    return AnimatedBuilder(
      animation: order,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final full = w - _side * 2;
          final cell = (full - _gap * (_n - 1)) / _n;
          // Slot i: karta v i-tém řádku ↔ pilulka v i-tém sloupci.
          Rect slot(int i) => Rect.lerp(
                Rect.fromLTWH(_side, _topPad + (_cardH + _gap) * i, full, _cardH),
                Rect.fromLTWH(_side + (cell + _gap) * i, 6, cell, _pillH),
                t,
              )!;
          final tr = t.clamp(0.0, 1.0);
          // Plynulý posun pořadí: položka j sedí mezi slotem (j+shift) a
          // (j+shift+1) podle desetinné části animace.
          final shift = order.value % _n;
          final base = shift.floor();
          final frac = Curves.easeInOutCubic.transform(shift - base);
          Rect rectFor(int j) => Rect.lerp(
                slot((j + base) % _n),
                slot((j + base + 1) % _n),
                frac,
              )!;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() > 120) onCycle();
            },
            child: Container(
              decoration: BoxDecoration(
                color: MotoGoColors.bg,
                boxShadow: t > 0.05
                    ? [
                        BoxShadow(
                          color: MotoGoColors.dark.withValues(alpha: 0.14 * t),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: ClipRect(
                child: Stack(
                  children: [
                    for (var j = 0; j < _n; j++)
                      Positioned.fromRect(
                        rect: rectFor(j),
                        child: _QuickTile(
                          t: tr,
                          emoji: links[j].emoji,
                          title: t2(context, links[j].titleKey),
                          subtitle: t2(context, links[j].subtitleKey),
                          bg: links[j].bg,
                          border: links[j].border,
                          fg: links[j].fg,
                          sub: links[j].sub,
                          chevron: links[j].chevron,
                          onTap: links[j].onTap,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String t2(BuildContext c, String key) => t(c).tr(key);
}

/// Jedna dlaždice — plynule přechází mezi plnou kartou (emoji + název +
/// podtitulek + šipka) a kompaktní pilulkou (emoji + název).
class _QuickTile extends StatelessWidget {
  final double t; // 0 = karta, 1 = pilulka
  final String emoji;
  final String title;
  final String subtitle;
  final Color bg;
  final Color? border;
  final Color fg;
  final Color sub;
  final Color chevron;
  final VoidCallback onTap;

  const _QuickTile({
    required this.t,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.bg,
    required this.border,
    required this.fg,
    required this.sub,
    required this.chevron,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subOpacity = (1 - t * 2.2).clamp(0.0, 1.0);
    final radius = _lerp(MotoGoRadius.card, MotoGoRadius.pill, t);
    final padH = _lerp(14, 12, t);
    final emojiSize = _lerp(22, 17, t);
    final titleSize = _lerp(MotoGoTypo.sizeLg, MotoGoTypo.sizeBase, t);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: padH),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: border == null ? null : Border.all(color: border!, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: (border ?? bg).withValues(alpha: 0.22 + 0.16 * t),
              blurRadius: 10 + 4 * t,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(emoji, style: TextStyle(fontSize: emojiSize)),
            SizedBox(width: _lerp(12, 8, t)),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: MotoGoTypo.w900,
                      color: fg,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (subOpacity > 0)
                    Opacity(
                      opacity: subOpacity,
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: MotoGoTypo.sizeMd,
                          fontWeight: MotoGoTypo.w600,
                          color: sub,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: _lerp(14, 11, t), color: chevron),
          ],
        ),
      ),
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
