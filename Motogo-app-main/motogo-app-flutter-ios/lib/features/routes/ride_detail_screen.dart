import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/router.dart' show MotoGoBackNav;
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import 'ride_card.dart'
    show rideDate, rideDateTime, rideDuration, rideKm, rideSpeed;
import 'ride_map.dart';
import 'ride_model.dart';
import 'ride_point_sheet.dart';
import 'ride_provider.dart';
import 'ride_share.dart';
import 'route_image.dart';

/// Detail projeté jízdy — mapa se stopou, statistiky, zastávky s fotkami
/// a popisky (přidat / upravit / smazat), přepínač sdílení a export na
/// sociální sítě. Jízda je soukromá, dokud ji jezdec sám nezveřejní.
class RideDetailScreen extends ConsumerWidget {
  final String rideId;

  const RideDetailScreen({super.key, required this.rideId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rides = ref.watch(myRidesProvider);
    return rides.when(
      loading: () => const Scaffold(
        backgroundColor: MotoGoColors.bg,
        body: Center(child: CircularProgressIndicator(color: MotoGoColors.greenDark)),
      ),
      error: (_, __) => _missing(context),
      data: (list) {
        UserRide? ride;
        for (final r in list) {
          if (r.id == rideId) ride = r;
        }
        if (ride == null) return _missing(context);
        return _RideDetailBody(ride: ride);
      },
    );
  }

  Widget _missing(BuildContext context) => Scaffold(
        backgroundColor: MotoGoColors.bg,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏍️', style: TextStyle(fontSize: 42)),
                const SizedBox(height: 10),
                Text(
                  t(context).tr('rideNotFound'),
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeXl,
                      fontWeight: MotoGoTypo.w800,
                      color: MotoGoColors.black,
                      decoration: TextDecoration.none),
                ),
                const SizedBox(height: 14),
                PressableScale(
                  onTap: () => context.backOr('/my-experiences'),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: MotoGoColors.green,
                      borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                    ),
                    child: Text(
                      t(context).tr('routesRetry'),
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeLg,
                          fontWeight: MotoGoTypo.w800,
                          color: MotoGoColors.black,
                          decoration: TextDecoration.none),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _RideDetailBody extends ConsumerStatefulWidget {
  final UserRide ride;
  const _RideDetailBody({required this.ride});

  @override
  ConsumerState<_RideDetailBody> createState() => _RideDetailBodyState();
}

class _RideDetailBodyState extends ConsumerState<_RideDetailBody> {
  bool _busy = false;

  UserRide get ride => widget.ride;

  Future<void> _reload() async => ref.invalidate(myRidesProvider);

  Future<void> _toggleVisibility(bool public) async {
    if (_busy) return;
    setState(() => _busy = true);
    await updateUserRide(ride.id, visibility: public ? 'public' : 'private');
    if (!mounted) return;
    setState(() => _busy = false);
    await _reload();
  }

  Future<void> _editTexts() async {
    final name = TextEditingController(text: ride.name);
    final desc = TextEditingController(text: ride.description ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(t(c).tr('rideEditTitle'),
            style: const TextStyle(
                fontSize: MotoGoTypo.sizeH3, fontWeight: MotoGoTypo.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: t(c).tr('rideName')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: desc,
              maxLines: 3,
              decoration: InputDecoration(labelText: t(c).tr('rideDescription')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t(c).tr('routesFilterClear'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: MotoGoColors.green,
                foregroundColor: MotoGoColors.black),
            onPressed: () => Navigator.pop(c, true),
            child: Text(t(c).tr('ridePointSave')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await updateUserRide(ride.id,
        name: name.text.trim(), description: desc.text.trim());
    await _reload();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(t(c).tr('rideDeleteConfirm'),
            style: const TextStyle(
                fontSize: MotoGoTypo.sizeH3, fontWeight: MotoGoTypo.w900)),
        content: Text(ride.name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t(c).tr('routesFilterClear'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD93636),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: Text(t(c).tr('myExpDelete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await deleteUserRide(ride.id);
    await _reload();
    if (mounted) context.backOr('/my-experiences');
  }

  Future<void> _addStop(LatLng at) async {
    final changed = await showRidePointSheet(context,
        rideId: ride.id, lat: at.latitude, lng: at.longitude);
    if (changed) await _reload();
  }

  Future<void> _editPoint(RidePoint p) async {
    final changed = await showRidePointSheet(context, rideId: ride.id, point: p);
    if (changed) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  _mapCard(),
                  const SizedBox(height: 12),
                  _statsCard(context),
                  const SizedBox(height: 12),
                  _sharingCard(context),
                  const SizedBox(height: 16),
                  Text(
                    t(context).tr('rideStops'),
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeXl,
                        fontWeight: MotoGoTypo.w900,
                        color: MotoGoColors.black,
                        decoration: TextDecoration.none),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t(context).tr('rideStopsHint'),
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeMd,
                        fontWeight: MotoGoTypo.w600,
                        color: MotoGoColors.g500,
                        height: 1.35,
                        decoration: TextDecoration.none),
                  ),
                  const SizedBox(height: 10),
                  for (final p in ride.points) _pointCard(context, p),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 16),
        decoration: const BoxDecoration(
          color: MotoGoColors.dark,
          borderRadius:
              BorderRadius.vertical(bottom: Radius.circular(MotoGoRadius.hdr)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => context.backOr('/my-experiences'),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(MotoGoRadius.lg),
                ),
                child: const Icon(Icons.arrow_back, size: 20, color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _editTexts,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            ride.name.isNotEmpty
                                ? ride.name
                                : t(context).tr('rideUntitled'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: MotoGoTypo.sizeH2,
                                fontWeight: MotoGoTypo.w900,
                                color: Colors.white,
                                decoration: TextDecoration.none),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.edit, size: 15, color: Color(0xFF8AAB99)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        rideDate(ride.startedAt),
                        if ((ride.motoName ?? '').isNotEmpty) ride.motoName!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeBase,
                          fontWeight: MotoGoTypo.w600,
                          color: Color(0xFF8AAB99),
                          decoration: TextDecoration.none),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => showRideShareSheet(context, ride),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.ios_share, size: 21, color: Colors.white),
              ),
            ),
            GestureDetector(
              onTap: _delete,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.delete_outline, size: 22, color: Color(0xFFFF9B9B)),
              ),
            ),
          ],
        ),
      );

  Widget _mapCard() => ClipRRect(
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        child: SizedBox(
          height: 260,
          child: RideTrackMap(
            track: ride.track,
            points: ride.points,
            interactive: true,
            onMapTap: _addStop,
            onPointTap: (i) => _editPoint(ride.points[i]),
          ),
        ),
      );

  Widget _statsCard(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoRadius.card),
          boxShadow: MotoGoShadows.cardSmall,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kompletní přehled jízdy — km, časy (celkem / v sedle / stání),
            // rychlosti, nastoupáno, zastávky a fotky.
            _statRow([
              _stat('📏', rideKm(ride.distanceKm), t(context).tr('rideStatDistance')),
              _stat('⏱️', rideDuration(ride.totalMin), t(context).tr('rideStatDuration')),
              _stat('🏍️', ride.movingSec > 0 ? rideDuration(ride.movingMin) : '—',
                  t(context).tr('rideStatMoving')),
            ]),
            const SizedBox(height: 12),
            _statRow([
              _stat('⏸️', ride.idleSec > 0 ? rideDuration(ride.idleMin) : '—',
                  t(context).tr('rideStatIdle')),
              _stat('📊', rideSpeed(ride.avgSpeedKmh ?? ride.avgOverallKmh),
                  t(context).tr('rideStatAvg')),
              _stat('🚀', rideSpeed(ride.maxSpeedKmh), t(context).tr('rideStatMax')),
            ]),
            const SizedBox(height: 12),
            _statRow([
              _stat('⛰️', ride.elevationGainM > 0 ? '${ride.elevationGainM} m' : '—',
                  t(context).tr('rideStatClimb')),
              _stat('📍', '${ride.stops.length}', t(context).tr('rideStatStops')),
              _stat('📷', '${ride.photoCount}', t(context).tr('rideStatPhotos')),
            ]),
            const SizedBox(height: 12),
            // Kdy se jelo — od kdy do kdy (u rozjeté jízdy jen start).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: MotoGoColors.g100,
                borderRadius: BorderRadius.circular(MotoGoRadius.xl),
              ),
              child: Text(
                '🕘 ${t(context).tr('rideStatStart')} ${rideDateTime(ride.startedAt)}'
                '${ride.endedAt != null ? '   →   ${t(context).tr('rideStatEnd')} ${rideDateTime(ride.endedAt!)}' : ''}',
                style: const TextStyle(
                    fontSize: MotoGoTypo.sizeMd,
                    fontWeight: MotoGoTypo.w700,
                    color: MotoGoColors.g600,
                    decoration: TextDecoration.none),
              ),
            ),
            if ((ride.motoName ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '🏍️ ${ride.motoName}',
                style: const TextStyle(
                    fontSize: MotoGoTypo.sizeBase,
                    fontWeight: MotoGoTypo.w700,
                    color: MotoGoColors.g600,
                    decoration: TextDecoration.none),
              ),
            ],
            if ((ride.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                ride.description!,
                style: const TextStyle(
                    fontSize: MotoGoTypo.sizeBase,
                    fontWeight: MotoGoTypo.w600,
                    color: MotoGoColors.g600,
                    height: 1.45,
                    decoration: TextDecoration.none),
              ),
            ],
          ],
        ),
      );

  /// Řádek tří statistik (stejně široké sloupce).
  Widget _statRow(List<Widget> children) => Row(children: children);

  Widget _stat(String emoji, String value, String label) => Expanded(
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontSize: MotoGoTypo.sizeXl,
                    fontWeight: MotoGoTypo.w900,
                    color: MotoGoColors.black,
                    decoration: TextDecoration.none)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: MotoGoTypo.sizeSm,
                    fontWeight: MotoGoTypo.w700,
                    color: MotoGoColors.g400,
                    decoration: TextDecoration.none)),
          ],
        ),
      );

  Widget _sharingCard(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoRadius.card),
          boxShadow: MotoGoShadows.cardSmall,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t(context).tr('rideVisibility'),
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeLg,
                        fontWeight: MotoGoTypo.w800,
                        color: MotoGoColors.black,
                        decoration: TextDecoration.none),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t(context).tr(
                        ride.isPublic ? 'rideVisibilityOn' : 'rideVisibilityOff'),
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeMd,
                        fontWeight: MotoGoTypo.w600,
                        color: MotoGoColors.g500,
                        height: 1.35,
                        decoration: TextDecoration.none),
                  ),
                ],
              ),
            ),
            Switch(
              value: ride.isPublic,
              activeColor: MotoGoColors.greenDark,
              onChanged: _busy ? null : _toggleVisibility,
            ),
          ],
        ),
      );

  Widget _pointCard(BuildContext context, RidePoint p) {
    final title = p.name.isNotEmpty
        ? p.name
        : t(context).tr(p.isStart
            ? 'rideStart'
            : p.isEnd
                ? 'rideEnd'
                : 'rideStop');
    final emoji = p.isStart
        ? '🏁'
        : p.isEnd
            ? '🏆'
            : '📍';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableScale(
        pressedScale: 0.98,
        onTap: () => _editPoint(p),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.card),
            boxShadow: MotoGoShadows.cardSmall,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeLg,
                          fontWeight: MotoGoTypo.w800,
                          color: MotoGoColors.black,
                          decoration: TextDecoration.none),
                    ),
                  ),
                  const Icon(Icons.edit, size: 16, color: MotoGoColors.g400),
                ],
              ),
              if ((p.note ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  p.note!,
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeBase,
                      fontWeight: MotoGoTypo.w600,
                      color: MotoGoColors.g600,
                      height: 1.4,
                      decoration: TextDecoration.none),
                ),
              ],
              if (p.photos.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 84,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: p.photos.length,
                    itemBuilder: (c, i) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 110,
                          height: 84,
                          child: RouteImage(
                            url: p.photos[i],
                            targetWidth: 320,
                            placeholder: (_) => Container(color: MotoGoColors.g100),
                            error: (_) => Container(
                              color: MotoGoColors.g200,
                              child: const Icon(Icons.broken_image,
                                  size: 18, color: MotoGoColors.g400),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
