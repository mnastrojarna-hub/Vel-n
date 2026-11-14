import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_state_screen.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/widgets/pickup_location_link.dart';
import '../../../core/widgets/state_views.dart';
import 'res_skeletons_v2.dart';

/// v2 look of `EditStateScaffold` (loading / load error of the edit): the
/// shared v2 state views with the SAME back, retry and texts.
class EditStateV2 extends StatelessWidget {
  final VoidCallback onBack;
  final String? error;
  final VoidCallback? onRetry;
  const EditStateV2({super.key, required this.onBack, this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgStateScaffold(
      title: tr.tr('editReservation'),
      onBack: onBack,
      child: error == null
          // Kostra výběru úprav (žádný holý spinner); po 15 s „trvá to déle".
          ? ResEditSkeletonV2(onBack: onBack)
          : MgErrorView(
              what: error,
              message: tr.tr('v2ResEditLoadHelp'),
              contact: false,
              onRetry: onRetry,
              onBack: onBack,
              backLabel: tr.tr('psBackToRes'),
            ),
    );
  }
}

/// v2 look of `EditConfirmPage` (Stavy T1): ✓ (or ↺ for a refund) with the
/// SAME title / message, the pickup branch link and the SAME way out
/// (→ Rezervace, also from the ✕).
class EditConfirmV2 extends StatelessWidget {
  final String title;
  final String message;
  final bool isRefund;
  final PickupInfo? pickup;
  final VoidCallback onDone;
  const EditConfirmV2({
    super.key,
    required this.title,
    required this.message,
    required this.isRefund,
    required this.pickup,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgStateScreen(
      tone: MgTone.ok,
      title: title,
      why: message,
      icon: isRefund ? MgIcons.refresh : null,
      onClose: onDone,
      support: false,
      primary: MgStateAction(tr.tr('backToReservations'), onDone),
      children: [
        if (pickup != null) EditPickupCardV2(info: pickup!),
      ],
    );
  }
}

/// "K vyzvednutí" on the edit result (Stavy T1): white card with the pin
/// tile, branch + address and "Otevřít v mapě" (the SAME `openPickupMap`
/// as `PickupLocationLink`), plus the gate arrival notice where the branch
/// has a gate (same provider, texts 1:1).
class EditPickupCardV2 extends ConsumerWidget {
  final PickupInfo info;
  const EditPickupCardV2({super.key, required this.info});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final branchId = info.branchId;
    final hasGate = branchId != null && (ref.watch(branchHasGateProvider(branchId)).valueOrNull ?? false);
    final name = (info.name ?? '').trim();
    final address = (info.address ?? '').trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MgColors.line),
          boxShadow: MgShadows.card,
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const MgIconTileLight(MgIcons.pin),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr.tr('confirmPickupTitle'), style: MgType.meta.copyWith(color: MgColors.meta)),
              if (name.isNotEmpty) Text(name, style: MgType.title.copyWith(color: MgColors.ink)),
              if (address.isNotEmpty) Text(address, style: MgType.small.copyWith(color: MgColors.lead)),
              MgBtnText(label: tr.tr('openInMap'), icon: MgIcons.map, onTap: () => openPickupMap(info)),
            ]),
          ),
        ]),
      ),
      if (hasGate) ...[
        const SizedBox(height: 12),
        MgStateBanner(tone: MgTone.warn, icon: MgIcons.lock, title: tr.tr('gateNoticeTitle'), text: tr.tr('gateNotice')),
      ],
    ]);
  }
}
