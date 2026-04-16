import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// A single label/value row in the price summary section.
Widget buildBookingFormPriceRow(
  String label,
  String value, {
  bool subtle = false,
  Color? color,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: subtle ? FontWeight.w500 : FontWeight.w600,
            color: subtle ? MotoGoColors.g400 : MotoGoColors.g600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: color != null ? FontWeight.w800 : FontWeight.w600,
            color: color ?? (subtle ? MotoGoColors.g400 : MotoGoColors.black),
          ),
        ),
      ]),
    );
