import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Numbered step card used throughout the booking form.
Widget buildBookingFormCard(int step, String title, Widget content) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
  child: Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(color: MotoGoColors.green, shape: BoxShape.circle),
          child: Center(child: Text('$step', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.black))),
        ),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
      ]),
      const SizedBox(height: 12),
      content,
    ]),
  ),
);
