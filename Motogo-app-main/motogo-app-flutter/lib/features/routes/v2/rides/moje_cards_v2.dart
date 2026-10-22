import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_surfaces.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../active_ride_provider.dart' show ActiveRide;
import '../../my_experiences_provider.dart';
import '../../ride_card.dart' show rideDate;
import '../../route_image.dart';
import '../rt_v2_text.dart' show rtDur;
import 'ride_track_sketch_v2.dart';

/// Delete icon of a light card (48 hit, red glyph) — same callback as the
/// old trash icon.
class MojeDeleteButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  const MojeDeleteButton({super.key, required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: MgPress(
          scale: 0.9,
          onTap: onTap,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Center(child: MgIcon(MgIcons.trash, size: 20, color: MgColors.err)),
          ),
        ),
      );
}

/// Saved route (board `.svc`): waypoint sketch, name, km · time · stops ·
/// date, description, NAVIGOVAT (ink) + Upravit (ghost). Tap = the old card
/// tap (builder preview); trash = the old delete confirm.
class SavedRouteCardV2 extends StatelessWidget {
  final SavedRoute route;
  final VoidCallback onOpen;
  final VoidCallback onNavigate;
  final VoidCallback onDelete;
  const SavedRouteCardV2({
    super.key,
    required this.route,
    required this.onOpen,
    required this.onNavigate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final r = route;
    final meta = [
      if (r.distanceKm != null) '${r.distanceKm!.toStringAsFixed(0)} km',
      if (r.durationMin != null) rtDur(r.durationMin!),
      '${r.waypoints.length}× ${tr.tr('routeBuilderStop').toLowerCase()}',
      if (r.createdAt != null) rideDate(r.createdAt!),
    ];
    return MgCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      onTap: onOpen,
      semanticLabel: r.name,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RideTrackSketch.line(r.waypoints, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
              const SizedBox(height: 4),
              Text(meta.join(' · '), style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.meta))),
            ]),
          ),
          MojeDeleteButton(onTap: onDelete, label: '${tr.tr('myExpDelete')}: ${r.name}'),
        ]),
        if ((r.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(r.description!,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.small.copyWith(color: MgColors.body2)),
          ),
        ],
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(children: [
            Expanded(child: MgBtnInk(label: tr.tr('myExpNavigate'), icon: MgIcons.navigate, neonLabel: true, height: 48, onTap: onNavigate)),
            const SizedBox(width: 10),
            Expanded(child: MgBtnGhostLight(label: tr.tr('myExpEdit'), icon: MgIcons.edit, onTap: onOpen)),
          ]),
        ),
      ]),
    );
  }
}

/// Discovered place (board `.vpc`): photo 92, ✓ name, the route it was
/// found on, first visit · visit count, round "navigate" button (only with
/// coordinates — as before). Tap = the existing place sheet.
class VisitedPlaceCardV2 extends StatelessWidget {
  final VisitedPlace place;
  final VoidCallback onOpen;
  final VoidCallback? onNavigate;
  const VisitedPlaceCardV2({super.key, required this.place, required this.onOpen, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final p = place;
    final when = [
      if (p.firstVisitedAt != null) rideDate(p.firstVisitedAt!),
      if (p.visitCount > 1) tr.tr('myExpVisited').replaceFirst('{n}', '${p.visitCount}'),
    ].join(' · ');
    Widget fallback(BuildContext _) => const ColoredBox(
          color: MgColors.tintFeatureA,
          child: Center(child: MgIcon(MgIcons.pin, size: 28, color: MgColors.routeGreen)),
        );
    return MgCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(8),
      onTap: onOpen,
      semanticLabel: p.name,
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 92,
            height: 92,
            child: p.imageUrl != null
                ? RouteImage(url: p.imageUrl!, targetWidth: 300, placeholder: fallback, error: fallback)
                : fallback(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle),
                child: const MgIcon(MgIcons.check, size: 12, color: MgColors.onNeon, stroke: 3),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
              ),
            ]),
            if (p.routeName != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const MgIcon(MgIcons.route, size: 15, color: MgColors.link),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(p.routeName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.link)),
                ),
              ]),
            ],
            if (when.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(when, style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
            ],
          ]),
        ),
        const SizedBox(width: 4),
        Semantics(
          button: true,
          enabled: onNavigate != null,
          label: '${tr.tr('myExpNavigate')}: ${p.name}',
          excludeSemantics: true,
          child: MgPress(
            scale: 0.9,
            onTap: onNavigate,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: onNavigate == null ? MgColors.well : MgColors.ink,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: MgIcon(MgIcons.navigate, size: 20, color: onNavigate == null ? MgColors.disabled : MgColors.neon),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Navigation history entry (board `.hic`): name, Aktivní / Dokončeno chip,
/// trash (active ride = end it, else remove — the old icon's action), date,
/// reached stops + progress bar, "Pokračovat v trase" / "Jet znovu".
class HistoryCardV2 extends StatelessWidget {
  final ActiveRide ride;
  final bool isActive;
  final VoidCallback onOpen;
  final VoidCallback onGo;
  final VoidCallback onDelete;
  const HistoryCardV2({
    super.key,
    required this.ride,
    required this.isActive,
    required this.onOpen,
    required this.onGo,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final r = ride;
    final name = r.name.isNotEmpty ? r.name : tr.tr('routeNavTitle');
    final chip = isActive ? tr.tr('myExpRideActive') : (r.done ? tr.tr('myExpRideDone') : null);
    final again = r.done && !isActive;
    final frac = r.totalStops > 0 ? (r.reached.length / r.totalStops).clamp(0.0, 1.0) : null;
    return MgCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 14),
      onTap: onOpen,
      semanticLabel: name,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // r1: název má celou šířku (stav jde pod něj), slovo se nedělí.
        Row(children: [
          Expanded(
            child: MgWordFit(
              minScale: 0.8,
              child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
            ),
          ),
          MojeDeleteButton(onTap: onDelete, label: '${tr.tr('myExpDelete')}: $name'),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (chip != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isActive ? MgColors.neon : MgColors.tintOk,
                    borderRadius: BorderRadius.circular(999),
                    border: isActive ? null : Border.all(color: MgColors.tintOkBorder),
                  ),
                  child: Text(chip,
                      style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: isActive ? MgColors.onNeon : MgColors.onTintOk)),
                ),
              RideMetaV2(MgIcons.calendarCheck, rideDate(r.updatedAt)),
              if (r.totalStops > 0) RideMetaV2(MgIcons.pin, '${r.reached.length}/${r.totalStops}'),
            ]),
            if (frac != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: Stack(children: [
                    const Positioned.fill(child: ColoredBox(color: MgColors.well)),
                    FractionallySizedBox(
                      widthFactor: frac,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(gradient: LinearGradient(colors: [MgColors.link, MgColors.neonLo])),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 12),
            again
                ? MgBtnGhostLight(label: tr.tr('myExpRideAgain'), icon: MgIcons.again, onTap: onGo)
                : MgBtnInk(label: tr.tr('myExpContinueRoute'), icon: MgIcons.navigate, neonLabel: true, height: 48, onTap: onGo),
          ]),
        ),
      ]),
    );
  }
}
