import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../../gear_rental/gear_contract.dart';
import '../../gear_rental/gear_offer_provider.dart';

/// „Půjčit samotnou výbavu“ na staré Domů — řádek ve stylu karty „Žádná
/// aktivní rezervace“ → `/gear-rental`. Zobrazí se za stejných podmínek
/// jako v novém vzhledu (služba zapnutá a viditelná v appce, pobočka dnes
/// otevřená); při načítání a chybě se nevykreslí.
class HomeGearRow extends ConsumerWidget {
  const HomeGearRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(gearRentEntryProvider).valueOrNull != true) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GestureDetector(
        key: const ValueKey('home-gear-row-old'),
        onTap: () => context.push(kGearRentalRoute),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MotoGoColors.g200),
          ),
          child: Row(children: [
            const Icon(Icons.checkroom, size: 28, color: MotoGoColors.g400),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  t(context).tr('gearRentCta'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MotoGoColors.black),
                ),
                Text(
                  t(context).tr('gearRentSub'),
                  style: const TextStyle(fontSize: 12, color: MotoGoColors.g400),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right, color: MotoGoColors.g400),
          ]),
        ),
      ),
    );
  }
}
