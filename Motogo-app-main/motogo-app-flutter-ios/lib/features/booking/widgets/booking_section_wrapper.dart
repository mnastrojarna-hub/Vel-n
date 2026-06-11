import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Wraps a form section with a numbered header and card styling.
Widget bookingSecWrapper(int n, String title, Widget content) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: MotoGoColors.green,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$n',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: MotoGoColors.black,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            content,
          ],
        ),
      ),
    );

/// Reusable checkbox row used in consents section.
Widget bookingCheckbox(
  String label,
  bool val,
  ValueChanged<bool> cb,
) {
  return GestureDetector(
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
        child: val
            ? const Icon(Icons.check, size: 14, color: Colors.black)
            : null,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: MotoGoColors.g600,
          ),
        ),
      ),
    ]),
  );
}
