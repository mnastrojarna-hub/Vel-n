// Fixtures + provider overrides for the v2 catalog / detail / calculator
// tests (PLAN §5.2): V22 sample bikes (BMW R 1200 GS Adventure list pá–ne
// 3 514 + 4 882 + 3 865 = 12 261 Kč, Husqvarna 701 SM, Shotgun 650, a
// kids' bike), rank 3 Motorkář, two branches. No network: no images, no
// videos, every provider the screens read is overridden.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motogo_app/core/banner_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_52_v2_catalog_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_52_v2_catalog_b.dart';
import 'package:motogo_app/core/i18n/translations_ext_52_v2_catalog_c.dart';
import 'package:motogo_app/core/i18n/translations_ext_52_v2_catalog_d.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';

/// Until the integration step registers ext_52 in `translations.dart`, the
/// tests merge it themselves (idempotent).
void registerCatalogStrings() {
  for (final part in [
    translationsExt52V2CatalogA,
    translationsExt52V2CatalogB,
    translationsExt52V2CatalogC,
    translationsExt52V2CatalogD,
  ]) {
    part.forEach((lang, m) => translations.putIfAbsent(lang, () => {}).addAll(m));
  }
}

const _mezna = 'b-mezna';
const _vn = 'b-vn';

Motorcycle _moto({
  required String id,
  required String model,
  required String branch,
  required String category,
  required List<String> lic,
  required DayPrices prices,
  int? kw,
  int? cc,
  int? kg,
  int? seat,
  int? nm,
  double? tank,
  bool? today,
  int? maxDays,
  String? status = 'active',
  String? description,
}) =>
    Motorcycle(
      id: id,
      model: model,
      category: category,
      licenseGroups: lic,
      powerKw: kw,
      powerHp: kw == null ? null : (kw * 1.36).round(),
      engineCc: cc,
      engineType: cc == null ? null : 'dvouválec',
      transmission: '6 st.',
      drivetrain: 'chain',
      weightKg: kg,
      seatHeightMm: seat,
      torqueNm: nm,
      fuelTankL: tank,
      fuelConsumptionL100km: 4.9,
      hasAbs: true,
      hasAsc: false,
      description: description,
      status: status,
      branchId: branch,
      branchName: branch == _mezna ? 'Mezná' : 'Velké Němčice',
      branchCity: branch == _mezna ? 'Pelhřimov' : 'Velké Němčice',
      branchType: branch == _mezna ? 'obslužná' : 'samoobslužná',
      branchIsOpen: true,
      maxRentalDays: maxDays,
      prices: prices,
      availableToday: today,
    );

final kBmw = _moto(
  id: 'm-bmw',
  model: 'BMW R 1200 GS Adventure',
  branch: _mezna,
  category: 'cestovni',
  lic: const ['A'],
  kw: 92,
  cc: 1170,
  kg: 260,
  seat: 890,
  nm: 125,
  tank: 30,
  today: true,
  prices: const DayPrices(mon: 2811, tue: 2811, wed: 2811, thu: 2811, fri: 3514, sat: 4882, sun: 3865),
  description: 'Cestovní enduro pro dlouhé výlety i lehký terén. Velká nádrž, pohodlná pozice a elektronika, '
      'která ti pomůže na mokru i na šotolině. Ideální na víkend po Vysočině i na delší cestu do Alp.\n\n'
      'Motorka je pravidelně servisovaná a připravená k jízdě.',
);

final kHusq = _moto(
  id: 'm-husq',
  model: 'Husqvarna 701 Supermoto',
  branch: _vn,
  category: 'supermoto',
  lic: const ['A2', 'A'],
  kw: 55,
  cc: 693,
  kg: 147,
  seat: 890,
  today: false,
  prices: const DayPrices(mon: 3543, tue: 3543, wed: 3543, thu: 3543, fri: 3600, sat: 4100, sun: 3900),
);

final kShotgun = _moto(
  id: 'm-shot',
  model: 'Royal Enfield Shotgun 650',
  branch: _mezna,
  category: 'chopper',
  lic: const ['A2'],
  kw: 34,
  cc: 648,
  kg: 240,
  seat: 795,
  maxDays: 30,
  status: 'maintenance',
  prices: const DayPrices(mon: 1833, tue: 1833, wed: 1833, thu: 1833, fri: 1990, sat: 2190, sun: 2190),
);

final kKids = _moto(
  id: 'm-kid',
  model: 'Yamaha PW50',
  branch: _mezna,
  category: 'detske',
  lic: const ['N'],
  kw: 2,
  prices: const DayPrices(mon: 600, tue: 600, wed: 600, thu: 600, fri: 650, sat: 650, sun: 650),
);

final kMotos = [kBmw, kHusq, kShotgun, kKids];

/// Rank 3 Motorkář (3 %), 5 points.
const kLoyalty3 = LoyaltyStatus(
  level: 3,
  percent: 3,
  rankName: 'Motorkář',
  colorHex: '#37CF63',
  qualifyingCount: 5,
  nextRankName: 'Stálý jezdec',
  nextPercent: 4,
  bookingsToNext: 1,
);

/// Next Friday → Sunday at least a week ahead (never in the past).
(DateTime, DateTime) futureWeekend() {
  final now = DateTime.now();
  final add = ((5 - now.weekday) % 7) + 7;
  final s = DateTime(now.year, now.month, now.day + add);
  return (s, DateTime(s.year, s.month, s.day + 2));
}

/// Overrides of everything the catalog screens read.
List<Override> catalogOverrides({
  List<Motorcycle>? motos,
  Object? motosError,
  bool motosLoading = false,
  List<Motorcycle>? filtered,
  Object? filteredError,
  bool filteredLoading = false,
  CatalogFilter filter = const CatalogFilter(),
  LoyaltyStatus? loyalty = kLoyalty3,
  Object? loyaltyError,
  Map<String, List<BookedDateRange>> booked = const {},
  bool bookedLoading = false,
  Object? bookedError,
  List<Motorcycle>? free,
  CalcState? calc,
  BannerData? banner,
  Map<String, dynamic>? profile,
  List<Reservation> reservations = const [],
}) {
  final all = motos ?? kMotos;
  return [
    motorcyclesProvider.overrideWith((ref) {
      if (motosLoading) return const Stream<List<Motorcycle>>.empty();
      if (motosError != null) return Stream<List<Motorcycle>>.error(motosError);
      return Stream.value(all);
    }),
    filteredMotorcyclesProvider.overrideWith((ref) {
      if (filteredLoading) return Completer<List<Motorcycle>>().future;
      if (filteredError != null) return Future<List<Motorcycle>>.error(filteredError);
      return Future.value(filtered ?? all);
    }),
    catalogFilterProvider.overrideWith((ref) => filter),
    loyaltyStatusProvider.overrideWith((ref) {
      if (loyaltyError != null) return Future<LoyaltyStatus?>.error(loyaltyError);
      return Future.value(loyalty);
    }),
    bookedDatesProvider.overrideWith((ref, id) {
      if (bookedLoading) return Completer<List<BookedDateRange>>().future;
      if (bookedError != null) return Future<List<BookedDateRange>>.error(bookedError);
      return Future.value(booked[id] ?? const <BookedDateRange>[]);
    }),
    calcFreeMotosProvider.overrideWith((ref, k) => Future.value(free ?? all.where((m) => m.id != 'm-shot').toList())),
    if (calc != null) calcStateProvider.overrideWith((ref) => _FixedCalc(calc)),
    profileProvider.overrideWith((ref) async => profile ?? {'license_group': ['A', 'B']}),
    reservationsProvider.overrideWith((ref) => Stream.value(reservations)),
    bannerProvider.overrideWithValue(AsyncData(banner)),
  ];
}

class _FixedCalc extends CalcStateNotifier {
  _FixedCalc(CalcState s) {
    state = s;
  }
}
