// SOS náhrada (r2): posílá se adresa, kterou zákazník v poli VIDÍ — i ručně
// doplněné číslo domu nebo opravená „GPS …“ ulice; „Doplněno podle polohy“
// zmizí, jakmile zákazník adresu přepíše.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/widgets/address_autocomplete_field.dart';
import 'package:motogo_app/features/sos/sos_here_address.dart';
import 'package:motogo_app/features/sos/sos_replacement_screen.dart' show sosDeliveryAddress;

import 'support/v2_harness.dart' show pumpV2;

void main() {
  const here = AddressSuggestion(street: 'Masarykova', city: 'Brno', zip: '60200', lat: 49.19, lng: 16.6);
  const shown = 'Masarykova, 60200 Brno';

  group('sosDeliveryAddress', () {
    test('prázdné pole → null (hláška „Zadej adresu doručení“)', () {
      expect(sosDeliveryAddress('   ', here, shown), isNull);
      expect(sosDeliveryAddress('', null, ''), isNull);
    });

    test('nezměněný výběr → text pole + souřadnice', () {
      expect(sosDeliveryAddress(shown, here, shown), 'Masarykova, 60200 Brno (GPS 49.19000, 16.60000)');
    });

    test('doplněné číslo domu se pošle, staré souřadnice ne', () {
      expect(sosDeliveryAddress('Masarykova 12, 60200 Brno', here, shown), 'Masarykova 12, 60200 Brno');
    });

    test('ručně napsaná adresa bez výběru návrhu se přijme', () {
      expect(sosDeliveryAddress(' Lidická 5, Brno ', null, ''), 'Lidická 5, Brno');
    });

    test('opravená GPS záloha', () {
      const gps = AddressSuggestion(street: 'GPS 49.19000, 16.60000', city: '', zip: '', lat: 49.19, lng: 16.6);
      expect(sosDeliveryAddress('Kounicova 2, Brno', gps, 'GPS 49.19000, 16.60000'), 'Kounicova 2, Brno');
    });
  });

  testWidgets('přepsání pole vrátí „Kde právě jsi“ do výchozího stavu', (tester) async {
    final key = GlobalKey<SosHereAddressState>();
    final field = GlobalKey<AddressAutocompleteFieldState>();
    await pumpV2(
        tester,
        Column(children: [
          SosHereAddress(
              key: key,
              onPick: (s) => field.currentState?.setAddress(s.street, s.city, s.zip),
              locate: () async => here),
          AddressAutocompleteField(
              key: field, onSelected: (_) {}, onChanged: (_) => key.currentState?.markEdited()),
        ]),
        v2: false);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SosHereAddress));
    await tester.pumpAndSettle();
    expect(field.currentState?.text, shown);
    expect(find.textContaining('Adresu můžeš upravit'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Masarykova 12, 60200 Brno');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Adresu můžeš upravit'), findsNothing);
    expect(find.text('Masarykova, Brno'), findsOneWidget); // znovu k jednomu klepnutí
    await tester.pump(const Duration(seconds: 1)); // debounce návrhů
  });
}
