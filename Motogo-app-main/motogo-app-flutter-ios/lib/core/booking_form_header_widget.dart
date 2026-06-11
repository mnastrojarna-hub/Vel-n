import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/booking/booking_models.dart';
import '../features/catalog/moto_model.dart';
import 'i18n/i18n_provider.dart';

/// Top header bar for the booking form screen.
class BookingFormHeader extends StatelessWidget {
  const BookingFormHeader({
    super.key,
    required this.draft,
    required this.moto,
  });

  final BookingDraft draft;
  final Motorcycle moto;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1A2E22),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              GoRouter.of(context).go(
                draft.motoId != null ? '/moto/${draft.motoId}' : '/search',
              );
            }
          },
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF74FB71),
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
                t(context).tr('bookingFor').replaceAll('{model}', moto.model),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                ),
              ),
              Text(
                t(context).tr('fillForm'),
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white54,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
