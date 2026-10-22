import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import 'ride_card.dart' show rideDuration, rideKm;
import 'ride_live_stats.dart' show rideDaysLabel;
import 'ride_model.dart';
import 'ride_trip.dart';
import 'route_export.dart';
import '../../core/widgets/mg_nav_controls.dart';
import '../../core/v2/flag/v2_scope.dart';
import 'v2/rides/ride_share_v2.dart';

/// Sdílení projeté jízdy na sociální sítě.
///
/// Sdílí se POPIS jízdy + odkaz na její stopu v Mapy.com (příjemce ji vidí
/// na mapě, nemusí mít appku). Sdílení je čistě na jezdci — z appky nic
/// neodchází samo a jízdu ostatní neuvidí, dokud ji sám nezveřejní.

/// Zjednodušená stopa pro odkaz do map (max ~12 bodů — delší URL nevezmou).
List<LatLng> rideShareWaypoints(UserRide ride) {
  // JEN nejdelší souvislý úsek — odkaz do map vedený přes mezeru
  // (appka byla na pozadí) by příjemci nakreslil cestu, kterou jezdec
  // neprojel. Sdílet vymyšlenou trasu je horší než sdílet kratší.
  final pts = ride.longestSegment;
  if (pts.length <= 12) return pts;
  final step = (pts.length / 11).ceil();
  final out = <LatLng>[];
  for (var i = 0; i < pts.length; i += step) {
    out.add(pts[i]);
  }
  if (out.last != pts.last) out.add(pts.last);
  return out;
}

/// Řádek statistik ke sdílení: rozsah dat · dny (≥ 2) · km · čas v sedle
/// (ne celkový čas — u vícedenní cesty by v něm byly i noci).
String _shareStats(AppTranslations tr, UserRide ride, DateTime from, DateTime to, int days) => [
      rideDateRange(from, to),
      if (days >= 2) rideDaysLabel(days, tr),
      rideKm(ride.distanceKm),
      if (ride.movingSec > 0) tr.trArgs('rpSaddle', {'time': rideDuration(ride.movingMin)}),
    ].join(' · ');

String _shareLink(UserRide ride) {
  final pts = rideShareWaypoints(ride);
  return pts.length >= 2 ? RouteExport.mapy(pts).toString() : '';
}

/// Text sdílení — název, statistiky a odkaz na mapu.
String rideShareText(BuildContext context, UserRide ride) {
  final tr = t(context);
  final link = _shareLink(ride);
  final parts = <String>[
    '🏍️ ${ride.name.isNotEmpty ? ride.name : tr.tr('rideUntitled')}',
    _shareStats(tr, ride, ride.startedAt, ride.endedAt ?? ride.lastFixAt ?? ride.startedAt, ride.days),
    if ((ride.description ?? '').isNotEmpty) ride.description!,
    if (link.isNotEmpty) link,
    tr.tr('rideShareFooter'),
  ];
  return parts.join('\n');
}

/// Text sdílení celé cesty (sloučené jízdy).
String rideTripShareText(BuildContext context, RideTrip trip) {
  final tr = t(context);
  final link = _shareLink(trip.aggregate);
  return [
    '🧳 ${rideTripDefaultName(trip, tr)}',
    _shareStats(tr, trip.aggregate, trip.from, trip.to, trip.days),
    if (link.isNotEmpty) link,
    tr.tr('rideShareFooter'),
  ].join('\n');
}

enum RideShareTarget { whatsapp, facebook, x, telegram, email, copy }

extension RideShareTargetInfo on RideShareTarget {
  String get label => switch (this) {
        RideShareTarget.whatsapp => 'WhatsApp',
        RideShareTarget.facebook => 'Facebook',
        RideShareTarget.x => 'X',
        RideShareTarget.telegram => 'Telegram',
        RideShareTarget.email => 'E-mail',
        RideShareTarget.copy => '',
      };

  String get emoji => switch (this) {
        RideShareTarget.whatsapp => '💬',
        RideShareTarget.facebook => '📘',
        RideShareTarget.x => '✖️',
        RideShareTarget.telegram => '✈️',
        RideShareTarget.email => '✉️',
        RideShareTarget.copy => '📋',
      };
}

Uri? _shareUri(RideShareTarget target, String text, String link) {
  final enc = Uri.encodeComponent(text);
  return switch (target) {
    RideShareTarget.whatsapp => Uri.parse('https://wa.me/?text=$enc'),
    RideShareTarget.telegram => Uri.parse(
        'https://t.me/share/url?url=${Uri.encodeComponent(link)}&text=$enc'),
    RideShareTarget.x => Uri.parse('https://twitter.com/intent/tweet?text=$enc'),
    RideShareTarget.facebook => link.isEmpty
        ? null
        : Uri.parse(
            'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(link)}'),
    RideShareTarget.email => Uri.parse(
        'mailto:?subject=${Uri.encodeComponent('MotoGo24')}&body=$enc'),
    RideShareTarget.copy => null,
  };
}

/// Spodní panel „Sdílet jízdu" — dlaždice sociálních sítí + kopie do schránky.
/// [text] = vlastní text (cesta — `rideTripShareText`), jinak text jízdy.
Future<void> showRideShareSheet(BuildContext context, UserRide ride, {String? text}) {
  final body = text ?? rideShareText(context, ride);
  final link = _shareLink(ride);

  // v2: světlý panel se stejnými cíli a stejnou akcí (`rideShareTap`).
  if (MgV2.on(context)) return showRideShareSheetV2(context, text: body, link: link);

  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MgSheetTitleRow(center: false, title: Text(
              t(c).tr('rideShareTitle'),
              style: const TextStyle(
                  fontSize: MotoGoTypo.sizeH3,
                  fontWeight: MotoGoTypo.w900,
                  color: MotoGoColors.black,
                  decoration: TextDecoration.none),
            )),
            const SizedBox(height: 4),
            Text(
              t(c).tr('rideShareSub'),
              style: const TextStyle(
                  fontSize: MotoGoTypo.sizeBase,
                  fontWeight: MotoGoTypo.w600,
                  color: MotoGoColors.g500,
                  height: 1.4,
                  decoration: TextDecoration.none),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final target in RideShareTarget.values)
                  _tile(c, target, body, link),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _tile(BuildContext context, RideShareTarget target, String text, String link) {
  final label =
      target == RideShareTarget.copy ? t(context).tr('rideShareCopy') : target.label;
  return GestureDetector(
    onTap: () => rideShareTap(context, target, text, link),
    child: Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: MotoGoColors.greenPale,
        borderRadius: BorderRadius.circular(MotoGoRadius.xl),
        border: Border.all(color: MotoGoColors.green, width: 1.2),
      ),
      child: Column(
        children: [
          Text(target.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: MotoGoTypo.sizeMd,
                fontWeight: MotoGoTypo.w800,
                color: MotoGoColors.greenDarker,
                decoration: TextDecoration.none),
          ),
        ],
      ),
    ),
  );
}

/// Klepnutí na cíl sdílení (zavře panel, kopie / odkaz; sdílí stará i v2
/// dlaždice). [context] = kontext panelu.
Future<void> rideShareTap(BuildContext context, RideShareTarget target, String text, String link) async {
  final messenger = ScaffoldMessenger.of(context);
  final copied = t(context).tr('rideShareCopied');
  final failed = t(context).tr('rideShareFailed');
  Navigator.of(context).pop();
  if (target == RideShareTarget.copy) {
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(copied)));
    return;
  }
  final uri = _shareUri(target, text, link);
  if (uri == null) {
    messenger.showSnackBar(SnackBar(content: Text(failed)));
    return;
  }
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(failed)));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}
