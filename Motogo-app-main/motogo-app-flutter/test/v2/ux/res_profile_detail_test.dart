// Reservation detail v2 after lookonly-fix (owner 2026-11-07 "jen upgrade
// vzhledu"): the OLD blocks and buttons per status (upcoming: edit + cancel;
// completed: documents + book again; cancelled: restore) call the SAME
// callbacks; the door-code copy keeps its ✓ feedback (RP-29).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart' show DoorCode;
import 'package:motogo_app/features/reservations/v2/res_codes_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_detail_view_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

String _t(String key, [String lang = 'cs']) => translations[lang]?[key] ?? key;

Widget _detail(Reservation r,
        {List<DoorCode> codes = const [],
        VoidCallback? onCancel,
        Future<void> Function(BuildContext, String)? onInvoice}) =>
    ResDetailV2View(
      res: r,
      doorCodesAsync: AsyncData(codes),
      branchFullAddress: 'Boudky, Velké Němčice',
      onStaleRetry: null,
      onBack: () {},
      onShowCancelDialog: onCancel ?? () {},
      onOpenFinalInvoice: onInvoice ?? (_, __) async {},
      onOpenContract: (_, __) async {},
      onRestoreBooking: (_, __) async {},
    );

Future<void> _pump(WidgetTester t, Widget w,
    {String lang = 'cs', Size size = const Size(360, 780), List<Override>? overrides}) async {
  await pumpV2(t, w, lang: lang, size: size, overrides: overrides ?? resOverrides(), reducedMotion: true);
  await t.pump(const Duration(milliseconds: 600));
}

final _sent = [code('accessories', '4821'), code('motorcycle', '7395')];

/// Scrolls the (lazy) detail list until [f] is built, then centres it.
Future<void> _center(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
  Scrollable.ensureVisible(t.element(f), alignment: 0.5);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerReservationStrings();
    mockPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  testWidgets('upcoming: the old "Upravit rezervaci" + "Zrušit rezervaci" (→ the old storno callback)', (t) async {
    var cancels = 0;
    await _pump(t, _detail(resv('u1', status: 'reserved', from: 3, to: 5), onCancel: () => cancels++));
    final cancel = find.text(_t('cancelReservationBtn'));
    await _center(t, cancel);
    expect(find.text(_t('editReservation')), findsOneWidget);
    await t.tap(cancel);
    await t.pump();
    expect(cancels, 1);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('completed: final invoice (= onOpenFinalInvoice with the id) and "Rezervovat znovu"', (t) async {
    final r = resv('c1', status: 'completed', from: -6, to: -3);
    final ids = <String>[];
    await _pump(t, _detail(r, onInvoice: (_, id) async => ids.add(id)));
    final invoice = find.text(_t('finalInvoice'));
    await _center(t, invoice);
    await t.tap(invoice);
    await t.pump();
    expect(ids, [r.id]);
    await _center(t, find.text(_t('bookAgain')));
    expect(find.text(_t('bookAgain')), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('cancelled: the old "Obnovit rezervaci"', (t) async {
    await _pump(t, _detail(resv('x1', status: 'cancelled', from: 3, to: 5)));
    await _center(t, find.text(_t('restoreBooking')));
    expect(find.text(_t('restoreBooking')), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('RP-29 copy code: ✓ for 1.5 s + selectionClick', (t) async {
    final log = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'HapticFeedback.vibrate') log.add('${c.arguments}');
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _pump(t, _detail(resv('d1', status: 'reserved', from: 0, to: 2), codes: _sent));
    final btn = find.byType(ResCopyCodeV2).first;
    await _center(t, btn);
    await t.tap(btn);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(log, contains('HapticFeedbackType.selectionClick'));
    MgIcon icon() => t.widget<MgIcon>(find.descendant(of: btn, matching: find.byType(MgIcon)));
    expect(icon().name, MgIcons.check);
    await t.pump(const Duration(milliseconds: 1600));
    expect(icon().name, MgIcons.copy);
    await t.pump(const Duration(seconds: 4));
  });
}
