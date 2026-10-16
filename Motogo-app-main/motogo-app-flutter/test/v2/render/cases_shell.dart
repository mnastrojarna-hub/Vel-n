// verify:render cases — the v2 shell with REAL tab screens in a GoRouter:
// 5-tab nav (Profil label in every language), floating AI button vs CTAs
// / strips / nav, payment + SOS status strips, Rezervace dot, Profil
// badge, top banner on non-Home tabs.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/banner_provider.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/pending_sos_fab_provider.dart';
import 'package:motogo_app/core/v2/shell/app_shell_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/reservations/v2/reservations_screen_v2.dart';
import 'package:motogo_app/features/routes/all_pois_screen.dart';

import '../screens/home_test.dart' show homeCases;
import '../support/fakes_catalog.dart' show catalogOverrides;
import '../support/fakes_profile.dart' show profileOverrides;
import '../support/fakes_reservations.dart';
import '../support/fakes_routes.dart' show routesOverrides, rtEnd;
import '../support/profile_harness.dart';
import 'render_harness.dart';

GoRouter Function() _router(String initial) => () => GoRouter(initialLocation: initial, routes: [
      ShellRoute(builder: (_, __, child) => AppShellV2(child: child), routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreenV2()),
        GoRoute(path: '/search', builder: (_, __) => const MotorkyScreenV2()),
        GoRoute(path: '/reservations', builder: (_, __) => const ReservationsScreenV2()),
        GoRoute(path: '/routes', builder: (_, __) => const AllPoisScreen(asTab: true)),
        GoRoute(path: '/profile', builder: (_, __) => const PfHubHarness()),
      ]),
    ]);

final _flag = appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true));
final _paid = paidAfterRestartProvider.overrideWith((ref) async => null);
const _banner = BannerData(enabled: true, text: '» V zimním období od 1. 11. 2026 do 25. 3. 2027 zavřeno.', bg: Color(0xFF0E2A1C), color: Color(0xFF74FB71));

List<Override> _extras({bool booking = true, bool sos = true, bool docs = true, bool banner = true, int? unread = 2}) => [
      _flag,
      _paid,
      if (booking) pendingBookingFabProvider.overrideWith((ref) => Stream.value(null)),
      if (sos) pendingSosFabProvider.overrideWith((ref) => Stream.value(null)),
      if (docs) docsFabStatusProvider.overrideWith((ref) => Completer<DocsScreenStatus>().future),
      if (banner) bannerProvider.overrideWithValue(const AsyncData(_banner)),
      if (unread != null) adminUnreadCountProvider.overrideWithValue(unread),
    ];

RenderCase _s(String state, String route, List<Override> Function() o, {Future<void> Function(WidgetTester)? end}) =>
    RenderCase('shell', 'tab', state, () => const SizedBox(), o, router: _router(route), end: end);

List<RenderCase> shellRenderCases() {
  final home = homeCases();
  final unpaid = resv('u1', status: 'pending', pay: 'unpaid', from: 9, to: 11, bike: 'BMW R 1200 GS Adventure',
      created: DateTime.now().subtract(const Duration(minutes: 5)));
  return [
    _s('home_funnel', '/', () => [...home['s0']!(), _flag, _paid]),
    _s('home_unpaid_strip', '/', () => [...home['s2']!(), _flag, _paid]),
    _s('home_sos_strip', '/', () => [...home['s1']!(), _flag, _paid]),
    _s('home_ticket', '/', () => [...home['s6']!(), _flag, _paid]),
    _s('motorky', '/search', () => [...catalogOverrides(), ..._extras(banner: false)]),
    _s('reservations', '/reservations', () => [...resOverrides(list: sampleList()), ..._extras(booking: false)]),
    _s('reservations_unpaid', '/reservations', () => [
          ...resOverrides(list: [unpaid, ...sampleList()], pending: PendingBooking(id: unpaid.id, totalPrice: 12027, createdAt: unpaid.createdAt)),
          ..._extras(booking: false),
        ]),
    _s('routes', '/routes', () => [...routesOverrides(), ..._extras(), reservationsProvider.overrideWith((ref) => Stream.value(const <Reservation>[]))], end: rtEnd),
    _s('profile', '/profile', () => [...profileOverrides(unread: 12), ..._extras(docs: false, unread: null)]),
  ];
}
