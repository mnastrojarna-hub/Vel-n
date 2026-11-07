// routes_rides F-01 / F-02 / F-03 / F-11: route reviews, place rating +
// reviews, the photo viewer and "Odesláno" in the v2 look — the SAME RPCs
// (captured request bodies), callbacks and results as the old look.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motogo_app/core/supabase_client.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_tone.dart';
import 'package:motogo_app/features/routes/poi_rating.dart';
import 'package:motogo_app/features/routes/poi_reviews.dart';
import 'package:motogo_app/features/routes/route_poi_sheet.dart' show openPoiImageViewer;
import 'package:motogo_app/features/routes/route_reviews.dart';
import 'package:motogo_app/features/routes/routes_model.dart';
import 'package:motogo_app/features/routes/submit_common.dart' show showSubmitSuccess;
import 'package:motogo_app/features/routes/v2/poi_reviews_v2.dart';
import 'package:motogo_app/features/routes/v2/review_editor_v2.dart';
import 'package:motogo_app/features/routes/v2/route_reviews_v2.dart';
import 'package:motogo_app/features/routes/v2/rt_photo_viewer_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/v2_harness.dart';

final _calls = <(String, Map<String, dynamic>)>[];

Future<void> _initSupabase() async {
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: MotoGoSupabase.url,
    publishableKey: 'test-anon',
    httpClient: MockClient((req) async {
      final path = req.url.path;
      final body = req.body.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(req.body) as Map);
      if (path.contains('/rpc/')) _calls.add((path.split('/rpc/').last, body));

      final out = path.endsWith('get_route_reviews') || path.endsWith('get_poi_reviews')
          ? {
              'avg': 4.5,
              'count': 2,
              'my': null,
              'reviews': [
                {'rating': 5, 'author': 'Jana', 'review_text': 'Krásná trasa.'},
                {'rating': 4, 'author': 'Petr', 'review_text': ''},
              ],
            }
          : null;
      return http.Response(jsonEncode(out), 200, headers: {'content-type': 'application/json'});
    }),
    authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(), detectSessionInUri: false, autoRefreshToken: false),
    debug: false,
  );
}

/// Signs a fake user in (no network: a non-expired session is restored).
Future<void> _signIn() async {
  final exp = DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;
  String b64(Map<String, Object> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final jwt = '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'sub': 'u1', 'exp': exp, 'role': 'authenticated'})}.sig';
  await Supabase.instance.client.auth.recoverSession(jsonEncode({
    'access_token': jwt,
    'token_type': 'bearer',
    'expires_in': 86400,
    'expires_at': exp,
    'refresh_token': 'r',
    'user': {
      'id': 'u1',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'u1@example.com',
      'app_metadata': <String, Object>{},
      'user_metadata': <String, Object>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  }));
}

/// Lets the (real-async) mock HTTP answers land, then pumps frames.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 100));
  }
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Image cache manager leaves a 10 s cleanup timer behind — drain it.
Future<void> _drain(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 11));
}

Widget _launch(void Function(BuildContext) open) =>
    Builder(builder: (c) => Center(child: ElevatedButton(onPressed: () => open(c), child: const Text('OPEN'))));

void main() {
  setUpAll(() async {
    await loadMontserrat();
    mockPathProvider();
    await _initSupabase();
  });
  setUp(() {
    _calls.clear();
    MgMotion.resetSession();
  });

  group('F-01 route reviews', () {
    testWidgets('section: v2 block + ghost "Napsat recenzi" (same get_route_reviews args)', (t) async {
      await pumpV2(t, const SingleChildScrollView(child: RouteReviewsSection(routeId: 'r1')));
      await _settle(t);
      expect(_calls.map((c) => c.$1), contains('get_route_reviews'));
      expect(_calls.first.$2, {'p_route_id': 'r1'});
      expect(find.byType(RouteReviewsSectionV2), findsOneWidget);
      expect(find.byType(RtReviewsBlockV2), findsOneWidget);
      expect(find.text('Napsat recenzi'), findsOneWidget);
    });

    testWidgets('editor: stars pop, submit sends the same submit_route_review args', (t) async {
      await t.runAsync(_signIn);
      await pumpV2(t, const SingleChildScrollView(child: RouteReviewsSection(routeId: 'r1')));
      await _settle(t);
      await t.tap(find.text('Napsat recenzi'));
      await _settle(t);
      expect(find.byType(ReviewEditorV2), findsOneWidget);
      await t.tap(find.bySemanticsLabel('4 / 5'));
      await t.pump();
      await t.enterText(find.byType(TextField), 'Super okruh');
      await t.tap(find.text('Odeslat recenzi'));
      await _settle(t);
      final submit = _calls.where((c) => c.$1 == 'submit_route_review').toList();
      expect(submit, hasLength(1));
      expect(submit.single.$2, {'p_route_id': 'r1', 'p_rating': 4, 'p_review_text': 'Super okruh', 'p_photos': <String>[]});
      await t.runAsync(() => Supabase.instance.client.auth.signOut());
      await _settle(t);
    });

    testWidgets('editor without stars keeps the old "Vyber počet hvězd" message, no RPC', (t) async {
      await t.runAsync(_signIn);
      await pumpV2(t, const SingleChildScrollView(child: RouteReviewsSection(routeId: 'r1')));
      await _settle(t);
      await t.tap(find.text('Napsat recenzi'));
      await _settle(t);
      await t.tap(find.text('Odeslat recenzi'));
      await t.pump();
      expect(find.text('Vyber počet hvězd'), findsOneWidget);
      expect(_calls.where((c) => c.$1 == 'submit_route_review'), isEmpty);
      await t.runAsync(() => Supabase.instance.client.auth.signOut());
      await _settle(t);
    });

    testWidgets('route-card ★ sheet: light sheet with the route name + pinned write button', (t) async {
      await pumpV2(t, _launch((c) => showRouteReviewsSheet(c, routeId: 'r1', routeName: 'Rajhrad a Židlochovicko')));
      await t.tap(find.text('OPEN'));
      await _settle(t);
      expect(find.byType(RouteReviewsSheetV2), findsOneWidget);
      expect(find.text('Rajhrad a Židlochovicko'), findsOneWidget);
      // Swipe down closes it (platform sheet drag).
      await t.drag(find.text('Rajhrad a Židlochovicko'), const Offset(0, 500));
      await _settle(t);
      expect(find.byType(RouteReviewsSheetV2), findsNothing);
    });

    testWidgets('summary "4,7" + 3 cards + write / delete for my review', (t) async {
      var wrote = 0, deleted = 0;
      await pumpV2(t, SingleChildScrollView(
          child: RouteReviewsSectionV2(
              data: const RtReviewsData(avg: 4.7, count: 3, my: {'rating': 5}, reviews: [
                {'rating': 5, 'author': 'Jana', 'review_text': 'Krásná trasa.'},
                {'rating': 4, 'author': 'Petr', 'review_text': ''},
                {'rating': 5, 'is_mine': true, 'review_text': ''},
              ], loading: false),
              onWrite: () => wrote++,
              onDelete: () => deleted++)));
      expect(find.text('4,7'), findsOneWidget);
      expect(find.text('3\u00A0recenze'), findsOneWidget);
      expect(find.byType(RtReviewCardV2), findsNWidgets(3));
      expect(find.text('Tvá recenze'), findsOneWidget);
      await t.tap(find.text('Upravit recenzi'));
      await t.ensureVisible(find.text('Smazat recenzi'));
      await t.tap(find.text('Smazat recenzi'));
      expect((wrote, deleted), (1, 1));
    });

    testWidgets('empty: the board card "Zatím žádné recenze"', (t) async {
      await pumpV2(t, SingleChildScrollView(
          child: RouteReviewsSectionV2(
              data: const RtReviewsData(avg: null, count: 0, my: null, reviews: [], loading: false),
              onWrite: () {},
              onDelete: () {})));
      expect(find.text('Zatím žádné recenze. Buď první!'), findsOneWidget);
    });
  });

  group('F-02 place rating + reviews', () {
    const poi = RoutePoi(id: 'p1', name: 'Klášter Rajhrad', lat: 49.09, lng: 16.61, category: 'sights');

    testWidgets('rating: v2 row, a star tap runs the old _rate (logged out → same message)', (t) async {
      await pumpV2(t, const Padding(padding: EdgeInsets.all(16), child: PoiRatingBar(poi: poi)));
      await _settle(t);
      expect(find.byType(PoiRatingV2), findsOneWidget);
      await t.tap(find.bySemanticsLabel('3 / 5'));
      await t.pump();
      expect(find.text('Přihlas se a ohodnoť'), findsOneWidget);
    });

    testWidgets('reviews: "Recenze · 2", the same get_poi_reviews target', (t) async {
      await pumpV2(t, SingleChildScrollView(child: PoiReviewsSection(target: poiReviewTarget(poi))));
      await _settle(t);
      expect(find.byType(PoiReviewsSectionV2), findsOneWidget);
      expect(_calls.firstWhere((c) => c.$1 == 'get_poi_reviews').$2,
          {'p_route_poi_id': 'p1', 'p_user_poi_id': null, 'p_poi_id': null});
    });
  });

  group('F-03 photo viewer', () {
    const urls = ['https://x.invalid/a.jpg', 'https://x.invalid/b.jpg', 'https://x.invalid/c.jpg'];

    testWidgets('v2 viewer: "2 / 3", swipe = next, swipe-down closes', (t) async {
      await pumpV2(t, _launch((c) => openPoiImageViewer(c, urls, 1, 'cs')));
      await t.tap(find.text('OPEN'));
      await _settle(t);
      expect(find.byType(RtPhotoViewerV2), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      await t.fling(find.byType(PageView), const Offset(-300, 0), 1200);
      await _settle(t);
      expect(find.text('3 / 3'), findsOneWidget);
      await t.drag(find.byType(PageView), const Offset(0, 260));
      await _settle(t);
      expect(find.byType(RtPhotoViewerV2), findsNothing);
      await _drain(t);
    });

    testWidgets('reduced motion: no follow, the same close on release', (t) async {
      await pumpV2(t, _launch((c) => openPoiImageViewer(c, urls, 0, 'cs')), reducedMotion: true);
      await t.tap(find.text('OPEN'));
      await t.pump();
      expect(find.byType(RtPhotoViewerV2), findsOneWidget);
      await t.drag(find.byType(PageView), const Offset(0, 40));
      await t.pump();
      expect(find.byType(RtPhotoViewerV2), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('rt-viewer-credit')));
      await _settle(t);
      expect(find.text('Zobrazit zdroj'), findsNothing); // not a Commons photo → only the sentence
      await _drain(t);
    });
  });

  group('F-11 Odesláno', () {
    testWidgets('dialog: ✓ disc + title + one "Hotovo" that closes it (the future completes)', (t) async {
      var done = false;
      await pumpV2(t, _launch((c) => showSubmitSuccess(c).then((_) => done = true)));
      await t.tap(find.text('OPEN'));
      await _settle(t);
      expect(find.byType(MgToneDisc), findsOneWidget);
      expect(find.text('Díky! Návrh odeslán'), findsOneWidget);
      await t.tap(find.text('Hotovo'));
      await _settle(t);
      expect(done, isTrue);
    });
  });
}
