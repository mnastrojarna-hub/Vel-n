import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/gestures/mg_one_step.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../auth/auth_provider.dart';
import '../../catalog/catalog_provider.dart';
import '../../catalog/v2/catalog_text.dart' show catLicenceFails, catRangeErrorsV2;
import '../../catalog/moto_model.dart';
import '../../loyalty/loyalty_provider.dart';
import '../../routes/ride_recorder.dart';
import '../nickname_provider.dart';
import 'funnel_carousel_v2.dart';
import 'funnel_provider.dart';
import 'home_date_sheet_v2.dart';
import 'home_funnel_cta.dart';
import 'home_funnel_parts.dart';
import 'home_links.dart';
import 'home_offer_provider.dart';
import 'home_reveal.dart';

/// Home funnel "Tvoje příští jízda" (S0 / S10, DESIGN_V21 §4 + V22 §2.4 #4):
/// photo-led dark card. No dates (owner v5.0.1: nothing preselected) =
/// every bike the customer may ride, "od X Kč/den" and "Volná dnes / od"
/// + "Vybrat termín" (that bike's calendar); dates = EVERY bike free in
/// them, your price from the SAME price engine the booking form uses and
/// the looping CTA "REZERVOVAT · {cena}" → the existing booking start
/// (PM-3); nothing free = the bikes with "Volná od", why (closed / booked
/// out) and "Vybrat jiný termín". The order changes on every visit.
/// The dates are the ones the customer gave anywhere (`homeGiveDates`):
/// a pick here also fills Motorky, and the bike detail opens with them.
class HomeFunnelV2 extends ConsumerStatefulWidget {
  const HomeFunnelV2({super.key});

  @override
  ConsumerState<HomeFunnelV2> createState() => _HomeFunnelV2State();
}

class _HomeFunnelV2State extends ConsumerState<HomeFunnelV2> {
  /// One bike per swipe, however fast (owner v5.0.1).
  final MgSwipeAnchor _swipe = MgSwipeAnchor();

  PageController? _pc;
  Object? _pcKey;
  AppLifecycleListener? _life;
  bool _paused = false;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    // Nový den (půlnoc / návrat do appky): termín, který už začal, zmizí.
    // v5.0.1: po pauze (appka na pozadí) nové pořadí motorek nabídky.
    _life = AppLifecycleListener(onPause: () => _paused = true, onResume: _resumed);
    _armMidnight();
  }

  @override
  void dispose() {
    _life?.dispose();
    _midnight?.cancel();
    _pc?.dispose();
    super.dispose();
  }

  void _armMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), _syncDay);
  }

  void _resumed() {
    _syncDay();
    if (!mounted || !_paused) return;
    _paused = false;
    // Jen když je Domů vidět: otevřený detail motorky si po „Zpět" najde
    // tutéž motorku.
    if (ModalRoute.of(context)?.isCurrent ?? true) {
      ref.read(homeOfferSeedProvider.notifier).state = homeOfferNewSeed();
    }
  }

  void _syncDay() {
    if (!mounted) return;
    final day = funnelDay(DateTime.now());
    final today = ref.read(funnelTodayProvider.notifier);
    if (today.state != day) today.state = day;
    _armMidnight();
  }

  /// One pager per list (dates + order), opened at the centred bike: back
  /// on Domů = the bike the customer left, other dates / a new order =
  /// their first bike — photo, "n / m" and the button always show the SAME
  /// bike.
  PageController _pager(Object key, int center) {
    final cur = _pc;
    if (cur != null && _pcKey == key) return cur;
    if (cur != null) WidgetsBinding.instance.addPostFrameCallback((_) => cur.dispose());
    _pcKey = key;
    return _pc = PageController(initialPage: center);
  }

  void _go(int page) {
    final pc = _pc;
    if (pc == null || !pc.hasClients) return;
    if (MgMotion.reduced(context)) {
      pc.jumpToPage(page);
    } else {
      pc.animateToPage(page, duration: MgMotion.pop, curve: MgMotion.out);
    }
  }

  /// The date sheet; with [moto] it shows that bike's booked days, and the
  /// bike leads the list for the picked dates (when it is free then).
  Future<void> _pickDates(FunnelRange? current, {Motorcycle? moto}) async {
    final picked = await showHomeDateSheet(context,
        initial: current, applyLabel: t(context).tr('v2HomeDateUse'), moto: moto);
    if (picked == null || !mounted) return;
    ref.read(homeOfferFocusProvider.notifier).state = moto?.id;
    _select(picked);
  }

  /// A preset / calendar pick (null = ✕): the dates for the whole app.
  void _select(FunnelRange? range) {
    homeGiveDates(ref, range);
    if (range == null) ref.read(funnelGivenProvider.notifier).state = null;
    ref.read(funnelCenterProvider.notifier).state = 0;
    final pc = _pc;
    if (pc != null && pc.hasClients) pc.jumpToPage(0);
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final sel = ref.watch(funnelSelectionProvider);
    final now = ref.watch(funnelTodayProvider);
    if (funnelDay(DateTime.now()) != now) WidgetsBinding.instance.addPostFrameCallback((_) => _syncDay());
    final offer = ref.watch(homeOfferProvider);
    final range = offer.range;
    final seed = ref.watch(homeOfferSeedProvider);
    final nextFree = ref.watch(homeNextFreeProvider).valueOrNull ?? const <String, DateTime>{};
    // Záznam jízdy běží → jeho tečka je živý indikátor Domů; tečka „Volná
    // v termínu" stojí (max. jeden živý indikátor na obrazovce).
    final recLive = ref.watch(rideRecorderProvider.select((r) => r.recording));
    final loyaltyAsync = ref.watch(loyaltyStatusProvider);
    final loyalty = loyaltyAsync.valueOrNull;
    final lastBike = ref.watch(homeLastBikeIdProvider);
    final groups = homeLicenseGroups(ref.watch(profileProvider).valueOrNull);
    final fullName = ref.watch(profileProvider).valueOrNull?['full_name'] as String?;
    final nick = ref.watch(nicknameProvider) ?? extractFirstName(fullName);
    final list = offer.bikes;
    final center = list.isEmpty ? 0 : ref.watch(funnelCenterProvider).clamp(0, list.length - 1);
    final m = list.isEmpty ? null : list[center];
    final free = offer.mode == HomeOfferMode.free;

    final emptyOrError = offer.mode == HomeOfferMode.error || offer.mode == HomeOfferMode.noBikes;
    // Nižší telefon (< 800 dp) fotka 150, velmi nízký (< 700 dp: 360×640,
    // 375×667) těsnější mezery a při běžném písmu fotka 124 (větší písmo
    // potřebuje 150, jinak by se štítky fotky překryly) — tlačítko nad
    // spodní lištou.
    final screenH = MediaQuery.sizeOf(context).height;
    final short = screenH < 700;
    final bigText = MediaQuery.textScalerOf(context).scale(10) > 10.5;
    final photoH = emptyOrError || screenH >= 800 ? 200.0 : (short && !bigText ? 124.0 : 150.0);
    final today = funnelDay(DateTime.now());
    final Widget slot = switch (offer.mode) {
      HomeOfferMode.loading => const FunnelSkeleton(),
      HomeOfferMode.error =>
        FunnelEmptySlot(error: true, title: tr.tr('eoMotosLoadFail'), text: tr.tr('v2HomeFnLoadFailText')),
      HomeOfferMode.noBikes =>
        FunnelEmptySlot(error: false, title: tr.tr('homeOfferEmptyTitle'), text: tr.tr('homeOfferEmptyText')),
      _ => MgSwipeAnchorListener(
          anchor: _swipe,
          axis: Axis.horizontal,
          child: PageView.builder(
            key: ValueKey((range, seed, free)),
            controller: _pager((range, seed, free), center),
            itemCount: list.length,
            pageSnapping: false,
            physics: MgOnePagePhysics(anchor: _swipe),
            onPageChanged: (i) => ref.read(funnelCenterProvider.notifier).state = i,
            itemBuilder: (_, i) {
              final b = list[i];
              final again = b.id == lastBike;
              final (avail, live) = homeOfferAvail(tr, offer, b, nextFree, today);
              final p = homeOfferPrice(tr, offer, b, loyalty);
              return FunnelBikeCard(
                moto: b,
                center: i == center,
                ping: !recLive,
                again: again,
                badge: again
                    ? tr.tr('v2HomeFnAgain')
                    : (groups.isEmpty ? null : tr.trArgs('v2HomeFnLicense', {'groups': groups.join(' · ')})),
                avail: avail,
                availLive: live,
                priceLabel: p.label,
                price: p.price,
                unit: p.unit,
                listPrice: p.list,
                onTap: () {
                  ref.read(filteredMotoIdsProvider.notifier).state = [for (final x in list) x.id];
                  // The detail opens with the dates this card is priced
                  // for (folded, "Změnit") — not an empty calendar.
                  if (free && range != null) homeGiveDates(ref, range);
                  homePushMoto(context, b.id);
                },
              );
            },
          ),
        ),
    };

    // G-102: the detail's licence / overlap / length warning for the shown
    // bike — REZERVOVAT goes straight to the form (which blocks).
    final errs = free && m != null && range != null
        ? catRangeErrorsV2(context, ref, m, range.start, range.end)
        : const <String>[];
    final action = homeOfferAction(
      context,
      ref,
      offer: offer,
      m: m,
      errs: errs,
      price: m == null ? null : homeOfferPrice(tr, offer, m, loyalty).price,
      pick: () => _pickDates(range, moto: m),
    );
    // J3: no fitting licence in a loaded profile → the warning offers the
    // same fix as the booking form ("Doplnit v profilu" → /profile).
    final licFix = errs.isNotEmpty && m != null && catLicenceFails(ref, m);

    return HomeReveal(
      sessionKey: 'home-funnel',
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
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            // Nižší telefon: menší fotka (photoH), ať je REZERVOVAT nad spodní
            // lištou (V22 §2.4 #4). Prázdný / chybový stav má min. 200 a roste
            // podle textu (velké písmo) — vysvětlení se neusekne.
            child: slot is FunnelEmptySlot ? slot : SizedBox(height: photoH, child: slot),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, short ? 8 : 14, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FunnelTopRow(
                count: list.length,
                more: offer.more,
                index: center,
                onPrev: center > 0 ? () => _go(center - 1) : null,
                onNext: center < list.length - 1 ? () => _go(center + 1) : null,
              ),
              SizedBox(height: short ? 2 : 6),
              MgEnter(
                child: Semantics(
                  header: true,
                  child: FunnelTitle(text: tr.trArgs('v2HomeFnTitle', {'nick': nick}), short: short),
                ),
              ),
              FunnelSubLine(
                loading: loyaltyAsync.isLoading && loyalty == null,
                loyalty: loyalty,
                // Výbava zdarma už je v mottu hlavičky (rank 3) / nízký
                // telefon: jen sleva na jeden řádek — REZERVOVAT nad lištou.
                compact: short || rank.level == 3,
                onRetry: () => ref.invalidate(loyaltyStatusProvider),
              ),
              if (sel.preset(now) == 2 && range != null) FunnelDateLine(range: range, onClear: () => _select(null)),
              SizedBox(height: short ? 6 : 10),
              FunnelPresets(
                selection: sel,
                dense: short,
                onPreset: (i) {
                  final p = funnelPresets(DateTime.now());
                  ref.read(homeOfferFocusProvider.notifier).state = null;
                  _select(i == 1 ? p.$2 : p.$1);
                },
                onCalendar: () => _pickDates(range),
              ),
              SizedBox(height: short ? 6 : 10),
              // G-102: the detail's licence / overlap / length warning also
              // here — REZERVOVAT goes straight to the form (which blocks).
              if (errs.isNotEmpty) ...[
                MgStateBanner(
                  key: const ValueKey('home-funnel-warning'),
                  tone: MgTone.err,
                  dark: true,
                  icon: MgIcons.warn,
                  title: errs.first,
                  text: errs.length > 1 ? errs.skip(1).join('\n') : null,
                  actions: [
                    if (licFix)
                      MgBtnInk(
                        label: tr.tr('completeProfileBtn'),
                        onTap: () => GoRouter.of(context).push('/profile'),
                        // Neon label: on the dark card the fix reads first.
                        neonLabel: true,
                        height: 48,
                        expand: false,
                      ),
                  ],
                ),
                SizedBox(height: short ? 6 : 10),
              ],
              // Nic volného v termínu: jasný nadpis proč (zavřeno / obsazeno).
              if (offer.mode == HomeOfferMode.noneFree) ...[
                homeOfferNoneBanner(tr, offer),
                SizedBox(height: short ? 6 : 10),
              ],
              action,
            ]),
          ),
        ]),
      ),
    );
  }
}
