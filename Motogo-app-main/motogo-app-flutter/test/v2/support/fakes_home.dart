// Fixtures + provider overrides for the Home v2 tests (PLAN §5.2): V22
// sample data (rank 3 Motorkář, licence A, Husqvarna 701 SM VN, BMW R 1200
// GS Adventure Mezná, Shotgun 650), every Supabase-backed provider faked.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:motogo_app/core/banner_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_51_v2_home_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_51_v2_home_b.dart';
import 'package:motogo_app/core/i18n/translations_ext_51_v2_home_c.dart';
import 'package:motogo_app/core/i18n/translations_ext_51_v2_home_d.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/pending_sos_fab_provider.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/branches/branches_info_provider.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/document_provider.dart';
import 'package:motogo_app/features/home/v2/funnel_provider.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/routes/my_experiences_provider.dart';
import 'package:motogo_app/features/routes/ride_model.dart';
import 'package:motogo_app/features/routes/ride_provider.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/routes_model.dart';
import 'package:motogo_app/features/routes/routes_provider.dart';

/// path_provider for the image cache (network photos fall back to their
/// placeholder in tests — the test HttpClient answers 400).
void mockPathProvider() {
  final dir = Directory.systemTemp.createTempSync('mg_home_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);
}

/// Registers the Home v2 strings in the global table (idempotent) — the
/// integration step registers them in translations.dart for the app.
void registerHomeStrings() {
  for (final part in [translationsExt51V2HomeA, translationsExt51V2HomeB, translationsExt51V2HomeC, translationsExt51V2HomeD]) {
    part.forEach((lang, map) => translations.putIfAbsent(lang, () => {}).addAll(map));
  }
}

DateTime get _today {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime day(int offset) => DateTime(_today.year, _today.month, _today.day + offset);

const _prices = DayPrices(mon: 2811, tue: 2811, wed: 2811, thu: 2811, fri: 3815, sat: 4223, sun: 4223);
const _pricesH = DayPrices(mon: 3543, tue: 3543, wed: 3543, thu: 3543, fri: 4620, sat: 4997, sun: 4997);
const _pricesS = DayPrices(mon: 1833, tue: 1833, wed: 1833, thu: 1833, fri: 2401, sat: 2581, sun: 2581);

final kMotos = <Motorcycle>[
  const Motorcycle(
      id: 'm-bmw', model: 'BMW R 1200 GS Adventure', brand: 'BMW', category: 'cestovni', licenseGroups: ['A'],
      branchId: '11111111-1111-1111-1111-111111111111', branchName: 'Mezná', branchType: 'obslužná',
      branchIsOpen: true, prices: _prices, availableToday: true),
  const Motorcycle(
      id: 'm-husq', model: 'Husqvarna 701 SM', brand: 'Husqvarna', category: 'supermoto', licenseGroups: ['A'],
      branchId: '22222222-2222-2222-2222-222222222222', branchName: 'Velké Němčice', branchType: 'samoobslužná',
      branchIsOpen: true, prices: _pricesH, availableToday: true),
  const Motorcycle(
      id: 'm-shot', model: 'Royal Enfield Shotgun 650', brand: 'Royal Enfield', category: 'chopper', licenseGroups: ['A2'],
      branchId: '11111111-1111-1111-1111-111111111111', branchName: 'Mezná', branchType: 'obslužná',
      branchIsOpen: true, prices: _pricesS, availableToday: false),
];

Reservation res(
  String id, {
  required String status,
  String pay = 'paid',
  required int from,
  required int to,
  bool self = true,
  bool delivery = false,
  int? rating,
  DateTime? ratedAt,
  DateTime? created,
  String bike = 'Husqvarna 701 SM',
}) =>
    Reservation(
      id: '${id}aaaaaaaa-1111-2222-3333-444455556666',
      motoId: 'm-husq',
      motoName: bike,
      category: 'supermoto',
      branchName: self ? 'Velké Němčice' : 'Mezná',
      branchAddress: self ? 'Boudky, 691 63 Velké Němčice' : 'Mezná 9, 393 01 Pelhřimov',
      branchType: self ? 'samoobslužná' : 'obslužná',
      branchLat: 49.0043,
      branchLng: 16.6721,
      status: status,
      paymentStatus: pay,
      startDate: day(from),
      endDate: day(to),
      pickupTime: '12:00:00',
      returnTime: '19:00:00',
      pickupMethod: delivery ? 'delivery' : 'branch',
      pickupAddress: delivery ? 'Masarykova 12, 602 00 Brno' : null,
      totalPrice: 12027,
      loyaltyDiscountAmount: 361,
      rating: rating,
      ratedAt: ratedAt,
      createdAt: created ?? DateTime.now().subtract(const Duration(days: 9)),
    );

const kLoyalty3 = LoyaltyStatus(
  level: 3,
  percent: 3,
  rankName: 'Motorkář',
  colorHex: '#4ADE80',
  qualifyingCount: 5,
  nextRankName: 'Stálý jezdec',
  nextPercent: 4,
  bookingsToNext: 1,
);

LoyaltyStatus loyaltyAt(int level) => LoyaltyStatus(
      level: level,
      percent: level,
      rankName: '',
      colorHex: '#000000',
      qualifyingCount: 2 * level - 1,
      nextRankName: level < 20 ? 'Další' : null,
      nextPercent: level < 20 ? level + 1 : null,
      bookingsToNext: level < 20 ? 1 : null,
    );

class FakeRecorder extends RideRecorderNotifier {
  final RideRecorderState initial;
  FakeRecorder(super.ref, this.initial) {
    state = initial;
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (mounted) state = initial;
    });
  }
}

class FakeRoutes extends RoutesDataNotifier {
  @override
  Future<RoutesData> build() async => RoutesData(routes: kRoutes, branches: const {});
}

class FakePois extends CatalogPoisNotifier {
  @override
  Future<List<RoutePoi>> build() async => const [];
}

final kRoutes = <RouteItem>[
  RouteItem(id: 'rt1', name: 'Rajhrad a Židlochovicko', distanceKm: 40, durationMin: 55, difficulty: 'easy',
      waypoints: const [LatLng(49.09, 16.60), LatLng(49.03, 16.62), LatLng(49.00, 16.68), LatLng(49.06, 16.66)]),
  RouteItem(id: 'rt2', name: 'Vodní krásy: Věstonická nádrž a okolí', distanceKm: 170, durationMin: 290, difficulty: 'medium',
      waypoints: const [LatLng(48.95, 16.60), LatLng(48.87, 16.63), LatLng(48.85, 16.72), LatLng(48.93, 16.70)]),
  RouteItem(id: 'rt3', name: 'Za historií: Synagoga v Dolních Kounicích a okolí', distanceKm: 122, durationMin: 174, difficulty: 'easy',
      waypoints: const [LatLng(49.07, 16.47), LatLng(49.12, 16.40), LatLng(49.02, 16.40)]),
];

final kRides = <UserRide>[
  UserRide(id: 'ride1', bookingId: 'b8', motoName: 'BMW R 1200 GS', name: 'Vysočina okruh', startedAt: day(-3), distanceKm: 182.4,
      track: const [LatLng(49.40, 15.22), LatLng(49.45, 15.30), LatLng(49.42, 15.40), LatLng(49.38, 15.28)]),
  UserRide(id: 'ride2', name: 'Večerní vyjížďka', startedAt: day(-8), distanceKm: 46.1,
      track: const [LatLng(49.19, 16.60), LatLng(49.22, 16.66), LatLng(49.17, 16.70)]),
];

/// Everything Home v2 reads, faked. [reservations] etc. pick the state.
List<Override> homeOverrides({
  List<Reservation> reservations = const [],
  PendingBooking? pending,
  PendingSosReplacement? sos,
  bool docsOk = true,
  LoyaltyStatus? loyalty = kLoyalty3,
  bool loyaltyFails = false,
  int unread = 1,
  RideRecorderState recorder = const RideRecorderState(),
  List<Motorcycle> funnel = const [],
  bool funnelLoading = false,
  bool funnelError = false,
  bool banner = true,
  bool resLoading = false,
}) =>
    [
      reservationsProvider.overrideWith((ref) => resLoading ? StreamController<List<Reservation>>().stream : Stream.value(reservations)),
      pendingBookingFabProvider.overrideWith((ref) => Stream.value(pending)),
      pendingSosFabProvider.overrideWith((ref) => Stream.value(sos)),
      docsFabStatusProvider.overrideWith((ref) async => DocsScreenStatus(
          docsOk ? DocsVerification(idVerifiedAt: day(-30), licenseVerifiedAt: day(-30)) : const DocsVerification(),
          null)),
      profileProvider.overrideWith((ref) async => {
            'full_name': 'Jan Novák',
            'license_group': ['A'],
            'date_of_birth': '1990-05-05',
          }),
      loyaltyStatusProvider.overrideWith((ref) async {
        if (loyaltyFails) return null;
        return loyalty;
      }),
      adminMessagesProvider.overrideWith((ref) => Stream.value([
            for (var i = 0; i < unread; i++)
              AdminMessage(id: 'msg$i', title: 'Sezóna 2027 je otevřená', type: i == 0 ? 'voucher' : 'info', createdAt: DateTime.now()),
          ])),
      bannerProvider.overrideWithValue(AsyncData(banner
          ? const BannerData(
              enabled: true,
              text: '» V zimním období od 1.11.2026 do 25.3.2027 zavřeno.',
              bg: Color(0xFF0E2A1C),
              color: Color(0xFF74FB71))
          : null)),
      motorcyclesProvider.overrideWith((ref) => Stream.value(kMotos)),
      funnelCandidatesProvider.overrideWith((ref, range) async {
        if (funnelLoading) await Completer<void>().future;
        if (funnelError) throw Exception('offline');
        return funnel;
      }),
      rideRecorderProvider.overrideWith((ref) => FakeRecorder(ref, recorder)),
      myRidesProvider.overrideWith((ref) async => kRides),
      mySavedRoutesProvider.overrideWith((ref) async => const [SavedRoute(id: 's1', name: 'Moje okruh')]),
      myPlacesProvider.overrideWith((ref) async => const [VisitedPlace(id: 'p1', name: 'Hrad Pernštejn')]),
      routesDataProvider.overrideWith(FakeRoutes.new),
      catalogPoisProvider.overrideWith(FakePois.new),
      branchesInfoProvider.overrideWith((ref, lang) async => branchesInfoDefaults),
      googleReviewUrlProvider.overrideWith((ref) async => kGoogleReviewFallbackUrl),
    ];
