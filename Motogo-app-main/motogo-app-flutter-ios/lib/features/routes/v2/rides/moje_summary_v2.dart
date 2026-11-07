import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../../../core/v2/rank/mg_club_emblem.dart';
import '../../../../core/v2/motion/mg_count_up.dart';
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

  /// Rides not loaded yet → the count shows "—", not a false 0 (F-18).
  final bool ridesLoading;
  final void Function(MojeSub sub, RideFilter? filter) onSub;
  final VoidCallback onCreateRoute;
  final VoidCallback onLogin;

  const MojeSummaryV2({
    super.key,
    required this.loggedIn,
    required this.rides,
    required this.savedCount,
    required this.placesCount,
    this.ridesLoading = false,
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
              // F-17: personal stat counts up once per session (never a price).
              MgCountUp(
                value: total.round(),
                sessionKey: 'moje-km',
                format: (v) => rtThousands(v.round()),
                style: MgType.tab(MgType.display.copyWith(color: MgColors.ink)),
              ),
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
        // F-17 (board Zazitky): 3 equal tiles in one row (→ sub-screen);
        // labels wrap at words, "—" while a count is still loading (F-18).
        _CountRow(children: [
            // Počet položek seznamu: cesta (sloučené jízdy / jedna výpůjčka) = 1.
          _CountTile(
              icon: MgIcons.bike,
              value: ridesLoading ? null : groupRides(rides).length,
              label: tr.tr('v2RideSubRides'),
              onTap: () => onSub(MojeSub.rides, RideFilter.all)),
          _CountTile(icon: MgIcons.bookmark, value: savedCount, label: tr.tr('v2RideSubSaved'), onTap: () => onSub(MojeSub.saved, null)),
          _CountTile(icon: MgIcons.pin, value: placesCount, label: tr.tr('v2RideSubPlaces'), onTap: () => onSub(MojeSub.places, null)),
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

/// The 3 count tiles in one equal row while every label word fits a tile
/// (scaled to ≥ .6); a narrow phone / large text gets the compact
/// content-sized tiles in a wrap instead — a word is never split.
class _CountRow extends StatelessWidget {
  final List<_CountTile> children;
  const _CountRow({required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final inner = (c.maxWidth - 16) / 3 - 22;
        final style = DefaultTextStyle.of(context).style.merge(MgType.meta);
        final scaler = MediaQuery.textScalerOf(context);
        var longest = 0.0;
        for (final t in children) {
          for (final w in t.label.split(RegExp(r'\s+'))) {
            final tp = TextPainter(text: TextSpan(text: w, style: style), textDirection: Directionality.of(context), textScaler: scaler)
              ..layout();
            if (tp.width > longest) longest = tp.width;
            tp.dispose();
          }
        }
        if (longest * 0.6 <= inner) {
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: children[i])],
            ]),
          );
        }
        return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in children) t.compact()]);
      });
}

/// Count tile (board `.zt`): dark icon tile, number 22/900 (counts up
/// once per session), label meta wrapping at words; tap = the sub-screen.
class _CountTile extends StatelessWidget {
  final String icon;
  final int? value;
  final String label;
  final VoidCallback onTap;
  final bool _compact;
  const _CountTile({required this.icon, required this.value, required this.label, required this.onTap}) : _compact = false;
  const _CountTile._compact({required this.icon, required this.value, required this.label, required this.onTap}) : _compact = true;

  /// Content-sized variant: icon tile + number + label on one line.
  _CountTile compact() => _CountTile._compact(icon: icon, value: value, label: label, onTap: onTap);

  @override
  Widget build(BuildContext context) {
    final style = MgType.tab(MgType.h2.copyWith(fontWeight: FontWeight.w900, color: MgColors.ink));
    final number = value == null
        ? Text('—', style: style)
        : MgCountUp(value: value!, sessionKey: 'moje-$icon', format: (v) => '${v.round()}', style: style);
    return Semantics(
      button: true,
      label: '${value ?? '—'}, $label',
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: _compact ? 44 : 96),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: MgColors.well,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MgColors.line),
          ),
          child: _compact
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  MgIconTileDark(icon, size: 30),
                  const SizedBox(width: 8),
                  number,
                  const SizedBox(width: 6),
                  Flexible(child: Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.lead))),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  MgIconTileDark(icon, size: 30),
                  const SizedBox(height: 8),
                  number,
                  const SizedBox(height: 2),
                  MgWordFit(minScale: 0.6, child: Text(label, style: MgType.meta.copyWith(color: MgColors.meta))),
                ]),
        ),
      ),
    );
  }
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

/// Compact rank row (board Zazitky, F-17): the tier emblem (→ ranks),
/// "Motorkář · Level 3 / 20", the tier progress (1 segment = 1 point, the
/// same table as Domů's club card) — rank on light = emblem + bar only.
class _RankRow extends StatelessWidget {
  final LoyaltyStatus status;
  final RankTokens rank;
  const _RankRow({required this.status, required this.rank});

  // Qualifying points where each league starts (HomeClubCardV2._tierStartPts).
  static const _tierStartPts = [0, 10, 18, 32, 38];

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final name = RankCopy.name(tr, status.level, status.rankName);
    final tier = rank.tierIndex;
    final from = _tierStartPts[tier];
    final to = tier < 4 ? _tierStartPts[tier + 1] : from + 1;
    final inTier = (status.qualifyingCount - from).clamp(0, to - from);
    final aria = RankCopy.aria(tr, status.level, name, status.percent);
    return Semantics(
      button: true,
      label: aria,
      excludeSemantics: true,
      child: MgPress(
        scale: 0.98,
        onTap: () => openLoyaltyRanks(context),
        child: MgWell(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(children: [
            MgClubEmblem(rank: rank, label: aria, onTap: () => openLoyaltyRanks(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MgWordFit(minScale: 0.75, child: Text(name, style: MgType.title.copyWith(color: MgColors.ink))),
                Text(RankCopy.levelLine(tr, status.level, status.percent), style: MgType.tab(MgType.meta.copyWith(color: MgColors.lead))),
                const SizedBox(height: 6),
                MgClubTierBar(rank: rank, segments: to - from, filled: inTier, full: status.isMax),
              ]),
            ),
            const SizedBox(width: 4),
            const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.link),
          ]),
        ),
      ),
    );
  }
}
