import 'package:flutter/material.dart';

import '../../core/friendly_error.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/native/gps_service.dart';
import '../../core/theme.dart';
import '../../core/widgets/error_feedback.dart';

/// Stav polohy / výpočtu trasy v navigaci (2026-10-16): dřív navigace při
/// ztrátě GPS tiše zamrzla na poslední poloze a bez internetu potichu kreslila
/// spojnici bodů jako by to byla silnice.
enum NavStatus { denied, serviceOff, gpsLost, weakGps, straightLine }

class NavStatusBanner extends StatelessWidget {
  final NavStatus status;

  /// „Povolit polohu" = systémový dialog (jen když ho systém ještě ukáže).
  final VoidCallback? onRequest;
  const NavStatusBanner({super.key, required this.status, this.onRequest});

  static NavStatus? fromGps(GpsStatus? s) => switch (s) {
        GpsStatus.serviceOff => NavStatus.serviceOff,
        GpsStatus.denied || GpsStatus.deniedForever => NavStatus.denied,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final (icon, key) = switch (status) {
      NavStatus.denied => ('📍', 'eoNavNoPerm'),
      NavStatus.serviceOff => ('📍', 'eoNavLocOff'),
      NavStatus.gpsLost => ('🛰️', 'eoNavGpsLost'),
      NavStatus.weakGps => ('🛰️', 'eoNavWeakGps'),
      NavStatus.straightLine => ('📡', 'eoNavStraightLine'),
    };
    final settings = status == NavStatus.denied ||
        status == NavStatus.serviceOff ||
        status == NavStatus.gpsLost;
    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(MotoGoRadius.xl),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr.tr(key),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: MotoGoTypo.w600,
                    color: MotoGoColors.black,
                    decoration: TextDecoration.none)),
          ),
          if (status == NavStatus.denied && onRequest != null)
            TextButton(onPressed: onRequest, child: Text(tr.tr('eoNavAllow')))
          else if (settings)
            TextButton(
              onPressed: () => openFixSettings(FriendlyError(status == NavStatus.denied
                  ? FriendlyKind.permission
                  : FriendlyKind.locationOff)),
              child: Text(tr.tr('eoOpenSettings')),
            ),
        ]),
      ),
    );
  }
}
