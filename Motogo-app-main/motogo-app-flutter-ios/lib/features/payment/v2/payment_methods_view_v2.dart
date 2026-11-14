import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_fold_header.dart';
import '../../../core/v2/chrome/mg_hide_on_scroll.dart' show MgBarsHost;
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../payment_provider.dart';
import 'card_visual_v2.dart';

/// v2 look of "Platební metody" (Profil board), shared by both platform
/// files: compact dark app bar (the screen's own back), the saved cards
/// drawn as cards with the existing "Nastavit jako prioritní" / "Odebrat"
/// actions, an empty state as T3 info and the Stripe note. [onAdd] = the
/// Android "add card" sheet; null on iOS — iOS NEVER offers manual card
/// entry (App Store 5.1.1 / PCI), cards are saved at checkout there.
/// [body] = the screen's loading / error view (already v2 via
/// state_views) when the list is not ready. Pull-to-refresh = [onRefresh]
/// (the existing retry).
class PaymentMethodsViewV2 extends StatelessWidget {
  final List<SavedCard>? cards;
  final Widget? body;
  final VoidCallback onBack;
  final Future<void> Function() onRefresh;
  final void Function(SavedCard) onDelete;
  final void Function(SavedCard) onSetDefault;
  final VoidCallback? onAdd;
  final String emptyNote;
  final String? footNote;

  const PaymentMethodsViewV2({
    super.key,
    required this.cards,
    this.body,
    required this.onBack,
    required this.onRefresh,
    required this.onDelete,
    required this.onSetDefault,
    required this.onAdd,
    required this.emptyNote,
    this.footNote,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final list = cards;
    final header = MgAppBar(title: tr.tr('paymentMethodsTitle'), onBack: onBack);
    if (list == null) {
      return Material(
        color: MgColors.canvas,
        // Hide-on-scroll: the app bar folds while a scrolling state scrolls.
        child: MgBarsHost(
          child: Column(children: [MgFoldHeader(child: header), Expanded(child: body ?? const SizedBox.shrink())]),
        ),
      );
    }
    final add = onAdd;
    return MgPage(
      header: header,
      overlapHero: false,
      overscrollColor: MgColors.night,
      onRefresh: onRefresh,
      sections: [
        Padding(
          padding: const EdgeInsets.fromLTRB(MgSpace.gutter, MgSpace.s16, MgSpace.gutter, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (list.isEmpty) MgStateBanner(tone: MgTone.info, icon: MgIcons.card, title: tr.tr('noSavedCards'), text: emptyNote),
            for (final c in list) ...[
              SavedCardV2(
                card: c,
                onDelete: () => onDelete(c),
                // The star existed only for non-priority cards with a Stripe id.
                onSetDefault: !c.isDefault && c.stripeId.isNotEmpty ? () => onSetDefault(c) : null,
              ),
              const SizedBox(height: MgSpace.s12),
            ],
            if (footNote != null) ...[
              const SizedBox(height: MgSpace.s8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 1), child: MgIcon(MgIcons.lock, size: 14, color: MgColors.meta)),
                const SizedBox(width: 6),
                Expanded(child: Text(footNote!, style: MgType.small.copyWith(color: MgColors.meta))),
              ]),
            ],
          ]),
        ),
      ],
      dock: add == null
          ? null
          : MgDock(
              child: MgCta(
                key: const ValueKey('pm-v2-add'),
                label: tr.tr('addNewCard'),
                leadingIcon: MgIcons.plus,
                onTap: add,
                size: MgCtaSize.md56,
              ),
            ),
    );
  }
}
