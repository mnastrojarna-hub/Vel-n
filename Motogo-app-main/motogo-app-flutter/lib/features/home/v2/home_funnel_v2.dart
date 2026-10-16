import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../auth/auth_provider.dart';
import '../../booking/booking_entry.dart';
import '../../booking/booking_quote.dart';
import '../../catalog/catalog_provider.dart';
import '../../catalog/moto_model.dart';
import '../../loyalty/loyalty_provider.dart';
import '../nickname_provider.dart';
import 'funnel_carousel_v2.dart';
import 'funnel_provider.dart';
import 'home_date_sheet_v2.dart';
import 'home_funnel_parts.dart';
import 'home_reveal.dart';

/// Home funnel "Tvoje příští jízda" (S0 / S10, DESIGN_V21 §4 + V22 §2.4 #4):
/// photo-led dark card — carousel of bikes free on the chosen weekend /
/// range (licence-filtered, real availability), your price from the SAME
/// price engine the booking form uses, presets + calendar, and the one
/// looping CTA "REZERVOVAT · {cena}" → the existing booking start (PM-3).
class HomeFunnelV2 extends ConsumerStatefulWidget {
  const HomeFunnelV2({super.key});

  @override
  ConsumerState<HomeFunnelV2> createState() => _HomeFunnelV2State();
}

class _HomeFunnelV2State extends ConsumerState<HomeFunnelV2> {
  final PageController _pc = PageController();

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _go(int page) {
    if (!_pc.hasClients) return;
    if (MgMotion.reduced(context)) {
      _pc.jumpToPage(page);
    } else {
      _pc.animateToPage(page, duration: MgMotion.pop, curve: MgMotion.out);
    }
  }

  Future<void> _pickDates(FunnelRange current) async {
    final picked = await showHomeDateSheet(context,
        initial: current, applyLabel: t(context).tr('v2HomeDateUse'));
    if (picked == null || !mounted) return;
    ref.read(funnelSelectionProvider.notifier).state = FunnelSelection(2, picked);
    ref.read(funnelCenterProvider.notifier).state = 0;
    if (_pc.hasClients) _pc.jumpToPage(0);
  }

  void _select(FunnelSelection s) {
    ref.read(funnelSelectionProvider.notifier).state = s;
    ref.read(funnelCenterProvider.notifier).state = 0;
    if (_pc.hasClients) _pc.jumpToPage(0);
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final sel = ref.watch(funnelSelectionProvider);
    final range = sel.range(DateTime.now());
    final async = ref.watch(funnelCandidatesProvider(range));
    final loyaltyAsync = ref.watch(loyaltyStatusProvider);
    final loyalty = loyaltyAsync.valueOrNull;
    final lastBike = ref.watch(homeLastBikeIdProvider);
    final groups = homeLicenseGroups(ref.watch(profileProvider).valueOrNull);
    final fullName = ref.watch(profileProvider).valueOrNull?['full_name'] as String?;
    final nick = ref.watch(nicknameProvider) ?? extractFirstName(fullName);
    final list = async.valueOrNull ?? const <Motorcycle>[];
    final center = list.isEmpty ? 0 : ref.watch(funnelCenterProvider).clamp(0, list.length - 1);
    final days = range.days;
    final dayWord = '$days ${tr.daysWord(days)}';

    String total(Motorcycle m) => Money.czk(quoteFor(m, range.start, range.end, loyalty: loyalty).total);
    String? listOf(Motorcycle m) {
      if (loyalty == null || loyalty.percent <= 0) return null;
      final l = listQuoteFor(m, range.start, range.end).total;
      return Money.czk(l);
    }

    final emptyOrError = (async.hasError && !async.hasValue) || (async.hasValue && list.isEmpty);
    final photoH = MediaQuery.sizeOf(context).height < 800 && !emptyOrError ? 150.0 : 200.0;
    final Widget slot = async.when(
      skipLoadingOnReload: true,
      loading: () => const FunnelSkeleton(),
      error: (_, __) => FunnelEmptySlot(error: true, title: tr.tr('eoMotosLoadFail'), text: tr.tr('v2HomeFnLoadFailText')),
      data: (l) => l.isEmpty
          ? FunnelEmptySlot(error: false, title: tr.tr('v2HomeFnNoneTitle'), text: tr.tr('v2HomeFnNoneText'))
          : PageView.builder(
              controller: _pc,
              itemCount: l.length,
              onPageChanged: (i) => ref.read(funnelCenterProvider.notifier).state = i,
              itemBuilder: (_, i) {
                final m = l[i];
                final again = m.id == lastBike;
                return FunnelBikeCard(
                  moto: m,
                  center: i == center,
                  again: again,
                  badge: again
                      ? tr.tr('v2HomeFnAgain')
                      : (groups.isEmpty ? null : tr.trArgs('v2HomeFnLicense', {'groups': groups.join(' · ')})),
                  priceLabel: tr.trArgs('v2HomeFnPriceFor', {'days': dayWord}),
                  price: total(m),
                  listPrice: listOf(m),
                  onTap: () {
                    ref.read(filteredMotoIdsProvider.notifier).state = [for (final x in l) x.id];
                    homePushMoto(context, m.id);
                  },
                );
              },
            ),
    );

    final Widget action;
    if (async.isLoading && !async.hasValue) {
      action = MgCta(label: tr.tr('v2HomeCtaReserve'), onTap: null, enabled: false);
    } else if (async.hasError && !async.hasValue) {
      action = MgBtnGhostDark(
        label: tr.tr('eoRetry'),
        onTap: () {
          ref.invalidate(motorcyclesProvider);
          ref.invalidate(funnelCandidatesProvider(range));
        },
      );
    } else if (list.isEmpty) {
      action = MgBtnGhostDark(label: tr.tr('v2HomeFnPickOther'), onTap: () => _pickDates(range));
    } else {
      final m = list[center];
      action = MgFabAvoid(
        child: MgCta(
          label: tr.tr('v2HomeCtaReserve'),
          price: total(m),
          loop: true,
          size: MgCtaSize.lg60,
          onTap: () => startBookingFromSelection(context, ref, m, range.start, range.end),
        ),
      );
    }

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
            // Nižší telefon (< 800 dp): fotka 150, ať je REZERVOVAT nad
            // spodní lištou (V22 §2.4 #4). Prázdný / chybový stav potřebuje 200.
            child: SizedBox(height: photoH, child: slot),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FunnelTopRow(
                count: list.length,
                index: center,
                onPrev: center > 0 ? () => _go(center - 1) : null,
                onNext: center < list.length - 1 ? () => _go(center + 1) : null,
              ),
              const SizedBox(height: 6),
              MgEnter(
                child: Semantics(
                  header: true,
                  // Raději o kousek menší na jednom řádku než na dvou (REZERVOVAT
                  // zůstane nad lištou); dlouhé jméno se zalomí v mezeře.
                  child: MgWordFit(
                    minScale: 0.85,
                    fitLines: 1,
                    child: Text(tr.trArgs('v2HomeFnTitle', {'nick': nick}),
                        maxLines: 2, style: MgType.h2.copyWith(color: MgColors.onDark)),
                  ),
                ),
              ),
              FunnelSubLine(
                loading: loyaltyAsync.isLoading && loyalty == null,
                loyalty: loyalty,
                onRetry: () => ref.invalidate(loyaltyStatusProvider),
              ),
              if (sel.preset == 2)
                FunnelDateLine(range: range, onClear: () => _select(const FunnelSelection(0))),
              const SizedBox(height: 10),
              FunnelPresets(
                selection: sel,
                onPreset: (i) => _select(FunnelSelection(i)),
                onCalendar: () => _pickDates(range),
              ),
              const SizedBox(height: 10),
              action,
            ]),
          ),
        ]),
      ),
    );
  }
}
