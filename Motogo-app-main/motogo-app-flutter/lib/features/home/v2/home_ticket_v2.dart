import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/shell_actions.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/chrome/mg_nav_helpers.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/widgets/pickup_location_link.dart';
import '../../documents/docs_gate_provider.dart';
import '../../reservations/reservation_models.dart';
import '../../sos/sos_provider.dart';
import 'home_state.dart';
import 'home_ticket_checklist.dart';
import 'home_ticket_parts.dart';
import 'home_reveal.dart';

/// Ticket S1–S9 (DESIGN_V2 §5.3 / V22 `.tk`): the one dark hero when a
/// booking needs attention or is coming. 128 photo header with eyebrow +
/// status, dates row, "Tým pro tebe" checklist from existing fields and ONE
/// primary action per state (the same actions the shell FABs / reservation
/// detail already offer). Codes are never shown here — only a way to them.
class HomeTicketV2 extends ConsumerWidget {
  final HomeSnapshot snap;
  const HomeTicketV2({super.key, required this.snap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final r = snap.res;
    final docsOk = ref.watch(docsFabStatusProvider).valueOrNull?.isComplete;
    final sosAllowed = ref.watch(hasActiveRentalProvider);
    final now = DateTime.now();
    void openDetail() {
      if (r != null) mgPushOrGo(context, '/reservations/${r.id}');
    }

    final title = r?.motoName ??
        tr.tr(snap.ticket == HomeTicket.s1 ? 'v2HomeSosTitle' : 'v2HomePayTitle');
    final place = r == null
        ? null
        : homeIsDelivery(r)
            ? (r.pickupAddress ?? r.branchName)
            : r.branchName;
    final meta = [if (place != null && place.trim().isNotEmpty) place.trim(), if (r != null) r.shortId].join(' · ');

    return HomeReveal(
      sessionKey: 'home-ticket',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: MgGradients.hero(rank.aura),
          border: Border.all(color: MgColors.neonA(0.25)),
          boxShadow: MgShadows.dark,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            button: r != null,
            label: '$title. $meta',
            child: MgPress(
              onTap: r == null ? null : openDetail,
              child: SizedBox(
                height: 128,
                child: Stack(fit: StackFit.expand, children: [
                  HomePhoto(url: r?.motoImage),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [MgColors.nightA(0.55), MgColors.nightA(0), MgColors.nightA(0), MgColors.nightA(0.9)],
                        stops: const [0, 0.34, 0.44, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 10,
                    child: _PillRow(left: _eyebrow(tr, now), right: _status(tr, docsOk)),
                  ),
                  Positioned(
                    left: 16,
                    right: 12,
                    bottom: 10,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MgType.h3.copyWith(
                              color: MgColors.onDark,
                              shadows: [Shadow(color: MgColors.black(0.45), blurRadius: 12, offset: const Offset(0, 2))])),
                      if (meta.isNotEmpty)
                        Text(meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MgType.small.copyWith(color: MgColors.onDarkBody)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (r != null) ...[_DatesRow(res: r), const SizedBox(height: 12)],
              HomeTicketChecklist(snap: snap, docsOk: docsOk),
              const SizedBox(height: 16),
              _action(context, ref, tr, sosAllowed),
              if (r != null && !_ctaIsDetail) ...[
                const SizedBox(height: 4),
                Center(
                  child: HomeTextLink(label: tr.tr('v2HomeCtaDetail'), dark: true, onTap: openDetail),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  bool get _ctaIsDetail => switch (snap.ticket) {
        HomeTicket.s5 || HomeTicket.s6 || HomeTicket.s7 || HomeTicket.s8 => true,
        HomeTicket.s4 => snap.res == null || homeIsDelivery(snap.res!),
        HomeTicket.s9 => snap.res == null || snap.res!.returnMethod == 'delivery',
        _ => false,
      };

  TkPill _eyebrow(AppTranslations tr, DateTime now) {
    final r = snap.res;
    switch (snap.ticket) {
      case HomeTicket.s1:
        return TkPill(tr.tr('v2HomeEbSos'), tone: TkPillTone.sos);
      case HomeTicket.s2:
        return TkPill(tr.tr(snap.pending?.verifying == true ? 'v2HomeEbVerify' : 'v2HomeEbPay'),
            tone: TkPillTone.pending);
      case HomeTicket.s7:
        return TkPill(tr.tr('v2HomeEbToday'));
      case HomeTicket.s8:
        final y = r?.dayCount ?? 1;
        final x = r == null ? 1 : (DateTime(now.year, now.month, now.day).difference(tripDay(r.startDate)).inDays + 1).clamp(1, y);
        return TkPill(tr.trArgs('v2HomeEbRiding', {'x': x, 'y': y}));
      case HomeTicket.s9:
        return TkPill(tr.tr('v2HomeEbReturnToday'));
      default:
        final n = r == null ? 0 : homeDaysUntil(r, now);
        return TkPill(n <= 1
            ? tr.tr(n <= 0 ? 'v2HomeEbToday' : 'v2HomeEbTomorrow')
            : tr.trArgs('v2HomeEbInDays', {'n': n, 'days': tr.daysWord(n)}));
    }
  }

  TkPill? _status(AppTranslations tr, bool? docsOk) {
    switch (snap.ticket) {
      case HomeTicket.s1:
      case HomeTicket.s2:
        return null;
      case HomeTicket.s3:
        return TkPill(tr.tr('v2HomePillDocs'), tone: TkPillTone.warn);
      case HomeTicket.s8:
      case HomeTicket.s9:
        return TkPill(tr.tr('homeStatusActive'), tone: TkPillTone.ok);
      default:
        return TkPill(tr.tr('homeStatusUpcoming'),
            tone: docsOk == true ? TkPillTone.ok : TkPillTone.plain, icon: docsOk == true ? MgIcons.check : null);
    }
  }

  Widget _action(BuildContext context, WidgetRef ref, AppTranslations tr, bool sosAllowed) {
    final r = snap.res;
    void detail() {
      if (r != null) mgPushOrGo(context, '/reservations/${r.id}');
    }

    void navigate() {
      if (r == null) return;
      openPickupMap(PickupInfo(name: r.branchName, address: r.branchAddress, lat: r.branchLat, lng: r.branchLng));
    }

    Widget cta(String key, VoidCallback onTap, {String? price}) => MgFabAvoid(
          child: MgCta(label: tr.tr(key), price: price, loop: true, onTap: onTap, arrow: price == null),
        );

    switch (snap.ticket) {
      case HomeTicket.s1:
        return MgFabAvoid(
          kind: MgAvoidKind.sos,
          child: MgBtnSos(label: tr.tr('v2HomeCtaSos'), onTap: () => openPendingSos(context, ref, snap.sos!)),
        );
      case HomeTicket.s2:
        final p = snap.pending!;
        if (p.verifying) {
          return TkPendingBlock(title: tr.tr('psFabVerifying'), text: tr.tr('v2HomeVerifyText'));
        }
        return cta('v2HomeCtaPay', () => openPendingPayment(context, ref, p), price: Money.czk(p.totalPrice));
      case HomeTicket.s3:
        return cta('v2HomeCtaDocs', () => mgPushOrGo(context, Routes.docs));
      case HomeTicket.s4:
        return _ctaIsDetail ? cta('v2HomeCtaDetail', detail) : cta('v2HomeCtaNavigate', navigate);
      case HomeTicket.s6:
        return cta('v2HomeCtaCodes', detail);
      case HomeTicket.s8:
      case HomeTicket.s9:
        final main = snap.ticket == HomeTicket.s9 && !_ctaIsDetail
            ? cta('v2HomeCtaNavigate', navigate)
            : cta('v2HomeCtaDetail', detail);
        if (!sosAllowed) return main;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: main),
            const SizedBox(width: 12),
            TkSosCircle(label: '${tr.tr('homeSosTitle')} · ${tr.tr('homeSosSubtitle')}'),
          ]),
          const SizedBox(height: 8),
          // Today's red SOS bar text (what SOS covers), now next to the circle.
          Text('SOS: ${tr.tr('homeSosTitle')} · ${tr.tr('homeSosSubtitle')}',
              textAlign: TextAlign.end, style: MgType.meta.copyWith(color: MgColors.errDark)),
        ]);
      default:
        return cta('v2HomeCtaDetail', detail);
    }
  }
}

/// Eyebrow left, status right; when both do not fit, each shrinks in
/// proportion to its text (never one pill squeezed to nothing).
class _PillRow extends StatelessWidget {
  final TkPill left;
  final TkPill? right;
  const _PillRow({required this.left, this.right});

  @override
  Widget build(BuildContext context) {
    final r = right;
    if (r == null) return Row(children: [Flexible(child: left)]);
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Flexible(flex: left.text.length + 4, child: left),
      const SizedBox(width: 8),
      Flexible(flex: r.text.length + 6, child: r),
    ]);
  }
}

/// "pá 16. 10. 12:00 → ne 18. 10. · 3 dny".
class _DatesRow extends StatelessWidget {
  final Reservation res;
  const _DatesRow({required this.res});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final pt = res.pickupHm;
    final rt = (res.returnTime ?? '').trim();
    final start = '${tripShortDate(tr, res.startDate)}${pt == null ? '' : ' $pt'}';
    final end = '${tripShortDate(tr, res.endDate)}${rt.length >= 5 ? ' ${rt.substring(0, 5)}' : ''}';
    final days = res.dayCount;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: MgColors.white(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MgColors.white(0.14)),
      ),
      child: Row(children: [
        const MgIcon(MgIcons.calendarCheck, size: 16, color: MgColors.neon),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$start → $end · $days ${tr.daysWord(days)}',
              style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDark))),
        ),
      ]),
    );
  }
}
