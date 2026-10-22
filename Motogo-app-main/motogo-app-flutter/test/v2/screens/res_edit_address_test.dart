// „Nic nevyplňovat dvakrát“ v úpravě rezervace (majitel 2026-10-22,
// fix:reservations): adresa přistavení / odvozu, kterou rezervace už má, se
// ukáže vyplněná (v2: zodpovězená sekce se „Změnit“) a předvyplní list;
// potvrzení stejné adresy = beze změny (žádný poplatek ani historie);
// psaní v listu přepíše předvyplněnou adresu; odvoz na adresu nabídne
// „Stejná jako u přistavení“ i adresu z profilu (8 jazyků × 2 velikosti).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motogo_app/core/i18n/translations.dart' show translations;
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/booking/widgets/address_picker.dart';
import 'package:motogo_app/features/reservations/reservation_edit_address.dart';
import 'package:motogo_app/features/reservations/reservation_edit_price_calc.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_address_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_notes_v2.dart';

import '../render/render_harness.dart' show loadRenderFonts;
import '../render/render_inspect.dart';
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

const _saved = 'Masarykova 12, 602 00 Brno';
const _profile = {'street': 'Lidická 5', 'city': 'Pelhřimov', 'zip': '393 01'};

/// Stejné složení textu jako `ReservationEditScreen._addrText`.
String? _text(AddressResult a) {
  final s = [a.street, a.city].map((e) => e.trim()).where((e) => e.isNotEmpty).join(', ');
  return s.isEmpty ? null : s;
}

String _tr(String lang, String key) => translations[lang]?[key] ?? key;

/// Část obrazovky úpravy: tentýž stav a tytéž zpětná volání jako
/// `ReservationEditScreen` (metody, nové adresy, poplatky) + `EditPriceCalc`.
class _Host extends StatefulWidget {
  final Reservation b;
  final bool v2;
  const _Host(this.b, {this.v2 = true});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late String pm = widget.b.pickupMethod == 'delivery' ? 'delivery' : 'store';
  late String rm = widget.b.returnMethod == 'delivery' ? 'delivery' : 'store';
  String? pNew, rNew;
  double pFee = 0, rFee = 0;
  int addrCalls = 0;

  EditPriceCalc get calc => EditPriceCalc(
        booking: widget.b,
        newStart: widget.b.startDate,
        newEnd: widget.b.endDate,
        motoPrices: null,
        newMotoId: null,
        pickupDelivFee: pFee,
        returnDelivFee: rFee,
        selectedExtras: const {},
        pickupMethod: pm,
        returnMethod: rm,
        pickupAddressNew: pNew,
        returnAddressNew: rNew,
        pickupTime: '12:00',
        returnTime: '19:00',
        helmetSize: widget.b.helmetSize,
        jacketSize: widget.b.jacketSize,
        pantsSize: widget.b.pantsSize,
        bootsSize: widget.b.bootsSize,
        glovesSize: widget.b.glovesSize,
        passengerHelmetSize: widget.b.passengerHelmetSize,
        passengerJacketSize: widget.b.passengerJacketSize,
        passengerPantsSize: widget.b.passengerPantsSize,
        passengerBootsSize: widget.b.passengerBootsSize,
      );

  @override
  Widget build(BuildContext context) {
    final carry = EditAddressCarry.of(widget.b, pickupMethod: pm, returnMethod: rm, pickupNew: pNew, returnNew: rNew);
    final AddressRowBuilder? row = widget.v2 ? (c, d) => ResEditAddressRowV2(data: d) : null;
    String tr(String k) => _tr(Localizations.localeOf(context).languageCode, k);
    return SingleChildScrollView(
      child: Column(children: [
        ResEditGroupV2(
          title: tr('pickupMotorcycle'),
          child: AddressPickerWidget(
            label: 'Vyzvednutí',
            method: pm,
            initialAddress: carry.savedPickup,
            currentAddress: pNew,
            quick: carry.quick(tr, pickup: true, profile: _profile),
            rowBuilder: row,
            onMethodChanged: (m) => setState(() => pm = m),
            onAddressChanged: (a) => setState(() {
              addrCalls++;
              pNew = _text(a);
            }),
            onDeliveryFeeChanged: (f) => setState(() => pFee = f),
          ),
        ),
        ResEditGroupV2(
          title: tr('returnMotorcycle'),
          child: AddressPickerWidget(
            label: 'Vrácení',
            isPickup: false,
            method: rm,
            initialAddress: carry.savedReturn,
            currentAddress: rNew,
            quick: carry.quick(tr, pickup: false, profile: _profile),
            rowBuilder: row,
            onMethodChanged: (m) => setState(() => rm = m),
            onAddressChanged: (a) => setState(() => rNew = _text(a)),
            onDeliveryFeeChanged: (f) => setState(() => rFee = f),
          ),
        ),
      ]),
    );
  }
}

Reservation _booking() => resv('d1', status: 'reserved', from: 9, to: 12, self: false, delivery: true);

Future<_HostState> _pump(WidgetTester t,
    {String lang = 'cs', Size size = const Size(412, 915), bool v2 = true, GlobalKey? shot}) async {
  MgMotion.resetSession();
  await pumpV2(t, _Host(_booking(), v2: v2), lang: lang, size: size, reducedMotion: true, v2: v2, boundaryKey: shot);
  await t.pump(const Duration(milliseconds: 700));
  return t.state<_HostState>(find.byType(_Host));
}

/// Sítě nedostupné (geokódování / našeptávač → odhad vzdálenosti podle obce).
Future<void> _offline(Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient((_) async => http.Response('{}', 404)));

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUpAll(() async {
    await loadRenderFonts();
    registerReservationStrings();
  });

  group('EditAddressCarry', () {
    test('uložená adresa jen u strany na adrese, rychlé volby bez duplicit', () {
      final b = _booking();
      var c = EditAddressCarry.of(b, pickupMethod: 'delivery', returnMethod: 'store');
      expect((c.savedPickup, c.savedReturn, c.pickupNow, c.returnNow), (_saved, null, _saved, null));
      String tr(String k) => k;
      // Přistavení: vlastní adresu znovu nenabízí, jen profil.
      expect(c.quick(tr, pickup: true, profile: _profile).map((q) => q.label), ['bkAddrMine']);
      // Odvoz na adresu: „Stejná jako u přistavení“ (uložená) + profil.
      c = EditAddressCarry.of(b, pickupMethod: 'delivery', returnMethod: 'delivery');
      final r = c.quick(tr, pickup: false, profile: _profile);
      expect(r.map((q) => (q.label, q.street, q.city)), [
        ('bkAddrSamePickup', 'Masarykova 12', '602 00 Brno'),
        ('bkAddrMine', 'Lidická 5', 'Pelhřimov'),
      ]);
      // Nově zadaná adresa přistavení má přednost před uloženou.
      c = EditAddressCarry.of(b, pickupMethod: 'delivery', returnMethod: 'delivery', pickupNew: 'Lidická 5, Pelhřimov');
      expect(c.quick(tr, pickup: false, profile: _profile).map((q) => q.street), ['Lidická 5']);
      // Přistavení na pobočce → žádná „stejná jako“.
      c = EditAddressCarry.of(b, pickupMethod: 'store', returnMethod: 'delivery');
      expect(c.quick(tr, pickup: false).isEmpty, isTrue);
    });

    test('rozdělení a porovnání adresy', () {
      expect(splitAddressLine(_saved), ('Masarykova 12', '602 00 Brno'));
      expect(splitAddressLine('Brno'), ('', 'Brno'));
      expect(sameAddressLine('masarykova 12 ,602 00  Brno', _saved), isTrue);
      expect(sameAddressLine('', ''), isFalse);
    });
  });

  testWidgets('uložená adresa se ukáže vyplněná, „Změnit“ ji otevře předvyplněnou; stejná = beze změny',
      (t) => _offline(() async {
            final s = await _pump(t);
            expect(find.text(_saved), findsOneWidget);
            expect(find.text(_tr('cs', 'v2BkChange')), findsOneWidget);
            expect(find.text(_tr('cs', 'clickEnterAddress')), findsNothing);
            expect(s.addrCalls, 0, reason: 'nic se nehlásí, dokud zákazník adresu nezmění');
            expect(s.calc.hasChanges, isFalse);

            await t.tap(find.text(_tr('cs', 'v2BkChange')));
            await _settle(t);
            final field = t.widget<TextField>(find.byType(TextField));
            expect(field.controller!.text, _saved);
            await t.tap(find.text(_tr('cs', 'confirmAddressBtn')));
            await _settle(t);
            expect(find.byType(TextField), findsNothing);
            expect(s.pNew, _saved);
            expect(s.calc.pickupAddressChanged, isFalse);
            expect(s.calc.deliveryFeeDelta, 0);
            expect(s.calc.deliveryAddressMissing, isFalse);
            expect(find.textContaining(' km · '), findsNothing, reason: 'žádná nová cena u nezměněné adresy');
            expect(find.text(_saved), findsOneWidget);
          }));

  testWidgets('psaní v předvyplněném listu uloží napsanou adresu i s její cenou', (t) => _offline(() async {
        final s = await _pump(t);
        await t.tap(find.text(_tr('cs', 'v2BkChange')));
        await _settle(t);
        await t.enterText(find.byType(TextField), 'Lidická 5, Pelhřimov');
        await _settle(t);
        await t.tap(find.text(_tr('cs', 'confirmAddressBtn')));
        await _settle(t);
        expect(s.pNew, 'Lidická 5, Pelhřimov');
        expect(s.calc.pickupAddressChanged, isTrue);
        expect(s.pFee, greaterThan(0));
        expect(find.text('Lidická 5, Pelhřimov'), findsOneWidget);
        expect(find.textContaining(' km · '), findsOneWidget);
      }));

  testWidgets('odvoz na adresu nabídne adresu přistavení jedním klepnutím', (t) => _offline(() async {
        final s = await _pump(t);
        await t.tap(find.text(_tr('cs', 'returnFromAddress')));
        await t.pump(const Duration(milliseconds: 500));
        await t.tap(find.text(_tr('cs', 'v2BkEnterAddress')));
        await _settle(t);
        expect(find.text(_tr('cs', 'bkAddrSamePickup')), findsOneWidget);
        expect(find.text(_tr('cs', 'bkAddrMine')), findsOneWidget);
        await t.tap(find.text(_tr('cs', 'bkAddrSamePickup')));
        await _settle(t);
        await t.tap(find.text(_tr('cs', 'confirmAddressBtn')));
        await _settle(t);
        expect(s.rNew, _saved);
        expect(s.rFee, greaterThan(0));
        expect(s.calc.deliveryAddressMissing, isFalse);
        // Přistavení zůstává beze změny.
        expect(s.pNew, isNull);
      }));

  testWidgets('pobočka → adresa vrací uloženou adresu (rodič drží „beze změny“)', (t) async {
    final s = await _pump(t, v2: false);
    expect(find.text(_saved), findsOneWidget, reason: 'starý vzhled ukazuje uloženou adresu taky');
    await t.tap(find.text(_tr('cs', 'atBranch')).first);
    await t.pump(const Duration(milliseconds: 300));
    expect(s.pNew, isNull);
    await t.tap(find.text(_tr('cs', 'deliveryToAddress')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(_saved), findsOneWidget);
    expect(s.calc.hasChanges, isFalse);
  });

  group('8 jazyků × 2 velikosti: řádek uložené adresy', () {
    for (final lang in kV2Langs) {
      for (final size in kV2Sizes) {
        testWidgets('$lang ${size.width.toInt()}', (t) async {
          final shot = GlobalKey();
          await _pump(t, lang: lang, size: size, shot: shot);
          expect(t.takeException(), isNull);
          await maybeShot(t, shot, 'res_edit_address__${lang}__${size.width.toInt()}');
          expect(find.text(_saved), findsOneWidget);
          expect(find.text(_tr(lang, 'v2BkChange')), findsOneWidget);
          final fails = inspectFrame(t.binding.renderViews.first, lang, size).where((f) => f.fail);
          expect(fails.map((f) => '${f.kind} "${f.text}" ${f.detail}'), isEmpty);
        });
      }
    }
  });
}
