// fix:dates (2026-11-05, both looks, both trees — crash safety, no UX
// change): `DateDropdownField` shows a saved date whose year lies outside
// [firstYear, lastYear] (licence that expired in an earlier year — the
// callers pass firstYear = this year; a birth year above lastYear) — the
// year list extends to it in the same order as today instead of the
// dropdown assert "There should be exactly one item with …'s value".
// `_RadioOption` of the address picker disposes every TextPainter it makes
// to measure its words / price (one per word on every layout before).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart' show translations;
import 'package:motogo_app/core/widgets/date_dropdown_field.dart';
import 'package:motogo_app/features/booking/widgets/address_picker.dart';

import 'v2/support/v2_harness.dart';

/// Old look: a plain MaterialApp without the v2 scope (= flag OFF).
Future<void> _pumpV1(WidgetTester t, Widget child) {
  addTearDown(t.view.reset);
  return t.pumpWidget(MaterialApp(
    home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
  ));
}

/// Values of the year dropdown (the last of day / month / year) in order.
List<int> _years(WidgetTester t) {
  final dd = t.widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>)).last;
  return [for (final i in dd.items!) i.value!];
}

List<int> _range(int a, int b) => a <= b ? [for (var y = a; y <= b; y++) y] : [for (var y = a; y >= b; y--) y];

Widget _expiry({DateTime? value, TextEditingController? controller, int first = 2026, int last = 2046}) =>
    DateDropdownField(
      label: 'Platnost ŘP',
      value: value,
      controller: controller,
      firstYear: first,
      lastYear: last,
      onChanged: controller == null ? (_) {} : null,
    );

void main() {
  for (final v2 in [false, true]) {
    final look = v2 ? 'v2' : 'v1';

    testWidgets('$look: expiry 2024-05-31 with firstYear 2026 renders and shows 2024', (t) async {
      final w = _expiry(value: DateTime(2024, 5, 31));
      if (v2) {
        await pumpV2(t, w);
      } else {
        await _pumpV1(t, w);
      }
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('2024'), findsOneWidget);
      expect(find.text('31'), findsOneWidget);
      expect(_years(t), _range(2024, 2046), reason: 'range extended down, still ascending');
    });

    testWidgets('$look: controller "31. 5. 2024" with firstYear 2026 renders and shows 2024', (t) async {
      final c = TextEditingController(text: '31. 5. 2024');
      addTearDown(c.dispose);
      final w = _expiry(controller: c);
      if (v2) {
        await pumpV2(t, w);
      } else {
        await _pumpV1(t, w);
      }
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('2024'), findsOneWidget);
      expect(_years(t), _range(2024, 2046));
      expect(c.text, '31. 5. 2024', reason: 'showing the saved date never rewrites the controller');
    });

    testWidgets('$look: birth year above lastYear (descending) renders and shows it', (t) async {
      final w = DateDropdownField(
        label: 'Datum narození',
        value: DateTime(2010, 1, 1),
        firstYear: 1920,
        lastYear: 2008,
        yearsDescending: true,
        onChanged: (_) {},
      );
      if (v2) {
        await pumpV2(t, w);
      } else {
        await _pumpV1(t, w);
      }
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('2010'), findsOneWidget);
      expect(_years(t), _range(2010, 1920), reason: 'range extended up, still descending');
    });

    testWidgets('$look: year inside the range / no value → the list is exactly firstYear..lastYear', (t) async {
      final w = Column(children: [
        _expiry(value: DateTime(2030, 6, 1)),
        _expiry(),
      ]);
      if (v2) {
        await pumpV2(t, w);
      } else {
        await _pumpV1(t, w);
      }
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('2030'), findsOneWidget);
      final dds = t.widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>)).toList();
      expect(dds.length, 6);
      for (final i in [2, 5]) {
        expect([for (final it in dds[i].items!) it.value!], _range(2026, 2046));
      }
    });

    testWidgets('$look: address picker renders and disposes every measuring TextPainter', (t) async {
      // Painters made in this test and not disposed yet (identity set, so a
      // painter from an earlier test disposed now does not count).
      final live = Set<Object>.identity();
      var created = 0;
      void onEvent(ObjectEvent e) {
        if (e.object is! TextPainter) return;
        if (e is ObjectCreated) {
          created++;
          live.add(e.object);
        }
        if (e is ObjectDisposed) live.remove(e.object);
      }

      FlutterMemoryAllocations.instance.addListener(onEvent);
      addTearDown(() => FlutterMemoryAllocations.instance.removeListener(onEvent));
      final w = AddressPickerWidget(
        label: 'x',
        method: 'delivery',
        onMethodChanged: (_) {},
        onAddressChanged: (_) {},
        onDeliveryFeeChanged: (_) {},
      );
      if (v2) {
        await pumpV2(t, w);
      } else {
        await _pumpV1(t, w);
      }
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text(translations[v2 ? 'cs' : 'en']!['atBranch']!), findsOneWidget);
      expect(find.text(translations[v2 ? 'cs' : 'en']!['deliveryToAddress']!), findsOneWidget);
      // Second layout (a resize) measures again — must not leak either.
      t.view.physicalSize = const Size(320, 690) * 2;
      await t.pump();
      expect(t.takeException(), isNull);
      // Unmount: the painters of the text widgets go away with them; what
      // stays undisposed is what `_RadioOption` measured with and dropped.
      await t.pumpWidget(const SizedBox());
      expect(created, greaterThan(0));
      expect(live, isEmpty, reason: '${live.length} of $created TextPainters never disposed');
    });
  }
}
