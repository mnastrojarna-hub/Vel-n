// Fixtures + provider overrides for the v2 booking form tests (PLAN §5.2):
// the catalog sample bikes (BMW R 1200 GS Adventure Mezná = staffed, the
// Husqvarna 701 SM Velké Němčice = self-service, a kids' bike), rank 3
// Motorkář, a complete profile, a free weekend ≥ 7 days ahead. Every
// Supabase-backed provider the form reads is overridden.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_53_v2_booking_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_53_v2_booking_b.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';

import 'fakes_catalog.dart';

export 'fakes_catalog.dart' show kBmw, kHusq, kKids, kLoyalty3, futureWeekend, registerCatalogStrings;

/// path_provider for the image cache (bike photos fall back to their
/// placeholder in tests — the test HttpClient answers 400).
void mockBookingPathProvider() {
  final dir = Directory.systemTemp.createTempSync('mg_booking_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);
}

/// Until the integration step registers ext_53 in `translations.dart`, the
/// tests merge it themselves (idempotent).
void registerBookingStrings() {
  for (final part in [translationsExt53V2BookingA, translationsExt53V2BookingB]) {
    part.forEach((lang, m) => translations.putIfAbsent(lang, () => {}).addAll(m));
  }
}

/// Complete profile (address + licence valid for years).
const kProfileOk = <String, dynamic>{
  'full_name': 'Jan Novák',
  'license_group': ['A', 'B'],
  'street': 'Mezná 9',
  'city': 'Pelhřimov',
  'zip': '39301',
  'license_number': 'EK123456',
  'license_expiry': '2034-05-01',
};

/// A ready draft for [moto] on the next free weekend.
BookingDraft bookingDraft(
  Motorcycle moto, {
  bool dates = true,
  bool sizes = true,
  bool consents = true,
  bool kids = false,
  String pickupTime = '09:00',
  String pickupMethod = 'store',
  String returnMethod = 'store',
  List<SelectedExtra> extras = const [],
  List<AppliedDiscount> discounts = const [],
  String? notes,
  bool ownGear = false,
}) {
  final (s, e) = futureWeekend();
  return BookingDraft(
    motoId: moto.id,
    motoName: moto.model,
    startDate: dates ? s : null,
    endDate: dates ? e : null,
    pickupTime: pickupTime,
    returnTime: '19:00',
    pickupMethod: pickupMethod,
    returnMethod: returnMethod,
    pickupCity: pickupMethod == 'delivery' ? 'Jihlava' : null,
    pickupAddress: pickupMethod == 'delivery' ? 'Masarykovo náměstí 1' : null,
    extras: extras,
    discounts: discounts,
    notes: notes,
    ownGear: ownGear,
    helmetSize: sizes ? (kids ? 'YM' : 'M') : null,
    glovesSize: sizes ? (kids ? '4–7 let' : 'L') : null,
    jacketSize: sizes ? (kids ? null : 'L') : null,
    pantsSize: sizes ? (kids ? null : 'M') : null,
    consentVop: consents,
    consentGdpr: consents,
    consentKids: consents && kids,
  );
}

/// Overrides of everything the booking form reads.
List<Override> bookingOverrides({
  Motorcycle? moto,
  BookingDraft? draft,
  Map<String, dynamic>? profile = kProfileOk,
  LoyaltyStatus? loyalty = kLoyalty3,
  Object? loyaltyError,
  bool bookedLoading = false,
  Object? bookedError,
  List<BookedDateRange> booked = const [],
  bool trailerFree = true,
  bool selfServiceDelivery = false,
  double pickupFee = 0,
  double pickupKm = 0,
}) {
  return [
    bookingMotoProvider.overrideWith((ref) => moto),
    if (draft != null) bookingDraftProvider.overrideWith((ref) => draft),
    profileProvider.overrideWith((ref) async => profile),
    loyaltyStatusProvider.overrideWith((ref) {
      if (loyaltyError != null) return Future<LoyaltyStatus?>.error(loyaltyError);
      return Future.value(loyalty);
    }),
    reservationsProvider.overrideWith((ref) => Stream.value(const [])),
    bookedDatesProvider.overrideWith((ref, id) {
      if (bookedLoading) return Completer<List<BookedDateRange>>().future;
      if (bookedError != null) return Future<List<BookedDateRange>>.error(bookedError);
      return Future.value(booked);
    }),
    trailerAvailabilityProvider.overrideWith(
        (ref, r) async => trailerFree ? const TrailerAvailability(1, 'tr-1') : const TrailerAvailability(0, null)),
    selfServiceDeliveryEnabledProvider.overrideWith((ref) async => selfServiceDelivery),
    pickupDelivFeeProvider.overrideWith((ref) => pickupFee),
    pickupDistKmProvider.overrideWith((ref) => pickupKm),
  ];
}
