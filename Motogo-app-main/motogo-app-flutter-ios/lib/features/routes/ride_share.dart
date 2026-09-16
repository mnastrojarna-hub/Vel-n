import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import 'ride_card.dart' show rideDate, rideDuration;
import 'ride_model.dart';
import 'route_export.dart';

/// Sdílení projeté jízdy na sociální sítě.
///
/// Sdílí se POPIS jízdy + odkaz na její stopu v Mapy.com (příjemce ji vidí
/// na mapě, nemusí mít appku). Sdílení je čistě na jezdci — z appky nic
/// neodchází samo a jízdu ostatní neuvidí, dokud ji sám nezveřejní.

/// Zjednodušená stopa pro odkaz do map (max ~12 bodů — delší URL nevezmou).
List<LatLng> rideShareWaypoints(UserRide ride) {
  final pts = ride.mapPoints;
  if (pts.length <= 12) return pts;
  final step = (pts.length / 11).ceil();
  final out = <LatLng>[];
  for (var i = 0; i < pts.length; i += step) {
    out.add(pts[i]);
  }
  if (out.last != pts.last) out.add(pts.last);
  return out;
}

/// Text sdílení — název, statistiky a odkaz na mapu.
String rideShareText(BuildContext context, UserRide ride) {
  final pts = rideShareWaypoints(ride);
  final link = pts.length >= 2 ? RouteExport.mapy(pts).toString() : '';
  final parts = <String>[
    '🏍️ ${ride.name.isNotEmpty ? ride.name : t(context).tr('rideUntitled')}',
    [
      '${ride.distanceKm.toStringAsFixed(ride.distanceKm < 10 ? 1 : 0)} km',
      if (ride.durationMin != null) rideDuration(ride.durationMin!),
      rideDate(ride.startedAt),
    ].join(' · '),
    if ((ride.description ?? '').isNotEmpty) ride.description!,
    if (link.isNotEmpty) link,
    t(context).tr('rideShareFooter'),
  ];
  return parts.join('\n');
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
Future<void> showRideShareSheet(BuildContext context, UserRide ride) {
  final text = rideShareText(context, ride);
  final pts = rideShareWaypoints(ride);
  final link = pts.length >= 2 ? RouteExport.mapy(pts).toString() : '';

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
            Text(
              t(c).tr('rideShareTitle'),
              style: const TextStyle(
                  fontSize: MotoGoTypo.sizeH3,
                  fontWeight: MotoGoTypo.w900,
                  color: MotoGoColors.black,
                  decoration: TextDecoration.none),
            ),
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
                  _tile(c, target, text, link),
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
    onTap: () async {
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
    },
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
