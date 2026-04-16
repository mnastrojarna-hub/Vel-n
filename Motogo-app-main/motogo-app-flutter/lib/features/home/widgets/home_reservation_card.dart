import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../reservations/reservation_models.dart';

/// Active reservation card shown on the home screen — matches Capacitor design.
class HomeReservationCard extends StatelessWidget {
  final Reservation reservation;
  const HomeReservationCard({super.key, required this.reservation});

  String _statusLabel(BuildContext context, ResStatus s) {
    switch (s) {
      case ResStatus.aktivni:
        return t(context).tr('homeStatusActive');
      case ResStatus.nadchazejici:
        return t(context).tr('homeStatusUpcoming');
      case ResStatus.dokoncene:
        return t(context).tr('homeStatusCompleted');
      case ResStatus.cancelled:
        return t(context).tr('homeStatusCancelled');
    }
  }

  Color _statusColor(ResStatus s) {
    switch (s) {
      case ResStatus.aktivni:
        return MotoGoColors.green;
      case ResStatus.nadchazejici:
        return MotoGoColors.greenDark;
      case ResStatus.dokoncene:
        return MotoGoColors.g400;
      case ResStatus.cancelled:
        return MotoGoColors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = reservation.displayStatus;

    return GestureDetector(
      onTap: () => context.push('/reservations/${reservation.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MotoGoColors.g200),
        ),
        child: Row(
          children: [
            // Moto thumbnail
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: MotoGoColors.g100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: reservation.motoImage != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        reservation.motoImage!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.motorcycle,
                          color: MotoGoColors.g400,
                        ),
                      ),
                    )
                  : const Icon(Icons.motorcycle, color: MotoGoColors.g400),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reservation.motoName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: MotoGoColors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${reservation.shortId} · ${_statusLabel(context, status) == 'PŘIPRAVENO' ? 'Nadcházející' : reservation.dateRange}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: MotoGoColors.g400,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: _statusColor(status).withValues(alpha: 0.3)),
              ),
              child: Text(
                _statusLabel(context, status),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _statusColor(status),
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
