import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import 'ride_card.dart';
import 'ride_provider.dart';

/// Projeté jízdy k jedné výpůjčce — zobrazuje se v detailu rezervace
/// (historie zákazníka). Jízdy vznikly automaticky během půjčení, když měl
/// zákazník povolenou polohu. Když žádná není, sekce se vůbec nevykreslí.
class BookingRidesSection extends ConsumerWidget {
  final String bookingId;

  const BookingRidesSection({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rides = ref.watch(bookingRidesProvider(bookingId)).valueOrNull ?? const [];
    if (rides.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '🏍️ ${t(context).tr('rideBookingSection')}',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: MotoGoColors.g400,
              letterSpacing: 0.5,
            ),
          ),
        ),
        for (final r in rides) RideCard(ride: r),
      ],
    );
  }
}
