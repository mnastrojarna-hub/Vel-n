import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';

/// Keeps the focused field above the keyboard on a page that does NOT
/// resize for it (the checkout keeps `resizeToAvoidBottomInset: false`):
/// when focus moves into this subtree or the keyboard grows, the field is
/// scrolled to the upper part of the page (`Scrollable.ensureVisible`).
class CheckoutFocusScrollV2 extends StatefulWidget {
  final Widget child;
  const CheckoutFocusScrollV2({super.key, required this.child});

  @override
  State<CheckoutFocusScrollV2> createState() => _CheckoutFocusScrollV2State();
}

class _CheckoutFocusScrollV2State extends State<CheckoutFocusScrollV2> {
  double _inset = 0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_reveal);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_reveal);
    super.dispose();
  }

  void _reveal() {
    final f = FocusManager.instance.primaryFocus?.context;
    if (f == null || !mounted || f.findAncestorStateOfType<_CheckoutFocusScrollV2State>() != this) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !f.mounted) return;
      Scrollable.ensureVisible(f,
          alignment: 0.15, duration: MgMotion.of(context, MgMotion.sheet), curve: MgMotion.out);
    });
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset > _inset + 1) _reveal();
    _inset = inset;
    return widget.child;
  }
}

/// v2 look of the e-shop checkout (Profil board "Doručovací údaje", kept
/// as the existing route — OD-PS-09): compact dark app bar (the screen's
/// guarded back), the screen's own sections (shipping with its reveal key,
/// payment, promo, summary, rounding note — each in its v2 look) and the
/// dock "ZAPLATIT · {total}" with a lock, busy spinner inside. The page
/// does not resize for the keyboard; the focused field is scrolled above
/// it instead.
class CheckoutViewV2 extends StatelessWidget {
  final List<Widget> sections;
  final String label;
  final String? price;
  final bool processing;
  final VoidCallback onPay;
  final VoidCallback onBack;

  const CheckoutViewV2({
    super.key,
    required this.sections,
    required this.label,
    required this.price,
    required this.processing,
    required this.onPay,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Scaffold(
      backgroundColor: MgColors.canvas,
      resizeToAvoidBottomInset: false,
      body: CheckoutFocusScrollV2(
        child: MgPage(
          header: MgAppBar(title: tr.tr('checkout'), subtitle: tr.tr('v2UxPsCompleteOrder'), onBack: onBack),
          overlapHero: false,
          overscrollColor: MgColors.night,
          sections: [
            Padding(
              padding: const EdgeInsets.fromLTRB(MgSpace.gutter, MgSpace.s16, MgSpace.gutter, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sections),
            ),
          ],
          slivers: [SliverToBoxAdapter(child: SizedBox(height: MediaQuery.viewInsetsOf(context).bottom))],
          dock: MgDock(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              MgCta(
                key: const ValueKey('checkout-v2-pay'),
                label: label,
                price: price,
                leadingIcon: MgIcons.lock,
                busy: processing,
                onTap: processing ? null : onPay,
                size: MgCtaSize.md56,
              ),
              const SizedBox(height: 6),
              Text('${tr.tr('securePayment')} · Stripe PCI DSS Level 1',
                  textAlign: TextAlign.center, style: MgType.meta.copyWith(color: MgColors.onDarkMeta)),
            ]),
          ),
        ),
      ),
    );
  }
}
