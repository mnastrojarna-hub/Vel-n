import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/rank/rank_copy.dart';
import '../../../../core/v2/rank/rank_provider.dart';
import '../../../../core/v2/rank/rank_tokens.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../../core/v2/widgets/mg_surfaces.dart';
import '../../../loyalty/loyalty_provider.dart';
import '../../../loyalty/loyalty_ranks_screen.dart' show openLoyaltyRanks;
import '../../ride_model.dart';
import '../../ride_trip.dart' show groupRides;
import '../rt_v2_text.dart' show rtThousands;
import 'moje_tabs_v2.dart';

/// White "Moje zážitky" summary (V22 §2.4 Zazitky): title, kilometres of
/// the rides split S MotoGo / Soukromé, count tiles (→ sub-screen), compact
/// rank row (→ ranks), "VYTVOŘIT NOVOU TRASU" (ink — the dock's record
/// button is the primary). Logged out: the old login prompt. Every number
/// comes from the providers the screen already reads.
class MojeSummaryV2 extends ConsumerWidget {
  final bool loggedIn;
  final List<UserRide> rides;
  final int? savedCount;
  final int? placesCount;
  final void Function(MojeSub sub, RideFilter? filter) onSub;
  final VoidCallback onCreateRoute;
  final VoidCallback onLogin;

  const MojeSummaryV2({
    super.key,
    required this.loggedIn,
    required this.rides,
    required this.savedCount,
    required this.placesCount,
    required this.onSub,
    required this.onCreateRoute,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final head = Row(children: [
      const MgIconTileDark(MgIcons.bike, size: 44),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(tr.tr('myExpTitle'), style: MgType.h3.copyWith(color: MgColors.ink))),
          const SizedBox(height: 2),
          Text(tr.tr('myExpSubtitle'), style: MgType.small.copyWith(color: MgColors.lead)),
        ]),
      ),
    ]);
    if (!loggedIn) {
      return MgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          head,
          const SizedBox(height: 16),
          Row(children: [
            const MgIcon(MgIcons.key, size: 22, color: MgColors.link),
            const SizedBox(width: 10),
            Expanded(child: Text(tr.tr('myExpLogin'), style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
          ]),
          const SizedBox(height: 14),
          MgBtnInk(label: tr.tr('loginBtn'), neonLabel: true, onTap: onLogin),
        ]),
      );
    }

    final mgKm = rides.where((r) => r.bookingId != null).fold<double>(0, (s, r) => s + r.distanceKm);
    final pvKm = rides.where((r) => r.bookingId == null).fold<double>(0, (s, r) => s + r.distanceKm);
    final total = mgKm + pvKm;
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;

    return MgCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        if (rides.isNotEmpty) ...[
          const SizedBox(height: 16),
          Semantics(
            label: '${rtThousands(total.round())} km',
            excludeSemantics: true,
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(rtThousands(total.round()), style: MgType.tab(MgType.display.copyWith(color: MgColors.ink))),
              const SizedBox(width: 8),
              Flexible(child: Text(tr.tr('v2RideKmTotal'), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.meta))),
            ]),
          ),
          const SizedBox(height: 12),
          _SplitBar(a: mgKm, b: pvKm),
          const SizedBox(height: 4),
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, children: [
            _SplitKey(color: MgColors.neonLo, label: tr.tr('v2RideFilterMg'), km: mgKm, onTap: () => onSub(MojeSub.rides, RideFilter.motogo)),
            _SplitKey(color: MgColors.ink, label: tr.tr('v2RideFilterPriv'), km: pvKm, onTap: () => onSub(MojeSub.rides, RideFilter.private)),
          ]),
        ],
        const SizedBox(height: 12),
        // Count pills (→ sub-screen): sized by their content, so long words
        // (de "Gespeicherte", fr "enregistrés") never break mid-word.
        Wrap(spacing: 8, runSpacing: 8, children: [
          // Počet položek seznamu: cesta (sloučené jízdy / jedna výpůjčka) = 1.
          _CountPill(
              icon: MgIcons.bike, value: '${groupRides(rides).length}', label: tr.tr('v2RideSubRides'), onTap: () => onSub(MojeSub.rides, RideFilter.all)),
          _CountPill(icon: MgIcons.bookmark, value: savedCount == null ? '—' : '$savedCount', label: tr.tr('v2RideSubSaved'), onTap: () => onSub(MojeSub.saved, null)),
          _CountPill(icon: MgIcons.pin, value: placesCount == null ? '—' : '$placesCount', label: tr.tr('v2RideSubPlaces'), onTap: () => onSub(MojeSub.places, null)),
        ]),
        if (status != null) ...[
          const SizedBox(height: 10),
          _RankRow(status: status, rank: ref.watch(rankTokensProvider)),
        ],
        const SizedBox(height: 14),
        MgBtnInk(label: tr.tr('myExpCreateRoute'), icon: MgIcons.pinPlus, neonLabel: true, onTap: onCreateRoute),
        const SizedBox(height: 8),
        Text(tr.tr('myExpCreateRouteSub'), textAlign: TextAlign.center, style: MgType.small.copyWith(color: MgColors.meta)),
      ]),
    );
  }
}

class _CountPill extends StatelessWidget {
  final String icon;
  final String value;
  final String label;
  final VoidCallback onTap;
  const _CountPill({required this.icon, required this.value, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$value, $label',
        excludeSemantics: true,
        child: MgPress(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: MgColors.well,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MgColors.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              MgIcon(icon, size: 18, color: MgColors.link),
              const SizedBox(width: 8),
              Text(value, style: MgType.tab(MgType.title.copyWith(fontWeight: FontWeight.w900, color: MgColors.ink))),
              const SizedBox(width: 6),
              Flexible(child: Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.lead))),
            ]),
          ),
        ),
      );
}

class _SplitBar extends StatelessWidget {
  final double a;
  final double b;
  const _SplitBar({required this.a, required this.b});

  @override
  Widget build(BuildContext context) {
    final total = a + b;
    return ExcludeSemantics(
      child: Container(
        height: 8,
        decoration: BoxDecoration(
          color: MgColors.well,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MgColors.line),
        ),
        child: total <= 0
            ? null
            : LayoutBuilder(builder: (context, c) {
                final w = c.maxWidth;
                var wa = a > 0 ? (a / total * w).clamp(6.0, w) : 0.0;
                var wb = b > 0 ? (b / total * w).clamp(6.0, w) : 0.0;
                if (wa + wb > w) {
                  if (wa > wb) {
                    wa = w - wb;
                  } else {
                    wb = w - wa;
                  }
                }
                return MgProgressOnce(
                  duration: const Duration(milliseconds: 600),
                  builder: (context, t) => Row(children: [
                    if (wa > 0) _bar(wa * t, MgColors.neonLo),
                    const Spacer(),
                    if (wb > 0) _bar(wb * t, MgColors.ink),
                  ]),
                );
              }),
      ),
    );
  }

  Widget _bar(double w, Color c) => Container(
        width: w,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(999)),
      );
}

class _SplitKey extends StatelessWidget {
  final Color color;
  final String label;
  final double km;
  final VoidCallback onTap;
  const _SplitKey({required this.color, required this.label, required this.km, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$label ${rtThousands(km.round())} km',
        excludeSemantics: true,
        child: MgPress(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.lead)),
              const SizedBox(width: 4),
              Text('${rtThousands(km.round())} km', style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
            ]),
          ),
        ),
      );
}

/// Compact rank row (dark mini disc + ink name, level line, tier progress).
class _RankRow extends StatelessWidget {
  final LoyaltyStatus status;
  final RankTokens rank;
  const _RankRow({required this.status, required this.rank});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final name = RankCopy.name(tr, status.level, status.rankName);
    return Semantics(
      button: true,
      label: RankCopy.aria(tr, status.level, name, status.percent),
      excludeSemantics: true,
      child: MgPress(
        scale: 0.98,
        onTap: () => openLoyaltyRanks(context),
        child: MgWell(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: rank.edgeGradient),
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: rank.ctaGradient),
                child: Center(child: MgIcon(_tierIcon(rank.tier), size: 18, color: rank.ctaLabel)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
                Text(RankCopy.levelLine(tr, status.level, status.percent),
                    style: MgType.tab(MgType.meta.copyWith(color: MgColors.lead))),
              ]),
            ),
            const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.link),
          ]),
        ),
      ),
    );
  }

  static String _tierIcon(RankTier t) => switch (t) {
        RankTier.road => MgIcons.tierRoad,
        RankTier.metal => MgIcons.tierMetal,
        RankTier.jewel => MgIcons.tierJewel,
        RankTier.vip => MgIcons.crown,
        RankTier.legend => MgIcons.laurel,
      };
}
