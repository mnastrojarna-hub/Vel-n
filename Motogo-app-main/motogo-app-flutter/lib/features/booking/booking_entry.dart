import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../auth/auth_provider.dart' show profileProvider;
import '../catalog/moto_model.dart';
import 'booking_models.dart';
import 'booking_provider.dart';

/// Start rezervace z vybrané motorky a termínu (PLAN PM-3) — tělo přesunuté
/// BEZE ZMĚNY z tlačítka REZERVOVAT v detailu motorky (`moto_detail_page`):
/// nastaví `bookingMotoProvider`, založí čerstvý `BookingDraft` s velikostmi
/// výbavy z profilu (boty se nepředvyplňují) a otevře `/booking`.
/// Volají ho detail (starý i v2), funnel na Domů a kalkulačka. Čas
/// vyzvednutí se NEpředává (majitel 2026-10-22): volí se jen ve formuláři
/// rezervace — vstupy před ním ukazují výhodu vyzvednutí od 12:00 jen jako
/// informaci.
void startBookingFromSelection(
  BuildContext ctx,
  WidgetRef ref,
  Motorcycle moto,
  DateTime start,
  DateTime end,
) {
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
  ref.read(bookingMotoProvider.notifier).state = moto;
  ref.read(bookingDraftProvider.notifier).state = BookingDraft(
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
  ctx.push(Routes.booking);
}
