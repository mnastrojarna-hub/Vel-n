import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/chrome/mg_nav_helpers.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../routes/my_experiences_provider.dart';
import '../../routes/ride_model.dart';
import '../../routes/ride_provider.dart';
import 'home_record_row_v2.dart';
import 'home_sketch.dart';
import 'home_reveal.dart';

const _myExp = '/my-experiences';

String _km(double v) => v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll('.', ',');

/// "Moje zážitky" — the page's one full-bleed white band (V22 §2.4 #9):
/// "Zaznamenat jízdu" (row B), 2 × 2 tiles with real counts from the
/// existing providers (rides split by booking, saved routes, places) and
/// the last 2 rides. Everything opens the existing screens.
class HomeExperiencesBandV2 extends ConsumerWidget {
  const HomeExperiencesBandV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final ridesA = ref.watch(myRidesProvider);
    final routesA = ref.watch(mySavedRoutesProvider);
    final placesA = ref.watch(myPlacesProvider);
    final rides = ridesA.valueOrNull ?? const <UserRide>[];
    final moto = rides.where((r) => r.bookingId != null).toList();
    final own = rides.where((r) => r.bookingId == null).toList();
    double sum(List<UserRide> l) => l.fold<double>(0, (s, r) => s + r.distanceKm);
    void open() => mgPushOrGo(context, _myExp);

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: MgBand(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(tr.tr('myExpTitle'), style: MgType.section.copyWith(color: MgColors.ink)),
                ),
              ),
              HomeTextLink(label: tr.tr('v2HomeAll'), onTap: open),
            ]),
          ),
          if (rides.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Text(
                tr.trArgs('v2HomeExpStats', {
                  'km': _km(sum(rides)),
                  'n': rides.length,
                  'p': placesA.valueOrNull?.length ?? 0,
                }),
                style: MgType.tab(MgType.small.copyWith(color: MgColors.meta)),
              ),
            ),
          const HomeRecordRowV2(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(children: [
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: _Tile(
                      i: 0,
                      icon: MgIcons.moto,
                      label: tr.tr('v2HomeTileMoto'),
                      value: ridesA.isLoading && !ridesA.hasValue ? null : '${moto.length}',
                      meta: moto.isEmpty ? null : '${_km(sum(moto))} km',
                      onTap: open,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Tile(
                      i: 1,
                      icon: MgIcons.ride,
                      label: tr.tr('v2HomeTilePrivate'),
                      value: ridesA.isLoading && !ridesA.hasValue ? null : '${own.length}',
                      meta: own.isEmpty ? null : '${_km(sum(own))} km',
                      onTap: open,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: _Tile(
                      i: 2,
                      icon: MgIcons.route,
                      label: tr.tr('v2HomeTileRoutes'),
                      value: routesA.isLoading && !routesA.hasValue ? null : '${routesA.valueOrNull?.length ?? 0}',
                      onTap: open,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Tile(
                      i: 3,
                      icon: MgIcons.pin,
                      label: tr.tr('v2HomeTilePlaces'),
                      value: placesA.isLoading && !placesA.hasValue ? null : '${placesA.valueOrNull?.length ?? 0}',
                      onTap: open,
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          if (rides.isEmpty && !ridesA.isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(tr.tr('v2HomeExpEmpty'), style: MgType.small.copyWith(color: MgColors.meta)),
            )
          else if (rides.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
              child: Text(tr.tr('v2HomeLastRides').toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.meta)),
            ),
            for (var k = 0; k < rides.length && k < 2; k++)
              _Entry(ride: rides[k], siblings: [for (final r in rides) r.id], last: k == 1 || k == rides.length - 1),
          ],
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final int i;
  final String icon;
  final String label;
  final String? value;
  final String? meta;
  final VoidCallback onTap;
  const _Tile({required this.i, required this.icon, required this.label, required this.value, this.meta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return HomeReveal(
      index: i + 2,
      sessionKey: 'home-exp',
      child: Semantics(
        button: true,
        label: '$label ${value ?? ''} ${meta ?? ''}',
        excludeSemantics: true,
        child: MgPress(
          scale: 0.98,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 108),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MgColors.well,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MgColors.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: MgColors.panel, borderRadius: BorderRadius.circular(10)),
                  child: Center(child: MgIcon(icon, size: 20, color: MgColors.neon)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MgWordFit(
                    minScale: 0.75,
                    child: Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, height: 1.3, color: MgColors.ink)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              if (value == null)
                const MgSkeleton(width: 60, height: 22, radius: 6)
              else
                Text(value!, style: MgType.tab(MgType.h2.copyWith(fontWeight: FontWeight.w900, color: MgColors.ink))),
              if (meta != null) Text(meta!, style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  final UserRide ride;
  final List<String> siblings;
  final bool last;
  const _Entry({required this.ride, required this.siblings, required this.last});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final withMoto = ride.bookingId != null;
    final title = ride.name.trim().isNotEmpty ? ride.name.trim() : (ride.motoName ?? tr.tr('v2HomeTilePrivate'));
    final meta = '${tripShortDate(tr, ride.startedAt.toLocal())} · ${_km(ride.distanceKm)} km';
    return Semantics(
      button: true,
      label: '$title, $meta',
      excludeSemantics: true,
      child: MgPress(
        scale: 0.99,
        onTap: () => homePushRide(context, ride.id, siblings),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: MgColors.line)),
          ),
          constraints: const BoxConstraints(minHeight: 72),
          child: Row(children: [
            HomeSketch(points: ride.mapPoints, width: 64, height: 48, private: !withMoto),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: withMoto ? MgColors.panel : MgColors.well,
                    borderRadius: BorderRadius.circular(999),
                    border: withMoto ? null : Border.all(color: MgColors.line),
                  ),
                  child: Text(
                    withMoto
                        ? (ride.motoName == null
                            ? tr.tr('v2HomeBadgeMoto')
                            : '${tr.tr('v2HomeBadgeMoto')} · ${ride.motoName}')
                        : tr.tr('v2HomeBadgePrivate'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: withMoto ? MgColors.neon : MgColors.body2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
                Text(meta, style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
              ]),
            ),
            const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.lead),
          ]),
        ),
      ),
    );
  }
}
