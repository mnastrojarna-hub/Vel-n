import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../catalog/moto_model.dart';
import '../booking_models.dart';

/// Top header bar for the booking form screen.
class BookingFormHeader extends StatelessWidget {
  const BookingFormHeader({
    super.key,
    required this.moto,
    required this.draft,
  });

  final Motorcycle moto;
  final BookingDraft draft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        color: MotoGoColors.dark,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => context.go(
            draft.motoId != null ? '/moto/${draft.motoId}' : '/search'),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: MotoGoColors.green,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back, size: 20, color: Colors.black),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rezervace: ${moto.model}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const Text(
                'Vyplňte formulář pro rezervaci',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
