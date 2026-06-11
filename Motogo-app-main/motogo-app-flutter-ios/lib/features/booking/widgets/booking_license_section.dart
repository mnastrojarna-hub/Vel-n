import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import 'booking_section_wrapper.dart';

/// Section 4 – Driver's license info + validation error.
Widget bookingLicenseSection(BuildContext context, String? err) {
  return bookingSecWrapper(
    4,
    t(context).tr('driverLicense'),
    Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MotoGoColors.g100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.credit_card, size: 18, color: MotoGoColors.g400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t(context).tr('profileData'),
              style: const TextStyle(fontSize: 12, color: MotoGoColors.g600),
            ),
          ),
        ]),
      ),
      if (err != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MotoGoColors.redBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: MotoGoColors.red.withValues(alpha: 0.3),
              ),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber, size: 16,
                  color: MotoGoColors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  err,
                  style: const TextStyle(
                      fontSize: 11, color: MotoGoColors.red),
                ),
              ),
            ]),
          ),
        ),
    ]),
  );
}
