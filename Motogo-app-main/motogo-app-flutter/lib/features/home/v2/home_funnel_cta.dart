import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/pending_booking_fab_provider.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../booking/booking_entry.dart';
import '../../booking/booking_quote.dart';
import '../../catalog/catalog_provider.dart';
import '../../catalog/moto_model.dart';
import '../../catalog/v2/catalog_price.dart';
import '../../loyalty/loyalty_provider.dart';
import 'funnel_dates.dart';
import 'funnel_provider.dart';
import 'home_links.dart';
import 'home_offer_provider.dart';

/// The availability pill of an offer bike outside a free range: "Volná
/// dnes" (`availableToday`, as the bike list), else "Volná od 26. 3." from
/// `get_motos_availability_status`, else none. (text, live dot)
(String?, bool) homeOfferAvail(AppTranslations tr, HomeOffer offer, Motorcycle m, Map<String, DateTime> nextFree,
    DateTime today) {
  if (offer.mode == HomeOfferMode.free) return (tr.tr('v2HomeFnFree'), true);
  if (m.availableToday == true) return (tr.tr('v2CatFreeToday'), true);
  final next = nextFree[m.id];
  if (next == null || !next.isAfter(today)) return (null, false);
  return (tr.trArgs('homeOfferFreeFrom', {'date': funnelDate(tr, next)}), false);
}

/// Price shown on an offer card: with free dates "Tvoje cena · n dny" + the
/// booking-form total (`quoteFor`, rank included) + struck list total;
/// otherwise the bike list's "od X Kč/den" (`catCardPrice`, rank included).
({String label, String price, String? unit, String? list}) homeOfferPrice(
    AppTranslations tr, HomeOffer offer, Motorcycle m, LoyaltyStatus? loyalty) {
  final r = offer.range;
  if (offer.mode == HomeOfferMode.free && r != null) {
    final days = r.days;
    final l = loyalty == null || loyalty.percent <= 0 ? null : Money.czk(listQuoteFor(m, r.start, r.end).total);
    return (
      label: tr.trArgs('v2HomeFnPriceFor', {'days': '$days ${tr.daysWord(days)}'}),
      price: Money.czk(quoteFor(m, r.start, r.end, loyalty: loyalty).total),
      unit: null,
      list: l,
    );
  }
  final p = catCardPrice(tr, m, null, null, loyalty);
  return (label: p.label, price: p.value, unit: p.unit, list: p.struck);
}

/// "Nothing free in these dates" heading of the offer card (closed branch
/// told apart from booked out).
Widget homeOfferNoneBanner(AppTranslations tr, HomeOffer offer) => MgStateBanner(
      key: const ValueKey('home-offer-none'),
      tone: MgTone.info,
      dark: true,
      icon: MgIcons.calendarX,
      title: tr.tr(offer.closed ? 'homeOfferClosedTitle' : 'homeOfferNoneTitle'),
      text: tr.tr(offer.closed ? 'homeOfferClosedText' : 'homeOfferNoneText'),
    );

/// The card's one action for [offer] and its centred bike [m].
/// [pick] opens the date sheet for that bike; [errs] are the detail's
/// licence / overlap warnings for a free range (the button turns ghost).
Widget homeOfferAction(
  BuildContext context,
  WidgetRef ref, {
  required HomeOffer offer,
  required Motorcycle? m,
  required List<String> errs,
  required VoidCallback pick,
  required String? price,
}) {
  final tr = t(context);
  final range = offer.range;
  final reserveLabel = tr.tr(range == null ? 'homeOfferPickDates' : 'v2HomeCtaReserve');
  switch (offer.mode) {
    case HomeOfferMode.loading:
      return MgCta(label: reserveLabel, onTap: null, enabled: false);
    case HomeOfferMode.error:
      return MgBtnGhostDark(
        label: tr.tr('eoRetry'),
        onTap: () {
          ref.invalidate(motorcyclesProvider);
          if (range != null) ref.invalidate(funnelCandidatesProvider(range));
        },
      );
    case HomeOfferMode.noBikes:
      return MgBtnGhostDark(label: tr.tr('homeOfferAllBikes'), onTap: () => homeOpenMotorky(context, ref));
    case HomeOfferMode.noDates:
    case HomeOfferMode.noneFree:
    case HomeOfferMode.free:
      break;
  }
  final pb = ref.watch(pendingBookingFabProvider).valueOrNull;
  // K4-05: an unpaid booking waits in the pay strip → "Zaplatit" first.
  final unpaid = pb != null && !pb.isExpired && !pb.verifying;
  final free = offer.mode == HomeOfferMode.free && m != null && range != null;
  final label = free ? reserveLabel : tr.tr(offer.mode == HomeOfferMode.noneFree ? 'v2HomeFnPickOther' : 'homeOfferPickDates');
  final VoidCallback onTap = free ? () => startBookingFromSelection(context, ref, m, range.start, range.end) : pick;
  // J3: with a warning the bike's action stays (same tap) but is secondary.
  return MgFabAvoid(
    child: errs.isNotEmpty || unpaid
        ? MgBtnGhostDark(
            key: const ValueKey('home-funnel-reserve-ghost'),
            label: free && price != null ? '${label.toUpperCase()} · $price' : label,
            height: 60,
            onTap: onTap,
          )
        : MgCta(
            key: ValueKey('home-offer-cta-${offer.mode.name}'),
            label: label,
            price: free ? price : null,
            loop: true,
            size: MgCtaSize.lg60,
            onTap: onTap,
          ),
  );
}
