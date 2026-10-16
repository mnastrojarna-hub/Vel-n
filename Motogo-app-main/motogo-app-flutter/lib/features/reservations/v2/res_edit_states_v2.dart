import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_screen.dart';
import '../../../core/widgets/pickup_location_link.dart';
import '../../../core/widgets/state_views.dart';

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
          ? MgLoadingView(onBack: onBack)
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
        if (pickup != null) PickupLocationLink(info: pickup!, dark: false, center: true),
      ],
    );
  }
}
