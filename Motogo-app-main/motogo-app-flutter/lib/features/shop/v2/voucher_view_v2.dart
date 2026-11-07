import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_format.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_choice_card.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_segmented.dart';
import '../../payment/v2/pay_parts_v2.dart' show PayCardV2;
import '../shop_models.dart' show printedVoucherShipping;

/// "Jiná" segment of the amount control.
const int kVoucherCustomV2 = -1;

/// v2 look of the gift voucher page (Profil board "Dárkový poukaz"):
/// compact dark app bar, the voucher picture, "Hodnota poukazu" as 4 equal
/// segments (500 · 1 000 · 2 000 · Jiná, ink thumb) + the custom amount
/// field, "Typ poukazu" as two option cards, "Jak to funguje" ✓ list and
/// the dock "KOUPIT POUKAZ · {total}" (locked below 100 Kč, the reason in
/// the dock line). Field controller, normalisation and the buy action are
/// the screen's own.
class VoucherViewV2 extends StatelessWidget {
  final int amount;
  final bool customMode;
  final bool printed;
  final double total;
  final TextEditingController customCtrl;
  final ValueChanged<int> onPreset;
  final VoidCallback onCustom;
  final ValueChanged<String> onCustomChanged;
  final VoidCallback onNormalize;
  final ValueChanged<bool> onPrinted;
  final VoidCallback? onBuy;
  final VoidCallback onBack;

  const VoucherViewV2({
    super.key,
    required this.amount,
    required this.customMode,
    required this.printed,
    required this.total,
    required this.customCtrl,
    required this.onPreset,
    required this.onCustom,
    required this.onCustomChanged,
    required this.onNormalize,
    required this.onPrinted,
    required this.onBuy,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final cur = tr.lang == 'cs' ? 'Kč' : 'CZK';
    String preset(int a) => '${mgNum(a, tr.lang)}\u00A0$cur';
    final value = customMode ? kVoucherCustomV2 : amount;
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(bottom: MgSpace.s8),
          child: Semantics(header: true, child: Text(s, style: MgType.title.copyWith(color: MgColors.ink))),
        );
    final card = PayCardV2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        label(tr.tr('voucherValue')),
        MgSegmented<int>(
          key: const ValueKey('voucher-v2-amount'),
          inkThumb: true,
          segments: [
            for (final a in const [500, 1000, 2000]) MgSegment(value: a, label: preset(a)),
            MgSegment(value: kVoucherCustomV2, label: tr.tr('other')),
          ],
          value: value,
          onChanged: (v) => v == kVoucherCustomV2 ? onCustom() : onPreset(v),
        ),
        if (customMode) ...[
          const SizedBox(height: MgSpace.s12),
          TextField(
            key: const ValueKey('voucher-v2-custom'),
            controller: customCtrl,
            keyboardType: TextInputType.number,
            decoration: mgInputDecoration(context, label: tr.tr('amountMin')).copyWith(suffixText: cur),
            onChanged: onCustomChanged,
            onEditingComplete: onNormalize,
            onTapOutside: (_) => onNormalize(),
          ),
        ],
        const SizedBox(height: MgSpace.s20),
        label(tr.tr('voucherTypeLabel')),
        // One option per row: two half-width cards split the words at 320–412.
        MgChoiceCard(
          title: tr.tr('electronicVoucher'),
          sub: 'Email · ${tr.free.toLowerCase()}',
          icon: MgIcons.mail,
          selected: !printed,
          onTap: () => onPrinted(false),
        ),
        const SizedBox(height: MgSpace.s8),
        MgChoiceCard(
          title: tr.tr('printedVoucher'),
          sub: '+ ${Money.czk(printedVoucherShipping)}',
          icon: MgIcons.gift,
          selected: printed,
          onTap: () => onPrinted(true),
        ),
      ]),
    );
    final how = PayCardV2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        label(tr.tr('howItWorks')),
        for (final k in const ['v2UxPsVoucherInfo1', 'voucherInfo2', 'voucherInfo3', 'voucherInfo5'])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 2), child: MgIcon(MgIcons.check, size: 16, color: MgColors.link, stroke: 2.6)),
              const SizedBox(width: 8),
              Expanded(child: Text(tr.tr(k), style: MgType.small.copyWith(color: MgColors.ink))),
            ]),
          ),
      ]),
    );
    final blocked = onBuy == null;
    return MgPage(
      header: MgAppBar(title: tr.tr('giftVoucher'), onBack: onBack),
      overlapHero: false,
      overscrollColor: MgColors.night,
      sections: [
        Padding(
          padding: const EdgeInsets.fromLTRB(MgSpace.gutter, MgSpace.s16, MgSpace.gutter, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(MgRadius.card),
              child: Image.asset('assets/darkovy-poukaz.webp', fit: BoxFit.cover, excludeFromSemantics: true),
            ),
            const SizedBox(height: MgSpace.s12),
            card,
            const SizedBox(height: MgSpace.s12),
            how,
            SizedBox(height: MediaQuery.viewInsetsOf(context).bottom),
          ]),
        ),
      ],
      dock: MgDock(
        contextLine: blocked
            ? Row(children: [
                const MgIcon(MgIcons.warn, size: 16, color: MgColors.warnDark),
                const SizedBox(width: 6),
                Expanded(child: Text(tr.tr('amountMin'), style: const TextStyle(color: MgColors.warnDark))),
              ])
            : null,
        child: MgCta(
          key: const ValueKey('voucher-v2-buy'),
          label: tr.tr('buyVoucherBtn'),
          price: blocked ? null : Money.czk(total).replaceAll(' ', '\u00A0'),
          leadingIcon: MgIcons.gift,
          enabled: !blocked,
          onTap: onBuy,
          size: MgCtaSize.md56,
        ),
      ),
    );
  }
}
