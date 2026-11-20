import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../gear_rental/gear_contract.dart';
import '../../gear_rental/gear_offer_provider.dart';
import 'home_offer_block_v2.dart' show HomeLinkRow;

/// "Půjčit samotnou výbavu" on Domů (owner 2026-11-19): one row in the
/// style of "Spočítat přesnou cenu" / "Zaznamenat jízdu" (dark 40 px tile,
/// neon icon) → `/gear-rental`. Shown only while the service is on and
/// visible in the app (`gear_rental.enabled && app_visible`) and a branch
/// is offered — all year like the web (closed days are only unselectable
/// in the order calendar); hidden while loading or on error.
class HomeGearRowV2 extends ConsumerWidget {
  const HomeGearRowV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(gearRentEntryProvider).valueOrNull != true) return const SizedBox.shrink();
    final tr = t(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: MgCard(
        key: const ValueKey('home-gear-row'),
        padding: EdgeInsets.zero,
        child: HomeLinkRow(
          icon: MgIcons.helmet,
          title: tr.tr('gearRentCta'),
          sub: tr.tr('gearRentSub'),
          onTap: () => context.push(kGearRentalRoute),
        ),
      ),
    );
  }
}
