// fix:home (verify:render) — Home layout guards that keep words whole at
// narrow widths / large text: word fit measured at the real text size,
// the club perk pair stacking, the ticket pill scaling instead of fading
// and the route card title sized from the text scaler.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/home/v2/home_club_parts.dart';
import 'package:motogo_app/features/home/v2/home_fit.dart';
import 'package:motogo_app/features/home/v2/home_routes_v2.dart' show homeRouteChipH, homeRouteTitleH;
import 'package:motogo_app/features/home/v2/home_ticket_parts.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';

import 'support/v2_harness.dart';

Widget _host(Widget child, {double scale = 1}) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    );

void main() {
  test('homeWordsFit measures at the current text size', () {
    const s = TextStyle(fontSize: 10, fontFamily: 'FlutterTest');
    expect(homeWordsFit('Dieses Wochenende', s, 100), isTrue); // 10 glyphs × 10 px
    expect(homeWordsFit('Dieses Wochenende', s, 100, const TextScaler.linear(1.3)), isFalse);
  });

  testWidgets('club perks: side by side when the words fit, else stacked', (t) async {
    Future<(Rect, Rect)> pump(String label) async {
      await t.pumpWidget(_host(SizedBox(
        width: 300,
        child: ClubPerkPair(
          first: const ClubPerk(big: '−5 %', label: 'Sleva'),
          second: ClubPerk(big: '0', label: label),
        ),
      )));
      final perks = find.byType(ClubPerk);
      return (t.getRect(perks.at(0)), t.getRect(perks.at(1)));
    }

    final (a, b) = await pump('Boty zdarma');
    expect(a.top, b.top);
    expect(b.left, greaterThan(a.right));
    final (c, d) = await pump('Passagiersuitrusting gratis');
    expect(d.top, greaterThanOrEqualTo(c.bottom));
    expect(d.width, c.width);
    expect(t.takeException(), isNull);
  });

  testWidgets('ticket pill scales a long status instead of cutting it', (t) async {
    await t.pumpWidget(_host(const SizedBox(width: 150, child: Row(children: [Flexible(child: TkPill('Bevorstehend'))])), scale: 1.3));
    final p = t.renderObject<RenderParagraph>(find.text('BEVORSTEHEND'));
    expect(p.textSize.width, lessThanOrEqualTo(p.size.width + 0.5));
    expect(t.takeException(), isNull);
  });

  testWidgets('route card title / chips grow with the text size', (t) async {
    late double h1, h13, c1, c13;
    await t.pumpWidget(_host(Builder(builder: (c) {
      h1 = homeRouteTitleH(c);
      c1 = homeRouteChipH(c);
      return const SizedBox();
    })));
    await t.pumpWidget(_host(Builder(builder: (c) {
      h13 = homeRouteTitleH(c);
      c13 = homeRouteChipH(c);
      return const SizedBox();
    }), scale: 1.3));
    expect(h1, 40);
    expect(c1, 24);
    expect(h13, greaterThanOrEqualTo(2 * 15 * 1.3 * 1.3));
    expect(c13, greaterThan(24));
  });

  // fix:shared r4 — the funnel CTA at 320 dp (card margin 16 + padding 16 →
  // 256 px wide): the amount never loses its currency to a second line
  // ("ЗАБРОНЮВАТИ · 11 893" / "Kč"); it shrinks a little onto one line or
  // breaks only after the "·".
  setUpAll(loadMontserrat);
  for (final lang in ['uk', 'pl', 'de', 'cs', 'nl']) {
    testWidgets('funnel CTA $lang 320: amount stays with its currency', (t) async {
      const price = '11 893 Kč';
      await pumpV2(
          t,
          Center(
            child: SizedBox(
              width: 256,
              child: Builder(
                builder: (c) => MgCta(
                    label: t_(c).tr('v2HomeCtaReserve'), price: price, size: MgCtaSize.lg60, onTap: () {}),
              ),
            ),
          ),
          lang: lang,
          size: const Size(320, 640),
          dpr: 1,
          reducedMotion: true);
      await t.pump();
      final p = t.renderObject<RenderParagraph>(find.byType(RichText).first);
      final plain = p.text.toPlainText();
      final start = plain.indexOf(price.replaceAll(' ', '\u00a0'));
      expect(start, greaterThan(0), reason: 'price span is one unbreakable word');
      final y0 = p.getOffsetForCaret(TextPosition(offset: start), Rect.zero).dy;
      final y1 = p.getOffsetForCaret(TextPosition(offset: plain.length - 1), Rect.zero).dy;
      expect(y1, closeTo(y0, 0.5), reason: 'currency on the same line as the amount ($lang)');
      expect(p.didExceedMaxLines, isFalse);
      expect(p.textSize.width, lessThanOrEqualTo(p.size.width + 0.5));
      expect(t.takeException(), isNull);
    });
  }
}

AppTranslations t_(BuildContext c) => t(c);
