import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../auth/auth_provider.dart';
import '../../booking/booking_validator.dart';
import '../../reservations/reservation_provider.dart';
import '../moto_model.dart';

/// Red warning banner shown when license or overlap validation fails.
class ValidationBanner extends ConsumerWidget {
  final Motorcycle moto;
  final DateTime startDate;
  final DateTime endDate;
  const ValidationBanner({
    super.key,
    required this.moto,
    required this.startDate,
    required this.endDate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // License check
    final profile = ref.watch(profileProvider).valueOrNull;
    final userGroups = <String>[];
    if (profile != null) {
      final raw = profile['license_group'];
      if (raw is List) {
        for (final g in raw) {
          if (g != null) userGroups.add(g.toString());
        }
      }
    }
    final licenseErr = BookingValidator.checkLicense(
      userLicenseGroups: userGroups,
      motoLicense: moto.licenseRequired,
    );

    // Overlap check
    final reservations = ref.watch(reservationsProvider).valueOrNull ?? [];
    final overlapErr = BookingValidator.checkOverlap(
      userReservations: reservations,
      startDate: startDate,
      endDate: endDate,
      isChildrensMoto: moto.licenseRequired == 'N',
    );

    final errors = [
      if (licenseErr != null) licenseErr,
      if (overlapErr != null) overlapErr,
    ];
    if (errors.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MotoGoColors.red.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final err in errors) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 18, color: MotoGoColors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    err,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: MotoGoColors.red,
                    ),
                  ),
                ),
              ]),
              if (err != errors.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
