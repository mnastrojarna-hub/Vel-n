// Journey rig — every Supabase / GPS / Stripe backed DATA provider the app
// reads, faked from the existing test fakes (test/v2/support) for one start
// state. Availability is NOT faked here: `filteredMotorcyclesProvider`,
// `funnelCandidatesProvider`, `calcFreeMotosProvider` and
// `bookedDatesProvider` run their real code against the fake backend
// (journey_backend.dart answers `check_moto_availability` /
// `get_moto_booked_dates`). A later override of the same provider wins
// (Riverpod keeps the last one), so the state layer comes last.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motogo_app/core/banner_provider.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/pending_sos_fab_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/branches/branches_info_provider.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/document_provider.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:motogo_app/features/payment/payment_provider.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/routes/my_experiences_provider.dart';
import 'package:motogo_app/features/routes/ride_provider.dart';
import 'package:motogo_app/features/shop/shop_provider.dart';

import '../support/fakes_catalog.dart' as cat;
import '../support/fakes_home.dart' show kRides;
import '../support/fakes_profile.dart' show PfDocs, profileOverrides;
import '../support/fakes_profile_sub.dart' show docListOverrides, loyaltyOverrides, messagesOverrides;
import '../support/fakes_reservations.dart' show resOverrides;
import '../support/fakes_routes.dart' show routesOverrides;
import 'journey_states.dart';

class _CsLocale extends LocaleNotifier {
  _CsLocale() {
    state = const Locale('cs');
  }
}

const _card = SavedCard(
    id: 'c1', stripeId: 'pm_1', brand: 'visa', last4: '4242', expMonth: 8, expYear: 2029, holderName: 'Jan Novák', isDefault: true);

/// All overrides for [d]. Bikes = the catalog fixtures: BMW R 1200 GS
/// Adventure (Mezná, staffed, licence A), Husqvarna 701 SM (Velké Němčice,
/// self-service, A2/A), Royal Enfield Shotgun 650 (A2, in service = busy
/// 60 days), Yamaha PW50 (kids' bike).
List<Override> journeyOverrides(JourneyData d, {bool v2 = true}) {
  final list = d.reservations;
  final profile = d.loggedIn ? d.profile : null;
  final level = d.loyalty?.level ?? 1;
  final docsOk = d.gate?.ok ?? false;
  final newUser = d.state == JourneyState.newUserNoDocs;
  return [
    // Layer 1 — area fakes (routes / places, reservation detail parts,
    // profile, messages, documents, loyalty).
    ...routesOverrides(),
    ...resOverrides(list: list, pending: d.pending),
    ...profileOverrides(profile: profile, loyalty: d.loyalty, docs: docsOk ? PfDocs.ok : PfDocs.none, reservations: list, unread: 1),
    ...messagesOverrides(unread: 1),
    ...docListOverrides(empty: list.isEmpty),
    ...loyaltyOverrides(status: d.loyalty),
    // Layer 2 — shell, catalog, booking, payment and the state itself.
    localeProvider.overrideWith((ref) => _CsLocale()),
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(level)),
    rankArcPctProvider.overrideWithValue(50),
    appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: v2)),
    paidAfterRestartProvider.overrideWith((ref) async => null),
    bannerProvider.overrideWithValue(const AsyncData(null)),
    pendingBookingFabProvider.overrideWith((ref) => Stream.value(d.pending)),
    pendingSosFabProvider.overrideWith((ref) => Stream.value(null)),
    profileProvider.overrideWith((ref) async => profile),
    loyaltyStatusProvider.overrideWith((ref) async => d.loggedIn ? d.loyalty : null),
    motorcyclesProvider.overrideWith((ref) => Stream.value(cat.kMotos)),
    reservationsProvider.overrideWith((ref) => Stream.value(list)),
    reservationByIdProvider.overrideWith((ref, id) async {
      for (final r in list) {
        if (r.id == id) return r;
      }
      return null;
    }),
    doorCodesProvider.overrideWith((ref, id) => Stream.value(d.codes[id] ?? const <DoorCode>[])),
    docsVerifiedProvider.overrideWith((ref) async => d.verification),
    docsGateChecklistProvider.overrideWith((ref) async => d.gate),
    docsScreenStatusProvider.overrideWith((ref) async => d.docsStatus),
    docsFabStatusProvider.overrideWith((ref) async => d.docsStatus),
    adminUnreadCountProvider.overrideWithValue(d.loggedIn ? 1 : 0),
    branchesInfoProvider.overrideWith((ref, lang) async => branchesInfoDefaults),
    myRidesProvider.overrideWith((ref) async => newUser ? const [] : kRides),
    mySavedRoutesProvider.overrideWith((ref) async => const []),
    myPlacesProvider.overrideWith((ref) async => const []),
    trailerAvailabilityProvider.overrideWith((ref, r) async => const TrailerAvailability(1, 'tr-1')),
    selfServiceDeliveryEnabledProvider.overrideWith((ref) async => false),
    eshopVisibleProvider.overrideWith((ref) async => false),
    paymentMethodsProvider.overrideWith((ref) async => newUser ? const <SavedCard>[] : const [_card]),
    reservationUpsellEnabledProvider.overrideWith((ref) async => false),
    productsProvider.overrideWith((ref) async => const []),
  ];
}
