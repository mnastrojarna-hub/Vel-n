import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../payment/v2/pay_parts_v2.dart' show PayCardV2, PayEyebrowV2, PayRowV2;
import '../shop_models.dart';
import 'qty_stepper_v2.dart';

/// v2 look of the cart (Profil board "Košík" + Stavy 13.1 empty): compact
/// dark app bar, the items in one white card ("V KOŠÍKU" + red
/// "Vyprázdnit" in its header — away from the corner, same action), icon
/// tiles, 44 px stepper and trash per row, the summary with the old rows
/// and note, and the dock "K POKLADNĚ · {total}". No swipe-to-delete (no
/// undo). Every number and action is the screen's.
class CartViewV2 extends StatelessWidget {
  final List<CartItem> items;
  final int count;
  final double subtotal;
  final bool digitalOnly;
  final String shippingLabel;
  final double shipping;
  final double discount;
  final double total;
  final void Function(String id) onPlus;
  final void Function(String id) onMinus;
  final void Function(String id) onRemove;
  final VoidCallback onClear;
  final VoidCallback onCheckout;
  final VoidCallback onShop;
  final VoidCallback onBack;

  const CartViewV2({
    super.key,
    required this.items,
    required this.count,
    required this.subtotal,
    required this.digitalOnly,
    required this.shippingLabel,
    required this.shipping,
    required this.discount,
    required this.total,
    required this.onPlus,
    required this.onMinus,
    required this.onRemove,
    required this.onClear,
    required this.onCheckout,
    required this.onShop,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final header = MgAppBar(title: tr.tr('cartTitle'), subtitle: tr.tr('shopTitle'), onBack: onBack);
    if (items.isEmpty) {
      return MgPage(
        header: header,
        overlapHero: false,
        overscrollColor: MgColors.night,
        sections: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MgSpace.gutter, MgSpace.s24, MgSpace.gutter, 0),
            child: MgStateBanner(
              tone: MgTone.info,
              icon: MgIcons.cart,
              plain: true,
              title: tr.tr('cartEmpty'),
              text: tr.tr('v2UxPsCartEmptyText'),
              actions: [MgBtnInk(label: tr.tr('backToShop'), icon: MgIcons.bag, expand: false, height: 44, onTap: onShop)],
            ),
          ),
        ],
      );
    }
    final list = PayCardV2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: PayEyebrowV2(tr.tr('v2UxPsInCartEyebrow'))),
          MgBtnText(key: const ValueKey('cart-v2-clear'), label: tr.tr('emptyBtn'), icon: MgIcons.trash, color: MgColors.err, onTap: onClear),
        ]),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 20, color: MgColors.line),
          _row(tr, items[i]),
        ],
      ]),
    );
    final summary = PayCardV2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PayRowV2(label: '${tr.tr('orderSummary')} ($count)', value: Money.czk(subtotal)),
        if (!digitalOnly) PayRowV2(label: shippingLabel, value: shipping > 0 ? '+${Money.czk(shipping)}' : tr.tr('free')),
        if (discount > 0) PayRowV2(label: tr.tr('discountLabel'), value: '−${Money.czk(discount)}', valueColor: MgColors.link),
        const Divider(height: 16, color: MgColors.line),
        Row(children: [
          Expanded(child: MgWordFit(child: Text(tr.tr('totalToPay'), style: MgType.title.copyWith(color: MgColors.ink)))),
          MgBump(
            trigger: total,
            child: Text(Money.czk(total), style: MgType.tab(MgType.h3.copyWith(fontWeight: FontWeight.w900, color: MgColors.ink))),
          ),
        ]),
        const SizedBox(height: MgSpace.s8),
        Text(tr.tr('shopPriceNote'), style: MgType.meta.copyWith(fontWeight: FontWeight.w600, color: MgColors.meta)),
      ]),
    );
    return MgPage(
      header: header,
      overlapHero: false,
      overscrollColor: MgColors.night,
      sections: [
        Padding(
          padding: const EdgeInsets.fromLTRB(MgSpace.gutter, MgSpace.s16, MgSpace.gutter, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            list,
            const SizedBox(height: MgSpace.s12),
            summary,
          ]),
        ),
      ],
      dock: MgDock(
        contextLine: Text(tr.trArgs('v2UxPsInCart', {'n': count})),
        child: MgCta(
          key: const ValueKey('cart-v2-checkout'),
          label: tr.tr('v2UxPsToCheckout'),
          price: Money.czk(total).replaceAll(' ', '\u00A0'),
          onTap: onCheckout,
          size: MgCtaSize.md56,
        ),
      ),
    );
  }

  Widget _row(AppTranslations tr, CartItem item) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MgIconTileLight(item.id.startsWith('voucher_') ? MgIcons.gift : MgIcons.tag),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MgWordFit(child: Text(item.name, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
              Text(Money.czk(item.price), style: MgType.tab(MgType.small.copyWith(color: MgColors.meta))),
            ]),
          ),
          MgIconButton(
            icon: MgIcons.trash,
            style: MgIconButtonStyle.light,
            iconColor: MgColors.err,
            semanticLabel: '${tr.tr('removeBtn')} ${item.name}',
            onTap: () => onRemove(item.id),
          ),
        ]),
        const SizedBox(height: MgSpace.s8),
        Row(children: [
          // Indent under the name, given up first on a narrow phone.
          const Flexible(child: SizedBox(width: 48)),
          QtyStepperV2(qty: item.qty, onMinus: () => onMinus(item.id), onPlus: () => onPlus(item.id)),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: MgBump(
                  trigger: item.total,
                  child: Text(Money.czk(item.total), style: MgType.tab(MgType.title.copyWith(color: MgColors.ink))),
                ),
              ),
            ),
          ),
        ]),
      ]);
}
