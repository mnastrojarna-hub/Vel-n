// res_profile gestures + edit (RP-10/11/13/18): Rezervace filter swipe (body
// follows, the filter track follows the finger, fling ← = next filter +
// selectionClick, vertical / diagonal never switches, reduced motion =
// instant), Zprávy notes ↔ threads swipe, loading skeleton without a false
// "0", edit iOS edge-back to the chooser with section state kept, money CTA
// "ZAPLATIT DOPLATEK · 4 296 Kč" on one line.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/core/v2/widgets/mg_skeleton.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:motogo_app/features/messages/v2/messages_view_v2.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_chooser_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_view_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_filter_tabs_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservations_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/reservations_cases.dart';
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';

String _t(String key, [String lang = 'cs']) => translations[lang]?[key] ?? key;

List<String> _haptics(WidgetTester t) {
  final log = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
    if (c.method == 'HapticFeedback.vibrate') log.add('${c.arguments}');
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return log;
}

/// Loops (Živě ping, CTA fx) never settle → pump the motion out instead.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

String _filter(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(ReservationsScreenV2))).read(resFilterProvider);

Future<void> _list(WidgetTester t, {bool reduced = false, bool loading = false}) async {
  await pumpV2(t, const ReservationsScreenV2(),
      overrides: resOverrides(list: sampleList(), loading: loading), reducedMotion: reduced);
  await t.pump(const Duration(milliseconds: 800));
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

  group('RP-10 Rezervace filter swipe', () {
    testWidgets('fling ← = next filter + selectionClick; → = back', (t) async {
      final log = _haptics(t);
      await _list(t);
      await t.fling(find.text('Husqvarna 701 SM').first, const Offset(-220, 0), 900);
      await _settle(t);
      expect(_filter(t), 'aktivni');
      expect(log, contains('HapticFeedbackType.selectionClick'));
      await t.fling(find.text('Husqvarna 701 SM').first, const Offset(220, 0), 900);
      await _settle(t);
      expect(_filter(t), 'all');
    });

    testWidgets('the filter track follows the finger mid-drag', (t) async {
      await _list(t);
      final tabs = t.widget<ResFilterTabsV2>(find.byType(ResFilterTabsV2));
      final g = await t.startGesture(t.getCenter(find.text('Husqvarna 701 SM').first));
      await g.moveBy(const Offset(-30, 0));
      await g.moveBy(const Offset(-90, 0));
      await t.pump();
      expect(tabs.dragProgress!.value, greaterThan(0));
      await g.up();
      await _settle(t);
      expect(tabs.dragProgress!.value, 0);
    });

    testWidgets('vertical and diagonal (mostly vertical) drags never switch', (t) async {
      await _list(t);
      await t.drag(find.text('Husqvarna 701 SM').first, const Offset(0, -300));
      await _settle(t);
      expect(_filter(t), 'all');
      await t.drag(find.byType(ReservationsScreenV2), const Offset(-30, -260));
      await _settle(t);
      expect(_filter(t), 'all');
    });

    testWidgets('a short slow drag springs back', (t) async {
      await _list(t);
      await t.drag(find.text('Husqvarna 701 SM').first, const Offset(-40, 0));
      await _settle(t);
      expect(_filter(t), 'all');
    });

    testWidgets('reduced motion: switch is instant (old list gone after one frame)', (t) async {
      await _list(t, reduced: true);
      expect(find.text('Royal Enfield Shotgun 650'), findsWidgets);
      await t.fling(find.text('Husqvarna 701 SM').first, const Offset(-220, 0), 900);
      await t.pump();
      expect(_filter(t), 'aktivni');
      expect(find.text('Royal Enfield Shotgun 650'), findsNothing);
    });

    testWidgets('tap twin: ‹ › steps still change the filter', (t) async {
      await _list(t);
      await t.tap(find.bySemanticsLabel(_t('v2ResNextFilter')));
      await _settle(t);
      expect(_filter(t), 'aktivni');
    });
  });

  testWidgets('RP-13 loading: two card skeletons, no false "0" counts', (t) async {
    await _list(t, loading: true);
    expect(find.byType(MgSkeletonPhotoCard), findsNWidgets(2));
    expect(find.descendant(of: find.byType(ResFilterTabsV2), matching: find.text('0')), findsNothing);
  });

  group('RP-10 Zprávy notes ↔ threads', () {
    Widget view(bool chat, ValueChanged<bool> onTab) => MessagesViewV2(
          adminAsync: AsyncData([
            AdminMessage(id: 'n1', title: 'Kódy k vyzvednutí', message: 'Text', type: 'door_codes', read: true, createdAt: DateTime(2026, 10, 1)),
          ]),
          threadsAsync: const AsyncData(<MessageThread>[]),
          chatTab: chat,
          expanded: const {},
          unread: 0,
          onBack: () {},
          onTab: onTab,
          onToggleNote: (_) {},
          onMarkAll: () {},
          onNewThread: () {},
          onOpenThread: (_) {},
          onRetryAdmin: () {},
          onRetryThreads: () {},
        );

    testWidgets('fling ← on notes → Konverzace; fling → on threads → Oznámení', (t) async {
      bool? got;
      await pumpV2(t, view(false, (v) => got = v), overrides: resOverrides());
      await t.pump(const Duration(milliseconds: 600));
      await t.fling(find.text('Kódy k vyzvednutí'), const Offset(-220, 0), 900);
      await _settle(t);
      expect(got, isTrue);
      got = null;
      await pumpV2(t, view(true, (v) => got = v), overrides: resOverrides());
      await t.pump(const Duration(milliseconds: 600));
      await t.fling(find.text(_t('noConversations')), const Offset(220, 0), 900);
      await _settle(t);
      expect(got, isFalse);
    });
  });

  group('RP-18 / RP-11 edit', () {
    final b = resv('e1', status: 'reserved', from: 4, to: 6);

    Widget edit({ResEditIntent? intent, Widget? place, String lang = 'cs'}) => ResEditV2View(
          booking: b,
          tab: 'extend',
          isActive: false,
          canMove: true,
          canSwap: true,
          returnTimeAvailable: false,
          calc: editCalc(b),
          sections: ResEditV2Sections(pickupPlace: place),
          stornoPct: null,
          missingSizes: const [],
          saveLabel: _t('v2UxRpPayDiffCta', lang),
          savePrice: '4 296 Kč',
          saveContext: 'Původně 12 027 Kč → nově 16 323 Kč',
          onSave: () {},
          saving: false,
          onBack: () {},
          onSelectExtend: () {},
          onSelectShorten: () {},
          onSelectMove: () {},
          onSelectSwap: () {},
          initialIntent: intent,
        );

    testWidgets('iOS left-edge swipe in an intent returns to the chooser', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpV2(t, edit(intent: ResEditIntent.place, place: const SizedBox(height: 200)), overrides: resOverrides());
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byType(ResEditChooserV2), findsNothing);
        await t.dragFrom(const Offset(4, 420), const Offset(260, 0));
        await _settle(t);
        expect(find.byType(ResEditChooserV2), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('text typed in an intent survives chooser ↔ intent', (t) async {
      await pumpV2(t, edit(intent: ResEditIntent.place, place: const TextField(key: ValueKey('note'))),
          overrides: resOverrides());
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(find.byKey(const ValueKey('note')), 'Zvonek 2');
      await t.pump();
      await t.tap(find.bySemanticsLabel(_t('back')).first);
      await _settle(t);
      expect(find.byType(ResEditChooserV2), findsOneWidget);
      await t.tap(find.text(_t('v2ResIntPlace')).first);
      await _settle(t);
      expect(find.text('Zvonek 2'), findsOneWidget);
    });

    for (final (lang, size) in [('cs', const Size(360, 780)), ('de', const Size(320, 690))]) {
      testWidgets('pay CTA "${_t('v2UxRpPayDiffCta', lang)} · price" on one line, $lang ${size.width.toInt()}', (t) async {
        await pumpV2(t, edit(intent: ResEditIntent.extend, lang: lang), lang: lang, size: size, overrides: resOverrides());
        await t.pump(const Duration(milliseconds: 400));
        final cta = t.widget<MgCta>(find.byType(MgCta));
        expect(cta.label, _t('v2UxRpPayDiffCta', lang));
        expect(cta.price, '4 296 Kč');
        final p = t.renderObject<RenderParagraph>(
            find.descendant(of: find.byType(MgCta), matching: find.byType(RichText)).first);
        final n = p.text.toPlainText().length;
        final tops = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n)).map((b) => b.top.round()).toSet();
        expect(tops, hasLength(1), reason: 'one line');
        expect(find.byKey(const ValueKey('res-edit-pay-diff')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });
}
