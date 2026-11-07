// res_profile (RP-14/19/23/26/30): "Rezervovat zde" on the branch card =
// the screen's booking action, pull-to-refresh = the existing retry on
// Rezervace / Zprávy / Profil, the shared photo tag list card → detail,
// the detail hero height clamp, the list card's main label by state.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/chrome/mg_photo_hero.dart';
import 'package:motogo_app/core/v2/motion/mg_hero_photo.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/branches/branches_info_provider.dart' show branchesInfoDefaults;
import 'package:motogo_app/features/branches/v2/branches_view_v2.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:motogo_app/features/messages/v2/messages_view_v2.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/reservations/v2/res_detail_view_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservation_card_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservations_screen_v2.dart';
import 'package:motogo_app/features/reservations/v2/ride_feedback_sheet_v2.dart';
import 'package:motogo_app/features/reservations/widgets/ride_feedback_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_profile.dart';
import '../support/fakes_reservations.dart';
import '../support/hero_tags.dart';
import '../support/profile_harness.dart';
import '../support/supabase_stub.dart';
import '../support/v2_harness.dart';

String _t(String key, [String lang = 'cs']) => translations[lang]?[key] ?? key;

/// Loops (Živě ping, CTA fx) never settle → pump the motion out instead.
Future<void> _settle(WidgetTester t, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Pull-to-refresh: a downward fling from [from] at the top of the page.
Future<void> _pull(WidgetTester t, Finder from) async {
  await t.fling(from, const Offset(0, 320), 1200);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await _settle(t, 14);
}

Widget _detail(Reservation r) => ResDetailV2View(
      res: r,
      doorCodesAsync: const AsyncData(<DoorCode>[]),
      branchFullAddress: 'Boudky, Velké Němčice',
      onStaleRetry: null,
      onBack: () {},
      onShowCancelDialog: () {},
      onOpenFinalInvoice: (_, __) async {},
      onOpenContract: (_, __) async {},
      onRestoreBooking: (_, __) async {},
    );

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerReservationStrings();
    registerProfileStrings();
    mockPathProvider();
    await stubSupabase();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  group('RP-30 list card main label', () {
    Future<int Function()> card(WidgetTester t, Reservation r) async {
      var taps = 0;
      await pumpV2(t, ReservationCardV2(reservation: r, onTap: () => taps++, onEdit: () {}, primary: true),
          overrides: resOverrides(), reducedMotion: true);
      await t.pump(const Duration(milliseconds: 600));
      return () => taps;
    }

    testWidgets('pickup-day self-service: "Kódy a postup", same tap as Detail', (t) async {
      final taps = await card(t, resv('d1', status: 'reserved', from: 0, to: 2));
      final cta = t.widget<MgCta>(find.byType(MgCta));
      expect(cta.label, _t('v2HomeCtaCodes'));
      await t.tap(find.byType(MgCta));
      await t.pump();
      expect(taps(), 1);
    });

    testWidgets('staffed or not yet in the rental term: Detail', (t) async {
      await card(t, resv('m1', status: 'reserved', from: 5, to: 7, self: false));
      expect(t.widget<MgCta>(find.byType(MgCta)).label, _t('detail'));
      await card(t, resv('d4', status: 'reserved', from: 5, to: 7));
      expect(t.widget<MgCta>(find.byType(MgCta)).label, _t('detail'));
    });
  });

  testWidgets('RP-14 branch card: "Rezervovat zde" = onBook, the detail stays a ghost button', (t) async {
    var books = 0;
    final opened = <int>[];
    await pumpV2(
      t,
      BranchesViewV2(
        tx: branchesInfoDefaults,
        onBack: () {},
        onRefresh: () async {},
        onOpen: opened.add,
        onBook: () => books++,
        onMotosSheet: () {},
      ),
      reducedMotion: true,
    );
    await t.pump(const Duration(milliseconds: 600));
    final book = find.widgetWithText(MgBtnInk, _t('v2UxRpBookHere'));
    expect(book, findsNWidgets(2));
    await t.ensureVisible(book.first);
    await t.pump();
    await t.tap(book.first);
    await t.pump();
    expect(books, 1);
    expect(opened, isEmpty);
    final detail = find.byType(MgBtnGhostLight);
    await t.ensureVisible(detail.first);
    await t.pump();
    await t.tap(detail.first);
    await t.pump();
    expect(opened, [0]);
    expect(books, 1);
  });

  group('RP-19 pull-to-refresh = the existing retry', () {
    testWidgets('Rezervace: re-reads the reservations stream', (t) async {
      var reads = 0;
      final ov = resOverrides(list: sampleList());
      await pumpV2(
        t,
        const ReservationsScreenV2(),
        overrides: [
          reservationsProvider.overrideWith((ref) {
            reads++;
            return Stream.value(sampleList());
          }),
          ...ov.skip(1),
        ],
        reducedMotion: true,
      );
      await _settle(t, 8);
      final before = reads;
      await _pull(t, find.text(_t('myReservations')).first);
      expect(reads, greaterThan(before));
    });

    testWidgets('Zprávy: notes tab → onRetryAdmin, chats tab → onRetryThreads', (t) async {
      var admin = 0, threads = 0;
      Widget view(bool chat) => MessagesViewV2(
            adminAsync: AsyncData([
              AdminMessage(id: 'n1', title: 'Kódy k vyzvednutí', message: 'Text', type: 'door_codes', read: true, createdAt: DateTime(2026, 10, 1)),
            ]),
            threadsAsync: const AsyncData(<MessageThread>[]),
            chatTab: chat,
            expanded: const {},
            unread: 0,
            onBack: () {},
            onTab: (_) {},
            onToggleNote: (_) {},
            onMarkAll: () {},
            onNewThread: () {},
            onOpenThread: (_) {},
            onRetryAdmin: () => admin++,
            onRetryThreads: () => threads++,
          );
      await pumpV2(t, view(false), overrides: resOverrides(), reducedMotion: true);
      await _settle(t, 6);
      await _pull(t, find.text('Kódy k vyzvednutí'));
      expect((admin, threads), (1, 0));
      await pumpV2(t, view(true), overrides: resOverrides(), reducedMotion: true);
      await _settle(t, 6);
      await _pull(t, find.text(_t('noConversations')));
      expect((admin, threads), (1, 1));
    });

    testWidgets('Profil hub: the screen retry', (t) async {
      var retries = 0;
      await pumpV2(t, PfHubHarness(onRetry: () => retries++), overrides: profileOverrides(), reducedMotion: true);
      await _settle(t, 6);
      await _pull(t, find.byType(PfHubHarness));
      expect(retries, 1);
    });
  });

  testWidgets('RP-04 v2 "Odeslat" runs the old send once: failure keeps the sheet and the text', (t) async {
    String? result = 'unset';
    await pumpV2(
      t,
      Builder(
        builder: (c) => TextButton(
          onPressed: () async => result =
              await showRideFeedbackSheet(c, res: resv('d5', status: 'completed', from: -6, to: -4), rating: 2),
          child: const Text('open'),
        ),
      ),
      overrides: resOverrides(),
    );
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.enterText(find.byType(TextField), 'Brzdy pískaly');
    await t.pump();
    // Dvojí klepnutí bez snímku mezi nimi: druhé zastaví stráž `_sending`.
    await t.tap(find.text(_t('send')));
    await t.tap(find.text(_t('send')), warnIfMissed: false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    // Bez přihlášení odeslání selže stejně jako dnes: sheet zůstává, text
    // zůstává, jedna hláška „text zůstal".
    expect(find.byType(RideFeedbackSheetV2), findsOneWidget);
    expect(find.text('Brzdy pískaly'), findsOneWidget);
    expect(find.textContaining(_t('eoTextKept')), findsOneWidget);
    expect(result, 'unset');
  });

  group('RP-23 / RP-26 detail photo', () {
    testWidgets('list cards and the detail carry res-img-{id}, one tag per route', (t) async {
      await pumpV2(t, const ReservationsScreenV2(), overrides: resOverrides(list: sampleList()));
      await _settle(t, 8);
      expectUniqueHeroTags(t);
      final r = resv('a1', status: 'reserved', from: 5, to: 7);
      expect(find.byWidgetPredicate((w) => w is Hero && w.tag == mgHeroTagRes(r.id)), findsOneWidget);
      await pumpV2(t, _detail(r), overrides: resOverrides());
      await _settle(t, 8);
      expectUniqueHeroTags(t);
      expect(find.byWidgetPredicate((w) => w is Hero && w.tag == mgHeroTagRes(r.id)), findsOneWidget);
    });

    testWidgets('reduced motion: no shared-element flight', (t) async {
      await pumpV2(t, _detail(resv('a1', status: 'reserved', from: 5, to: 7)), overrides: resOverrides(), reducedMotion: true);
      await _settle(t, 4);
      expect(find.byType(Hero), findsNothing);
    });

    for (final (size, h) in const [(Size(320, 690), 690 * 0.34), (Size(360, 600), 220.0), (Size(412, 915), 300.0)]) {
      testWidgets('hero height clamp(220, .34 × h, 300) at ${size.width.toInt()}×${size.height.toInt()}', (t) async {
        await pumpV2(t, _detail(resv('a1', status: 'reserved', from: 5, to: 7)),
            overrides: resOverrides(), size: size, reducedMotion: true);
        await _settle(t, 4);
        expect(t.getSize(find.byType(MgPhotoHero)).height, moreOrLessEquals(h, epsilon: 0.5));
      });
    }
  });
}
