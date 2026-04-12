import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Checkbox consent row used for VOP and GDPR agreements.
Widget buildBookingFormConsent(
  String label,
  bool val,
  ValueChanged<bool> cb,
) =>
    GestureDetector(
      onTap: () => cb(!val),
      child: Row(children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: val ? MotoGoColors.green : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: val ? MotoGoColors.green : MotoGoColors.g200,
              width: 2,
            ),
          ),
          child: val ? const Icon(Icons.check, size: 14, color: Colors.black) : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MotoGoColors.g600),
          ),
        ),
      ]),
    );
