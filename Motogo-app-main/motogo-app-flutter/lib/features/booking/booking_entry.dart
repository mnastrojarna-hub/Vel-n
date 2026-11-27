import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/booking_address_carry.dart' show HandoverChoice;
import '../../core/router.dart';
import '../../core/v2/flag/v2_scope.dart';
import '../auth/auth_provider.dart' show profileProvider;
import '../catalog/catalog_provider.dart' show catalogFilterProvider;
import '../catalog/moto_model.dart';
import '../payment/payment_provider.dart' show lastConfirmedBookingProvider;
import 'booking_models.dart';
import 'booking_provider.dart';
import 'v2/booking_carry_v2.dart';

/// Start rezervace z vybrané motorky a termínu (PLAN PM-3) — tělo přesunuté
/// BEZE ZMĚNY z tlačítka REZERVOVAT v detailu motorky (`moto_detail_page`):
/// nastaví `bookingMotoProvider`, založí čerstvý `BookingDraft` s velikostmi
/// výbavy z profilu (boty se nepředvyplňují) a otevře `/booking`.
/// Volají ho detail (starý i v2), funnel na Domů a kalkulačka. Čas
/// vyzvednutí se NEpředává (majitel 2026-10-22): volí se jen ve formuláři
/// rezervace — vstupy před ním ukazují výhodu vyzvednutí od 12:00 jen jako
/// informaci.
///
/// v2 vzhled (majitel 2026-10-22, „nic nevyplňovat dvakrát“): rozpracovaný
/// draft se NEPŘEPISUJE — viz [carryBookingDraft] — pokud patří stejnému
/// účtu ([bookingDraftOwnerProvider]). Starý vzhled beze změny.
///
/// [handover] (jen v2, majitel 2026-11-27) = místo předání zvolené
/// v kalkulačce „Spočítat cenu“: způsob, adresy i cena/km obou stran se
/// zapíšou do draftu a do providerů formuláře — formulář se otevře
/// předvyplněný a všechno si znovu ověří sám (zámek samoobsluhy, +6 h,
/// obsazenost). null = dosavadní chování.
void startBookingFromSelection(
  BuildContext ctx,
  WidgetRef ref,
  Motorcycle moto,
  DateTime start,
  DateTime end, {
  HandoverChoice? handover,
}) {
  // Předvyplň velikosti výbavy z minulé rezervace
  // (profiles.gear_sizes.rider) — zákazník je nemusí lovit z paměti.
  final gs = ref.read(profileProvider).valueOrNull?['gear_sizes'];
  final rider = (gs is Map ? gs['rider'] : null) as Map?;
  // „Vlastní výbava" z minulé rezervace — předzaškrtne toggle.
  final riderOwn = gs is Map && gs['rider_own'] == true;
  String? rg(String k) {
    final v = rider?[k];
    return (v is String && v.trim().isNotEmpty) ? v : null;
  }
  final fresh = BookingDraft(
    motoId: moto.id,
    motoName: moto.model,
    motoImage: moto.displayImage,
    startDate: start,
    endDate: end,
    ownGear: riderOwn,
    helmetSize: rg('helmet'),
    glovesSize: rg('gloves'),
    jacketSize: rg('jacket'),
    pantsSize: rg('pants'),
    // Boty se NEpředvyplňují: jsou placený doplněk volený dlaždicí
    // („Boty řidiče"), formulář předvyplněnou velikost nikde
    // neukazoval, ale payment_screen ji zapisoval do
    // bookings.boots_size → Velín ukazoval boty, které si zákazník
    // nevybral (incident 2026-09-28).
  );
  final foreign = bookingDraftForeign(ref);
  // Komu draft patří (v2 ho jinému účtu nepřenese) — i ve starém vzhledu,
  // aby přepnutí kill-switche nepřeneslo draft odhlášeného účtu.
  ref.read(bookingDraftOwnerProvider.notifier).state = bookingSessionUid();
  if (!MgV2.peek(ctx)) {
    ref.read(bookingMotoProvider.notifier).state = moto;
    ref.read(bookingDraftProvider.notifier).state = fresh;
    ctx.push(Routes.booking);
    return;
  }
  final confirmed = ref.read(lastConfirmedBookingProvider);
  final (carried, dropFees) = _entryCarry(ref.read, moto, fresh, foreign: foreign);
  // Nový / jinde předaný draft: ceny přistavení a odvozu z minulé adresy
  // by jinak naskočily ke zvolení „na adresu“ bez adresy.
  if (dropFees) {
    for (final p in [pickupDelivFeeProvider, pickupDistKmProvider, returnDelivFeeProvider, returnDistKmProvider]) {
      ref.read(p.notifier).state = 0;
    }
  }
  // Místo předání z kalkulačky = poslední výslovná volba zákazníka: platí
  // pro obě strany i proti rozpracovanému draftu (i výslovné „na pobočce“).
  final next = handover == null ? carried : handover.applyTo(carried);
  if (handover != null) {
    ref.read(pickupDelivFeeProvider.notifier).state = handover.pickupFee;
    ref.read(pickupDistKmProvider.notifier).state = handover.pickupKm;
    ref.read(returnDelivFeeProvider.notifier).state = handover.returnFee;
    ref.read(returnDistKmProvider.notifier).state = handover.returnKm;
  }
  final f = ref.read(catalogFilterProvider);
  ref.read(bookingDraftSeedMarkProvider.notifier).state = confirmed;
  ref.read(bookingEntryFilterProvider.notifier).state = (f.startDate, f.endDate);
  ref.read(bookingMotoProvider.notifier).state = moto;
  ref.read(bookingDraftProvider.notifier).state = next;
  ctx.push(Routes.booking);
}

/// Čtení providerů: `ref.read` (akce) nebo `ref.watch` (build).
typedef BookingRead = T Function<T>(ProviderListenable<T> provider);

/// v2 vstup: draft, který formulář pro [moto] dostane (rozpracovaný se
/// nepřepisuje — [carryBookingDraft]), a zda se zahazují ceny přistavení a
/// odvozu z minulé adresy. Zaplacená rezervace mezitím NEBO draft jiného účtu
/// ([foreign]: odhlášení mimo profil — chyba platby, vypršelé přihlášení) →
/// čerstvý draft.
(BookingDraft, bool) _entryCarry(BookingRead read, Motorcycle moto, BookingDraft fresh, {required bool foreign}) {
  final prev = read(bookingDraftProvider);
  final prevMoto = read(bookingMotoProvider);
  final submitted = read(lastConfirmedBookingProvider) != read(bookingDraftSeedMarkProvider) || foreign;
  final next = carryBookingDraft(prev: prev, prevMoto: prevMoto, moto: moto, fresh: fresh, submitted: submitted);
  return (next, identical(next, fresh) || carryDropsDelivery(prev, prevMoto, moto));
}

/// Místo předání, se kterým by formulář pro [moto] TEĎ otevřel bez nové
/// volby — stejná pravidla jako [startBookingFromSelection] ve v2
/// (rozpracovaná rezervace téhož účtu: stejná motorka, nebo jiná ze stejné
/// pobočky). Kalkulačka ho ukazuje, dokud zákazník nezvolí jinak, takže
/// nikdy neukáže jiné předání ani nižší cenu, než jaké pak ukáže formulář.
/// Nic nezapisuje.
HandoverChoice bookingEntryHandover(BookingRead read, Motorcycle moto) {
  final (next, dropFees) =
      _entryCarry(read, moto, BookingDraft(motoId: moto.id), foreign: bookingDraftForeignOf(read(bookingDraftOwnerProvider)));
  double fee(StateProvider<double> p) => dropFees ? 0 : read(p);
  return HandoverChoice.of(
    next,
    pickupFee: fee(pickupDelivFeeProvider),
    pickupKm: fee(pickupDistKmProvider),
    returnFee: fee(returnDelivFeeProvider),
    returnKm: fee(returnDistKmProvider),
  );
}

/// [bookingEntryHandover] pro `build`: přepočítá se s draftem formuláře, ale
/// posluchače (kalkulačku pod otevřeným formulářem) budí jen změna místa
/// předání nebo jeho ceny.
final bookingEntryHandoverProvider = Provider.autoDispose
    .family<HandoverChoice, Motorcycle>((ref, moto) => bookingEntryHandover(ref.watch, moto));
