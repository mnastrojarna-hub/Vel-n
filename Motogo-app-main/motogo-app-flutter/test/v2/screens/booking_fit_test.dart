// Booking v2 fit rules (fix:booking): option rows / extras rows move the
// price under the text on narrow rows or large text, the extras row drops
// its item icon there, the pay dock never clips the price and turns the
// trailing link into a chevron button when the text would be squeezed,
// the step pill label is never cut, amounts never split.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/features/booking/v2/booking_dock_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_header_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_v2_parts.dart';
import 'package:motogo_app/features/booking/v2/sections/extras_rows_v2.dart';

import '../render/render_inspect.dart' show midWordBreak;
import '../support/v2_harness.dart';

/// [child] at [width] (card-like gutter) with system text [scale].
Widget _host(Widget child, {double width = 288, double scale = 1.0}) => Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Align(alignment: Alignment.topCenter, child: SizedBox(width: width, child: child)),
      ),
    );

RenderParagraph _para(WidgetTester t, String text) => t.renderObject<RenderParagraph>(find.text(text));

Rect _rect(WidgetTester t, String text) => t.getRect(find.text(text));

void main() {
  setUpAll(loadMontserrat);

  test('amounts never split (no-break spaces, joined per-km rate)', () {
    expect(bkNbAmounts('1 000 CZK + 40 CZK/km'), '1 000 CZK + 40 CZK/⁠km');
    expect(bkNbAmounts('od 1 000 Kč'), 'od 1 000 Kč');
    expect(bkNbAmounts('Na pobočce'), 'Na pobočce');
  });

  testWidgets('option row: narrow / large text → price under the sub line', (t) async {
    await pumpV2(
      t,
      _host(
        BkOptionRow(title: 'Livraison à ton adresse', sub: '1 000 CZK + 40 CZK/km', trailing: 'à partir de 1 000 CZK', selected: true, onTap: () {}),
        width: 256,
        scale: 1.3,
      ),
      lang: 'fr',
      size: const Size(320, 690),
    );
    await t.pump();
    expect(t.takeException(), isNull);
    final price = _rect(t, 'à partir de 1 000 CZK');
    final title = _rect(t, 'Livraison à ton adresse');
    expect(price.top, greaterThan(title.bottom));
    if (montserratLoaded) expect(midWordBreak(_para(t, 'Livraison à ton adresse')), isNull);
  });

  testWidgets('option row: roomy row → price stays on the right', (t) async {
    await pumpV2(
      t,
      _host(BkOptionRow(title: 'Na pobočce', sub: 'Mezná 9', trailing: 'Zdarma', selected: false, onTap: () {}), width: 560),
      size: const Size(600, 800),
    );
    await t.pump();
    expect(t.takeException(), isNull);
    expect(_rect(t, 'Zdarma').left, greaterThan(_rect(t, 'Na pobočce').right));
  });

  testWidgets('extras row: narrow / large text → no item icon, price under the title', (t) async {
    await pumpV2(
      t,
      _host(
        BookingExtraRowV2(
          icon: MgIcons.helmet,
          title: 'Beifahrerausrüstung',
          sub: 'Helm, Handschuhe, Weste',
          needSize: false,
          price: 'Gratis',
          struck: '690 Kč',
          freeWithRank: true,
          selected: false,
          onTap: () {},
        ),
        width: 256,
        scale: 1.3,
      ),
      lang: 'de',
      size: const Size(320, 690),
    );
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byType(MgIcon), findsNothing);
    expect(_rect(t, 'Gratis').top, greaterThan(_rect(t, 'Beifahrerausrüstung').bottom));
    if (montserratLoaded) expect(midWordBreak(_para(t, 'Beifahrerausrüstung')), isNull);
  });

  testWidgets('extras row: roomy row keeps the icon and the price column', (t) async {
    await pumpV2(
      t,
      _host(
        BookingExtraRowV2(
          icon: MgIcons.helmet,
          title: 'Vozík',
          sub: null,
          needSize: false,
          price: '300 Kč',
          selected: false,
          onTap: () {},
        ),
        width: 560,
      ),
      size: const Size(600, 800),
    );
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byType(MgIcon), findsOneWidget);
    expect(_rect(t, '300 Kč').left, greaterThan(_rect(t, 'Vozík').right));
  });

  testWidgets('pay dock: price never clipped, squeezed link → chevron with its label', (t) async {
    await pumpV2(
      t,
      _host(
        Column(mainAxisSize: MainAxisSize.min, children: [
          BookingDockV2(
            canProceed: true,
            blocker: null,
            context2: 'Dein Preis · 3 Tage',
            price: '11 893 Kč',
            onProceed: () {},
            onTrailing: () {},
            trailingLabel: 'Aufstellung',
          ),
        ]),
        width: 320,
        scale: 1.3,
      ),
      lang: 'de',
      size: const Size(320, 690),
    );
    await t.pump(const Duration(milliseconds: 500));
    expect(t.takeException(), isNull);
    expect(_para(t, '11 893 Kč').didExceedMaxLines, isFalse);
    expect(find.text('Aufstellung'), findsNothing);
    expect(find.bySemanticsLabel('Aufstellung'), findsOneWidget);
  });

  testWidgets('pay dock: blocker gets up to 3 lines', (t) async {
    await pumpV2(
      t,
      _host(
        Column(mainAxisSize: MainAxisSize.min, children: [
          BookingDockV2(
            canProceed: false,
            blocker: 'Tailles d’équipement manquantes',
            context2: null,
            price: null,
            onProceed: () {},
            onTrailing: () {},
            trailingLabel: 'Compléter',
          ),
        ]),
        width: 320,
        scale: 1.3,
      ),
      lang: 'fr',
      size: const Size(320, 690),
    );
    await t.pump(const Duration(milliseconds: 500));
    expect(t.takeException(), isNull);
    final p = _para(t, 'Tailles d’équipement manquantes');
    expect(p.maxLines, 3);
    expect(p.didExceedMaxLines, isFalse);
  });

  testWidgets('step pill: long label is never cut', (t) async {
    await pumpV2(t, _host(const BookingStepsV2(current: 2), width: 288, scale: 1.3),
        lang: 'fr', size: const Size(320, 690));
    await t.pump(const Duration(milliseconds: 500));
    expect(t.takeException(), isNull);
    final p = _para(t, 'Vérification et paiement');
    expect(p.didExceedMaxLines, isFalse);
    expect(p.textSize.width, lessThanOrEqualTo(p.size.width + 1));
  });
}
