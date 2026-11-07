import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_choice_card.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../booking/booking_models.dart' show AppliedDiscount, DiscountType;
import '../../payment/v2/pay_parts_v2.dart' show PayCardV2, PayEyebrowV2, PayRowV2;
import '../shop_models.dart';

/// "Doprava" of the v2 checkout (Profil board "Doručovací údaje"): two
/// option cards (post / pickup — the existing provider), and for post the
/// prefilled address as one collapsed row (tap = the existing inline
/// fields, as today). Controllers and the open flag are the section's.
class CheckoutShippingV2 extends StatelessWidget {
  final ShipMode mode;
  final VoidCallback onPost;
  final VoidCallback onPickup;
  final bool addressOpen;
  final VoidCallback onToggle;
  final Listenable fields;
  final String Function() summary;
  final TextEditingController name, street, zip, city;

  const CheckoutShippingV2({
    super.key,
    required this.mode,
    required this.onPost,
    required this.onPickup,
    required this.addressOpen,
    required this.onToggle,
    required this.fields,
    required this.summary,
    required this.name,
    required this.street,
    required this.zip,
    required this.city,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    InputDecoration dec(String l) => mgInputDecoration(context, label: l);
    return Padding(
      padding: const EdgeInsets.only(bottom: MgSpace.s12),
      child: PayCardV2(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PayEyebrowV2(tr.tr('v2UxPsShipping')),
          const SizedBox(height: MgSpace.s10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: MgChoiceCard(
                  title: tr.tr('shippingByPost'),
                  sub: tr.tr('shippingPostInfo'),
                  icon: MgIcons.truck,
                  selected: mode == ShipMode.post,
                  onTap: onPost,
                ),
              ),
              const SizedBox(width: MgSpace.s8),
              Expanded(
                child: MgChoiceCard(
                  title: tr.tr('personalPickup'),
                  sub: tr.tr('personalPickupInfo'),
                  icon: MgIcons.pin,
                  selected: mode == ShipMode.pickup,
                  onTap: onPickup,
                ),
              ),
            ]),
          ),
          if (mode == ShipMode.post) ...[
            const SizedBox(height: MgSpace.s10),
            Semantics(
              button: true,
              expanded: addressOpen,
              child: MgPress(
                onTap: onToggle,
                child: MgWell(
                  padding: const EdgeInsets.all(12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(padding: EdgeInsets.only(top: 1), child: MgIcon(MgIcons.pin, size: 18, color: MgColors.link)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: fields,
                        builder: (context, _) {
                          final s = summary();
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tr.tr('deliveryDetails'), style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
                            if (s.isNotEmpty) Text(s, style: MgType.small.copyWith(color: MgColors.meta)),
                          ]);
                        },
                      ),
                    ),
                    AnimatedRotation(
                      turns: addressOpen ? 0.5 : 0,
                      duration: MgMotion.of(context, MgMotion.color),
                      child: const MgIcon(MgIcons.chevronDown, size: 18, color: MgColors.link),
                    ),
                  ]),
                ),
              ),
            ),
            MgAnimatedSize(
              duration: MgMotion.sheet,
              curve: MgMotion.emphasized,
              alignment: Alignment.topCenter,
              child: !addressOpen
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: MgSpace.s12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        TextField(controller: name, decoration: dec(tr.tr('fullNameLabel'))),
                        const SizedBox(height: MgSpace.s8),
                        Row(children: [
                          Expanded(flex: 2, child: TextField(controller: city, decoration: dec(tr.tr('city')))),
                          const SizedBox(width: MgSpace.s8),
                          Expanded(child: TextField(controller: zip, decoration: dec(tr.tr('zip')), keyboardType: TextInputType.number)),
                        ]),
                        const SizedBox(height: MgSpace.s8),
                        TextField(controller: street, decoration: dec(tr.tr('streetShort'))),
                      ]),
                    ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// "Slevový kód" of the v2 checkout: collapsed row → field + "Použít"
/// (spinner inside) — the screen's own apply; the result line ok / error
/// colour without emoji; applied codes as ok rows with a 44 px ✕ (the
/// screen's own remove).
class CheckoutPromoV2 extends StatelessWidget {
  final bool expanded;
  final VoidCallback onExpand;
  final TextEditingController ctrl;
  final bool loading;
  final VoidCallback onApply;
  final String? msg;
  final bool? ok;
  final List<AppliedDiscount> applied;
  final void Function(String code) onRemove;

  const CheckoutPromoV2({
    super.key,
    required this.expanded,
    required this.onExpand,
    required this.ctrl,
    required this.loading,
    required this.onApply,
    required this.msg,
    required this.ok,
    required this.applied,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: MgSpace.s12),
      child: PayCardV2(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!expanded)
            MgBtnText(key: const ValueKey('checkout-v2-promo-open'), label: tr.tr('discountCode'), icon: MgIcons.tag, onTap: onExpand)
          else ...[
            const SizedBox(height: 4),
            PayEyebrowV2(tr.tr('discountCode')),
            const SizedBox(height: MgSpace.s8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('checkout-v2-promo'),
                  controller: ctrl,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => onApply(),
                  decoration: mgInputDecoration(context, hint: tr.tr('v2UxPsEnterCode')),
                ),
              ),
              const SizedBox(width: MgSpace.s8),
              MgBtnGhostLight(label: tr.tr('apply'), expand: false, height: 52, busy: loading, onTap: loading ? null : onApply),
            ]),
            if (msg != null)
              Padding(
                padding: const EdgeInsets.only(top: MgSpace.s8),
                child: Text(msg!,
                    style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: ok == true ? MgColors.link : MgColors.err)),
              ),
          ],
          for (final d in applied)
            Padding(
              padding: const EdgeInsets.only(top: MgSpace.s8),
              child: MgTintOk(
                padding: const EdgeInsets.only(left: 12),
                child: Row(children: [
                  const MgIcon(MgIcons.tag, size: 16, color: MgColors.onTintOk),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MgWordFit(
                      child: Text(
                        d.type == DiscountType.percent
                            ? '${d.code} (−${d.value.toStringAsFixed(0)}%)'
                            : '${d.code} (−${Money.czk(d.value)})',
                        style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onTintOk),
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: '${tr.tr('removeBtn')} ${d.code}',
                    excludeSemantics: true,
                    child: MgPress(
                      scale: 0.92,
                      onTap: () => onRemove(d.code),
                      child: const SizedBox(width: 44, height: 44, child: Center(child: MgIcon(MgIcons.close, size: 18, color: MgColors.err))),
                    ),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Order summary of the v2 checkout: the same rows as the old section
/// (items × qty, shipping, discount) and the total.
class CheckoutSummaryV2 extends StatelessWidget {
  final List<CartItem> cart;
  final bool digitalOnly;
  final ShipMode shipMode;
  final double shipping;
  final double discount;
  final double total;
  const CheckoutSummaryV2({
    super.key,
    required this.cart,
    required this.digitalOnly,
    required this.shipMode,
    required this.shipping,
    required this.discount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return PayCardV2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final i in cart) PayRowV2(label: '${i.name}${i.qty > 1 ? ' ×${i.qty}' : ''}', value: Money.czk(i.total)),
        if (!digitalOnly)
          PayRowV2(
            label: shipMode == ShipMode.post ? tr.tr('shippingPost') : tr.tr('shippingPickup'),
            value: shipping > 0 ? '+${Money.czk(shipping)}' : tr.tr('free'),
          ),
        if (discount > 0) PayRowV2(label: tr.tr('discountLabel'), value: '−${Money.czk(discount)}', valueColor: MgColors.link),
        const Divider(height: 16, color: MgColors.line),
        Row(children: [
          Expanded(child: MgWordFit(child: Text(tr.tr('totalToPay'), style: MgType.title.copyWith(color: MgColors.ink)))),
          Text(Money.czk(total), style: MgType.tab(MgType.h3.copyWith(fontWeight: FontWeight.w900, color: MgColors.ink))),
        ]),
      ]),
    );
  }
}
