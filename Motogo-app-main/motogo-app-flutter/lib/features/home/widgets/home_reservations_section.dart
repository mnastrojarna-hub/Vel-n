import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/router.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../reservations/reservation_models.dart';
import 'home_reservation_card.dart';

/// Shows active reservations list (or empty-state placeholder) and optional SOS button.
class HomeReservationsSection extends StatelessWidget {
  final List<Reservation> activeReservations;

  const HomeReservationsSection({
    super.key,
    required this.activeReservations,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ===== ACTIVE RESERVATIONS or NO RESERVATION PLACEHOLDER =====
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    t(context).tr('homeActiveReservations'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: MotoGoColors.black,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.go(Routes.reservations),
                    child: Text(
                      t(context).tr('homeViewAll'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: MotoGoColors.greenDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (activeReservations.isNotEmpty)
                ...activeReservations
                    .take(2)
                    .map((r) => HomeReservationCard(reservation: r))
              else
                GestureDetector(
                  onTap: () => context.go(Routes.search),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: MotoGoColors.g200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.motorcycle, size: 28, color: MotoGoColors.g400),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t(context).tr('homeNoActiveReservation'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: MotoGoColors.black,
                                ),
                              ),
                              Text(
                                t(context).tr('homeBookMotorcycle'),
                                style: const TextStyle(fontSize: 12, color: MotoGoColors.g400),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: MotoGoColors.g400),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ===== SOS BUTTON (only when an active reservation exists) =====
        if (activeReservations.any((r) => r.displayStatus == ResStatus.aktivni))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: GestureDetector(
              onTap: () => context.push(Routes.sos),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: MotoGoColors.red,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text('🆘', style: TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t(context).tr('homeSosTitle'),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            t(context).tr('homeSosSubtitle'),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Text('›', style: TextStyle(fontSize: 16, color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
