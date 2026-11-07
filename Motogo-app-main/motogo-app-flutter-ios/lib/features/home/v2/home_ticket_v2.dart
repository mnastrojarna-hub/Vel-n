import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/shell_actions.dart';
import '../../../core/shell_fabs.dart' show cancelPendingBookingFlow;
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/chrome/mg_nav_helpers.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_hero_photo.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/widgets/pickup_location_link.dart';
import '../../booking/price_calculator.dart' show branchLat, branchLng;
import '../../documents/docs_gate_provider.dart';
import '../../routes/ride_recorder.dart';
import '../../sos/sos_provider.dart';
import 'home_state.dart';
import 'home_ticket_checklist.dart';
import 'home_ticket_parts.dart';
import 'home_ticket_pay_v2.dart';
import 'home_ticket_rows_v2.dart';
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
    // Board Main: "{pobočka} · {samoobsluha | s obsluhou}" (rozvoz = adresa).
    // Číslo rezervace na vlastním řádku pod ním — viditelně a nikdy useknuté
    // (stará karta Domů ho ukazuje, zákazník ho diktuje podpoře).
    final kind = r == null || homeIsDelivery(r)
        ? null
        : r.isSelfService
            ? tr.tr('v2CalcBranchSelf')
            : r.branchType == 'obslužná'
                ? tr.tr('v2CalcBranchStaffed')
                : null;
    final meta = [if (place != null && place.trim().isNotEmpty) place.trim(), if (kind != null) kind].join(' · ');
    final shortId = r?.shortId ?? '';
    final payable = snap.ticket == HomeTicket.s2 && snap.pending?.verifying != true;
    final riding = snap.ticket == HomeTicket.s8 && r != null;

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
            label: '$title. ${[meta, shortId].where((x) => x.isNotEmpty).join(' · ')}',
            child: MgPress(
              onTap: r == null ? null : openDetail,
              // Eyebrow + stav se nevejdou ani zmenšené → pod sebe a fotka o
              // řádek vyšší (francouzsky / velké písmo na úzkém telefonu).
              child: LayoutBuilder(builder: (context, box) {
                final left = _eyebrow(tr, now), right = _status(tr, docsOk);
                final stacked = tkPillsStack(context, box.maxWidth - 24, left, right);
                return SizedBox(
                height: stacked ? 158 : 128,
                child: Stack(fit: StackFit.expand, children: [
                  // Sdílená fotka → detail rezervace (V2 §5.3 Hero).
                  MgHeroPhoto(
                    tag: mgHeroTagRes(r?.id ?? 'none'),
                    enabled: r != null,
                    child: HomePhoto(url: r?.motoImage),
                  ),
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
                    child: TkPillRow(left: left, right: right, stacked: stacked),
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
                        Row(children: [
                          const MgIcon(MgIcons.pin, size: 14, color: MgColors.onDarkBody),
                          const SizedBox(width: 4),
                          Expanded(
                            // Typ pobočky se nikdy neusekne (dlouhé jazyky → 2 řádky).
                            child: Text(meta,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: MgType.small.copyWith(color: MgColors.onDarkBody)),
                          ),
                        ]),
                      if (shortId.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 18),
                          child: Text(shortId,
                              key: const ValueKey('tk-short-id'),
                              maxLines: 1,
                              softWrap: false,
                              style: MgType.tab(MgType.meta.copyWith(color: MgColors.onDarkMeta))),
                        ),
                    ]),
                  ),
                ]),
              );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (riding) ...[
                // Board Main S8: den výpůjčky v kroužku + kam a kdy vrátit.
                TkRideDayRow(res: r, now: now),
                const SizedBox(height: 12),
                const _RecLine(),
              ] else ...[
                if (r != null) ...[TkDatesRow(res: r), const SizedBox(height: 12)],
                // S2 k zaplacení: místo seznamu odpočet (board Main S2).
                if (!payable) HomeTicketChecklist(snap: snap, docsOk: docsOk),
              ],
              const SizedBox(height: 16),
              _action(context, ref, tr, sosAllowed),
              if (r != null && !_ctaIsDetail && !payable) ...[
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
        final hm = r?.pickupHm;
        return TkPill(hm == null ? tr.tr('v2HomeEbToday') : tr.trArgs('v2UxShEbTodayFrom', {'time': hm}));
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
        // Zaplaceno + doklady v pořádku → „Připraveno" (board Main S6).
        if (docsOk == true) return TkPill(tr.tr('v2UxShPillReady'), tone: TkPillTone.ok, icon: MgIcons.check);
        return TkPill(tr.tr('homeStatusUpcoming'), tone: TkPillTone.plain);
    }
  }

  Widget _action(BuildContext context, WidgetRef ref, AppTranslations tr, bool sosAllowed) {
    final r = snap.res;
    void detail() {
      if (r != null) mgPushOrGo(context, '/reservations/${r.id}');
    }

    void navigate() {
      if (r == null) return;
      // Stejné vstupy jako detail rezervace (ResWhenWhereV2): GPS pobočky
      // s náhradní polohou a celá adresa — samotné „Mezná 9" by mapy poslalo
      // do jiné Mezné.
      final full = [r.branchAddress, r.branchCity].where((p) => p != null && p.isNotEmpty).join(', ');
      openPickupMap(PickupInfo(
        name: r.branchName,
        address: full.isEmpty ? r.branchName : full,
        lat: r.branchLat ?? branchLat,
        lng: r.branchLng ?? branchLng,
      ));
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
        return TkPayBlock(
          pending: p,
          cta: cta('v2HomeCtaPay', () => openPendingPayment(context, ref, p), price: Money.czk(p.totalPrice)),
          // Týž postup jako ✕ proužku (potvrzení → zrušení → „Zkusit znovu").
          onCancel: () => cancelPendingBookingFlow(context, ref, p),
        );
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
        final sosLabel = '${tr.tr('homeSosTitle')} · ${tr.tr('homeSosSubtitle')}';
        // Úzký telefon: CTA na celou šířku („BUCHUNGSDETAILS" celé) a SOS
        // kruh pod ním vedle svého vysvětlení; jinak kruh vedle CTA.
        return LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 300) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              main,
              const SizedBox(height: 10),
              Row(children: [
                TkSosCircle(label: sosLabel),
                const SizedBox(width: 12),
                Expanded(child: Text('SOS: $sosLabel', style: MgType.meta.copyWith(color: MgColors.errDark))),
              ]),
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: main),
              const SizedBox(width: 12),
              TkSosCircle(label: sosLabel),
            ]),
            const SizedBox(height: 8),
            // Today's red SOS bar text (what SOS covers), now next to the circle.
            Text('SOS: $sosLabel', textAlign: TextAlign.end, style: MgType.meta.copyWith(color: MgColors.errDark)),
          ]);
        });
      default:
        return cta('v2HomeCtaDetail', detail);
    }
  }
}

/// S8 recording line from the recorder (automatic recording only).
class _RecLine extends ConsumerWidget {
  const _RecLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(rideRecorderProvider);
    if (!rec.recording || rec.manual) return const SizedBox.shrink();
    return TkRecLine(gpsLost: rec.gpsLost, km: rec.liveKm);
  }
}
