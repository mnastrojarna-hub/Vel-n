import 'package:flutter/material.dart';

import '../../core/friendly_error.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/error_feedback.dart';
import 'ride_recorder.dart';

/// Hláška k ručnímu startu záznamu jízdy: co je špatně a jak to opravit
/// (dřív pro všechno „přihlas se a povol polohu", i když chyběl internet).
void showRideStartResult(ScaffoldMessengerState msg, AppTranslations tr, RideStartResult r) {
  final key = switch (r) {
    RideStartResult.ok => 'rideManualStarted',
    RideStartResult.notSignedIn => 'eoRideNotSignedIn',
    RideStartResult.locationOff => 'eoRideLocOff',
    RideStartResult.noPermission => 'eoRideNoPerm',
    RideStartResult.imprecise => 'eoRideImprecise',
    RideStartResult.failed => 'eoRideStartFailed',
  };
  final settings = r == RideStartResult.locationOff ||
      r == RideStartResult.noPermission ||
      r == RideStartResult.imprecise;
  msg
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(tr.tr(key)),
      duration: Duration(seconds: r == RideStartResult.ok ? 4 : 8),
      action: settings
          ? SnackBarAction(
              label: tr.tr('eoOpenSettings'),
              textColor: MotoGoColors.green,
              onPressed: () => openFixSettings(FriendlyError(
                  r == RideStartResult.locationOff
                      ? FriendlyKind.locationOff
                      : FriendlyKind.permission)),
            )
          : null,
    ));
}

/// Pruh „Záznam jízdy stojí – poloha je vypnutá" (Moje zážitky).
class RideGpsLostBanner extends StatelessWidget {
  const RideGpsLostBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MotoGoColors.amberBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MotoGoColors.amberBorder),
      ),
      child: Row(children: [
        const Text('📍', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(tr.tr('eoRideGpsLost'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.35)),
        ),
        TextButton(
          onPressed: () => openFixSettings(const FriendlyError(FriendlyKind.locationOff)),
          child: Text(tr.tr('eoOpenSettings')),
        ),
      ]),
    );
  }
}
