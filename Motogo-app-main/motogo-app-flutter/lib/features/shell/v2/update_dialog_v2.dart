import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_dialog.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// Forced update in the v2 look (Stavy 19.2 "Je potřeba aktualizovat") as
/// the SAME non-dismissible dialog (the caller keeps `barrierDismissible:
/// false` + `PopScope(canPop: false)`): warn disc, title, why, the
/// store-open failure as an error banner, the emergency line with today's
/// two calls and ONE ink "Aktualizovat" → [onUpdate] (the old handler).
class UpdateForceDialogV2 extends StatelessWidget {
  final String version;
  final bool storeFailed;
  final VoidCallback onUpdate;
  final VoidCallback onCall;
  final VoidCallback onCall112;
  const UpdateForceDialogV2({
    super.key,
    required this.version,
    required this.storeFailed,
    required this.onUpdate,
    required this.onCall,
    required this.onCall112,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgDialogFrame(
      content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: MgToneDisc(tone: MgTone.warn, size: 56, icon: MgIcons.download),
        ),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: MgWordFit(
            minScale: 0.75,
            child: Text(tr.tr('v2UxShUpdReqTitle'), style: MgType.h3.copyWith(color: MgColors.ink)),
          ),
        ),
        const SizedBox(height: 8),
        Text(tr.trArgs('v2UxShUpdReqBody', {'version': version}),
            style: MgType.body.copyWith(color: MgColors.body2)),
        if (storeFailed) ...[
          const SizedBox(height: 12),
          MgStateBanner(tone: MgTone.err, title: tr.tr('eoStoreOpenFail')),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          decoration: BoxDecoration(
            color: MgColors.well,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MgColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr.tr('eoUpdateEmergency'), style: MgType.small.copyWith(color: MgColors.meta)),
            Wrap(spacing: 4, children: [
              MgBtnText(
                key: const ValueKey('upd-call'),
                label: tr.tr('eoCallNonstop'),
                icon: MgIcons.phone,
                onTap: onCall,
              ),
              MgBtnText(
                key: const ValueKey('upd-112'),
                label: tr.tr('v2UxShCall112'),
                icon: MgIcons.phone,
                color: MgColors.sos,
                onTap: onCall112,
              ),
            ]),
          ]),
        ),
      ]),
      action: MgBtnInk(key: const ValueKey('upd-now'), label: tr.tr('v2UxShUpdBtn'), onTap: onUpdate),
    );
  }
}

/// Optional update (Stavy 19.3 "Je tu nová verze"): T6 dialog, "Později"
/// ghost left → [onLater], "Aktualizovat" ink right → [onUpdate] — the old
/// dialog's two handlers.
class UpdateOfferDialogV2 extends StatelessWidget {
  final String version;
  final VoidCallback onLater;
  final VoidCallback onUpdate;
  const UpdateOfferDialogV2({super.key, required this.version, required this.onLater, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final later = tr.tr('updateLater');
    final now = tr.tr('v2UxShUpdBtn');
    return MgDialogFrame(
      title: tr.tr('v2UxShUpdNewTitle'),
      body: tr.trArgs('v2UxShUpdNewBody', {'version': version}),
      safe: MgBtnGhostLight(key: const ValueKey('upd-later'), label: later, onTap: onLater),
      action: MgBtnInk(key: const ValueKey('upd-now'), label: now, onTap: onUpdate),
      safeLabel: later,
      actionLabel: now,
    );
  }
}
