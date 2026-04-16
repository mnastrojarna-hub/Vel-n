import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../catalog/moto_model.dart';
import 'booking_section_wrapper.dart';

/// Section 1 – Motorka (motorcycle info card).
Widget bookingMotoSection(Motorcycle moto) {
  return bookingSecWrapper(
    1,
    'MOTORKA',
    Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          moto.displayImage,
          width: 48,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 48,
            height: 36,
            color: MotoGoColors.g200,
            child: const Icon(Icons.motorcycle, size: 18,
                color: MotoGoColors.g400),
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
              ),
            ),
            Text(
              'od ${moto.priceLabel}/den · záloha neúčtována',
              style: const TextStyle(fontSize: 11, color: MotoGoColors.g400),
            ),
            if (moto.branchName != null)
              Row(children: [
                const Icon(Icons.location_on, size: 12, color: MotoGoColors.red),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    '${moto.branchName}'
                    '${moto.branchCity != null ? ', ${moto.branchCity}' : ''}',
                    style: const TextStyle(
                        fontSize: 10, color: MotoGoColors.g400),
                  ),
                ),
              ]),
          ],
        ),
      ),
    ]),
  );
}
