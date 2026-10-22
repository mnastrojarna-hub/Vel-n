// Fixtures + provider overrides for the Profil v2 tests (PLAN §5.2): V22
// sample customer (rank 3 Motorkář, 5 points, licence A, documents
// verified), variants for missing documents, an active rental (SOS), a new
// customer, loading and error. Every Supabase-backed provider is faked.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_55_v2_profile_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_55_v2_profile_b.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/document_provider.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';

import 'fakes_home.dart' show day, kLoyalty3, res;

/// Registers the Profil v2 strings in the global table (idempotent) — the
/// integration step registers them in translations.dart for the app.
void registerProfileStrings() {
  for (final part in [
    translationsExt55V2ProfileA,
    translationsExt55V2ProfileB,
  ]) {
    part.forEach((lang, map) => translations.putIfAbsent(lang, () => {}).addAll(map));
  }
}

const kProfileFull = <String, dynamic>{
  'full_name': 'Jan Novák',
  'email': 'jan.novak@example.cz',
  'phone': '+420 777 123 456',
  'street': 'Masarykova 12',
  'zip': '602 00',
  'city': 'Brno',
  'country': 'Česká republika',
  'date_of_birth': '1990-05-05',
  'id_number': '123456789',
  'license_number': 'EF 123456',
  'license_expiry': '2031-08-31',
  'license_group': ['A', 'B'],
};

const kProfileNew = <String, dynamic>{
  'full_name': 'Petra Svobodová',
  'email': 'petra@example.cz',
};

const kGateMissing = DocsGateChecklist(
  ok: false,
  idFront: true,
  idBack: true,
  passport: false,
  dlFront: true,
  dlBack: false,
  identityOk: true,
  licenseOk: false,
  hasDob: true,
  ageOk: true,
  expiryOk: true,
  groupsOk: true,
);

enum PfDocs { ok, missing, none, unknown }

/// Everything Profil v2 reads, faked.
List<Override> profileOverrides({
  Map<String, dynamic>? profile = kProfileFull,
  bool profileLoading = false,
  bool profileError = false,
  LoyaltyStatus? loyalty = kLoyalty3,
  PfDocs docs = PfDocs.ok,
  List<Reservation> reservations = const [],
  int unread = 2,
  bool eshop = false,
}) =>
    [
      profileProvider.overrideWith((ref) async {
        if (profileLoading) await Completer<void>().future;
        if (profileError) throw Exception('SocketException: Failed host lookup');
        return profile;
      }),
      loyaltyStatusProvider.overrideWith((ref) async => loyalty),
      docsFabStatusProvider.overrideWith((ref) async {
        switch (docs) {
          case PfDocs.unknown:
            await Completer<void>().future;
            return DocsScreenStatus(const DocsVerification(), null);
          case PfDocs.ok:
            return DocsScreenStatus(DocsVerification(idVerifiedAt: day(-30), licenseVerifiedAt: day(-30)), null);
          case PfDocs.missing:
            return DocsScreenStatus(DocsVerification(idVerifiedAt: day(-30)), kGateMissing);
          case PfDocs.none:
            return DocsScreenStatus(const DocsVerification(), null);
        }
      }),
      reservationsProvider.overrideWith((ref) => Stream.value(reservations)),
      adminUnreadCountProvider.overrideWithValue(unread),
      eshopVisibleProvider.overrideWith((ref) async => eshop),
    ];

/// An active rental today (SOS allowed, consents locked).
List<Reservation> activeRental() => [res('a1', status: 'active', from: -1, to: 2)];
