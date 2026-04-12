import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Radio-style selection tile for pickup/return method.
Widget buildBookingFormRadioTile(
  String label,
  String sublabel,
  String price,
  bool selected,
  VoidCallback onTap,
) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? MotoGoColors.greenPale : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? MotoGoColors.green : MotoGoColors.g200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? MotoGoColors.green : MotoGoColors.g400, width: 2),
            ),
            child: selected
                ? Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: MotoGoColors.green),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text(sublabel, style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
            ]),
          ),
          Text(
            price,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selected ? MotoGoColors.greenDarker : MotoGoColors.g400,
            ),
          ),
        ]),
      ),
    );
