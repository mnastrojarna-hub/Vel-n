// verify:render cases — hide-on-scroll + one bike per screen (owner
// 2026-11-08): Motorky / Domů scrolled down by a USER drag onto bike 2
// (bars folded: nav band, card = the screen) and the bike detail pager
// scrolled down (controls + nav folded). Safe areas 47 / 34 like an
// iPhone. MG_VERIFY_RENDER=1 flutter test test/v2/render/render_bars_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/pending_sos_fab_provider.dart';
import 'package:motogo_app/core/v2/gestures/mg_zone_snap.dart';
import 'package:motogo_app/core/v2/shell/app_shell_v2.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';

import '../screens/home_test.dart' show homeCases;
import '../support/fakes_catalog.dart' show catalogOverrides;
import 'render_harness.dart';

GoRouter Function() _router(String initial) => () => GoRouter(initialLocation: initial, routes: [
      ShellRoute(builder: (_, __, child) => AppShellV2(child: child), routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreenV2()),
        GoRoute(path: '/search', builder: (_, __) => const MotorkyScreenV2()),
        GoRoute(path: '/moto/:id', builder: (_, s) => MotoDetailScreen(motoId: s.pathParameters['id']!)),
      ]),
    ]);

final _shellExtras = [
  appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)),
  paidAfterRestartProvider.overrideWith((ref) async => null),
  pendingBookingFabProvider.overrideWith((ref) => Stream.value(null)),
  pendingSosFabProvider.overrideWith((ref) => Stream.value(null)),
  docsFabStatusProvider.overrideWith((ref) => Completer<DocsScreenStatus>().future),
  adminUnreadCountProvider.overrideWithValue(0),
];

Future<void> _insets(WidgetTester t) async {
  t.view.padding = const FakeViewPadding(top: 94, bottom: 68);
  t.view.viewPadding = const FakeViewPadding(top: 94, bottom: 68);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

/// A real finger drag (pauses → no fling) of [dy] px on [at].
Future<void> _drag(WidgetTester t, Offset at, double dy) async {
  final g = await t.startGesture(at);
  for (var i = 0; i < 8; i++) {
    await g.moveBy(Offset(0, dy / 8));
    await t.pump(const Duration(milliseconds: 16));
  }
  await t.pump(const Duration(milliseconds: 200));
  await g.up();
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Lands on bike [k] of the page list by a user drag (bars fold).
Future<void> _toBike(WidgetTester t, Type screen, int k) async {
  await _insets(t);
  final zone = t.renderObject<RenderMgSnapZone>(find.byType(MgSnapZoneSliver, skipOffstage: false)).zone;
  final pos = t.state<ScrollableState>(find.descendant(of: find.byType(screen), matching: find.byType(Scrollable)).first).position;
  pos.jumpTo(zone.offsetOf(k) - 120);
  await t.pump();
  await _drag(t, const Offset(200, 400), -120);
  // Reduced motion = no animated snap: land exactly on the bike (a
  // programmatic jump keeps the bars folded).
  pos.jumpTo(zone.offsetOf(k));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _detail(WidgetTester t) async {
  await _insets(t);
  // On the hero (the dock below does not scroll).
  await _drag(t, const Offset(200, 260), -420);
}

List<RenderCase> barsRenderCases() {
  final home = homeCases();
  return [
    RenderCase('bars', 'motorky', 'bike2_folded', () => const SizedBox(), () => [...catalogOverrides(), ..._shellExtras],
        router: _router('/search'), after: (t) => _toBike(t, MotorkyScreenV2, 1)),
    RenderCase('bars', 'home', 'bike1_folded', () => const SizedBox(), () => [...home['s0']!(), ..._shellExtras],
        router: _router('/'), after: (t) => _toBike(t, HomeScreenV2, 0)),
    RenderCase(
      'bars',
      'detail',
      'scrolled_folded',
      () => const SizedBox(),
      () => [
        ...catalogOverrides(),
        ..._shellExtras,
        filteredMotoIdsProvider.overrideWith((ref) => ['m-bmw', 'm-husq', 'm-shot']),
      ],
      router: _router('/moto/m-husq'),
      after: _detail,
    ),
  ];
}
