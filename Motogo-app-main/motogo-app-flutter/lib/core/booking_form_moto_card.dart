import 'package:flutter/material.dart';

import '../features/catalog/moto_model.dart';
import '../features/booking/booking_ui_helpers.dart';
import 'i18n/i18n_provider.dart';

/// Card showing the selected motorcycle summary inside the booking form.
class BookingFormMotoCard extends StatelessWidget {
  const BookingFormMotoCard({super.key, required this.moto});

  final Motorcycle moto;

  @override
  Widget build(BuildContext context) {
    return bookingCard(
      1,
      t(context).motorcycle.toUpperCase(),
      Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            moto.displayImage,
            width: 56,
            height: 42,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 56,
              height: 42,
              color: const Color(0xFFD4E8E0),
              child: const Icon(
                Icons.motorcycle,
                size: 20,
                color: Color(0xFF8AAB99),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                moto.model,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.none,
                ),
              ),
              Text(
                t(context).tr('motoFromPrice').replaceAll('{price}', moto.priceLabel),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8AAB99),
                  decoration: TextDecoration.none,
                ),
              ),
              if (moto.branchName != null)
                Row(children: [
                  const Icon(Icons.location_on,
                      size: 12, color: Color(0xFFEF4444)),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      'Pobočka: ${moto.branchName}'
                      '${moto.branchCity != null ? ", ${moto.branchCity}" : ""}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF8AAB99),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ]),
            ],
          ),
        ),
      ]),
    );
  }
}
