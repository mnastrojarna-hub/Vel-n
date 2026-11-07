import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_emoji_map.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../card_minimum.dart';
import '../payment_provider.dart';

/// v2 line icon for the emoji the payment code already passes (outcome
/// lines, SOS rows) — display only; unknown emoji → the info icon.
String payIconFor(String emoji) {
  final e = emoji.replaceAll('️', '').trim();
  switch (e) {
    case '💳':
      return MgIcons.card;
    case '🧾':
      return MgIcons.receipt;
    case '🏍':
      return MgIcons.moto;
    case '📅':
    case '🗓':
      return MgIcons.calendarCheck;
    case '📍':
      return MgIcons.pin;
    case '↩':
      return MgIcons.refresh;
    case '🚛':
    case '🚚':
      return MgIcons.truck;
    case '📧':
      return MgIcons.mail;
    case '🎁':
      return MgIcons.gift;
    case 'ℹ':
      return MgIcons.info;
  }
  return mgToastLookFor(e).$1;
}

/// The amount as the old screen printed it: a sub-minimum amount with
/// haléře exactly ("0,60 Kč"), anything else through the app formatter.
String payAmountText(double amount) =>
    Money.code == 'CZK' && amount < cardMinCzk && amount != amount.roundToDouble()
        ? kcExact(amount)
        : Money.czk(amount);

/// White v2 card (r16, 1 px line, card shadow) used by every payment block.
class PayCardV2 extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const PayCardV2({super.key, required this.child, this.padding = const EdgeInsets.all(MgSpace.card), this.radius = MgRadius.card});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: MgColors.line),
          boxShadow: MgShadows.card,
        ),
        child: child,
      );
}

/// Eyebrow of a light card ("ZPŮSOB PLATBY", "CO BUDE DÁL").
class PayEyebrowV2 extends StatelessWidget {
  final String text;
  const PayEyebrowV2(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(text.toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.meta)),
      );
}

/// "ZPŮSOB PLATBY" (Booking board): the saved default card the payment
/// already uses, or card / wallet when there is none. No "Změnit" — no
/// such action exists today (OD-PS-10).
class PayMethodCardV2 extends StatelessWidget {
  final SavedCard? card;
  const PayMethodCardV2({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final c = card;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final title = c == null ? tr.tr('paymentCard') : '${c.displayBrand} •••• ${c.last4}';
    final sub = c == null
        ? tr.trArgs('v2UxPsWalletToo', {'wallet': ios ? 'Apple Pay' : 'Google Pay'})
        : tr.tr('v2UxPsDefaultCard');
    return PayCardV2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PayEyebrowV2(tr.tr('v2UxPsMethod')),
        const SizedBox(height: MgSpace.s10),
        Row(children: [
          const MgIconTileLight(MgIcons.card),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MgWordFit(minScale: 0.85, child: Text(title, style: MgType.tab(MgType.title.copyWith(color: MgColors.ink)))),
              Text(sub, style: MgType.small.copyWith(color: MgColors.meta)),
            ]),
          ),
        ]),
      ]),
    );
  }
}

/// Trust lines at the decision point (lock / clock icons, 12.5/600 meta):
/// Stripe + PCI (+ "bez kauce" for a booking) and that the term is held.
class PayTrustV2 extends StatelessWidget {
  final bool booking;
  final bool showStripe;

  /// The unpaid booking is released when the time runs out (new /
  /// unfinished booking only — a surcharge just is not applied).
  final bool showHold;
  const PayTrustV2({super.key, required this.booking, this.showStripe = true, this.showHold = false});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget line(String icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: MgIcon(icon, size: 16, color: MgColors.meta)),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: MgType.small.copyWith(color: MgColors.meta))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (showStripe) line(MgIcons.lock, tr.tr(booking ? 'v2UxPsTrustBooking' : 'v2UxPsTrust')),
      if (showHold) line(MgIcons.clock, tr.tr('v2UxPsTrustHold')),
    ]);
  }
}

/// The card-minimum note BEFORE paying (D1/D2, same texts and rule as
/// `CardRoundingNote`) as a T3 info banner; nothing for normal amounts.
class PayRoundingNoteV2 extends StatelessWidget {
  final num due;
  final bool forceMin;
  final String roundKey;
  final String waiveKey;
  final bool showLine;
  const PayRoundingNoteV2({
    super.key,
    required this.due,
    this.forceMin = false,
    this.roundKey = 'pdRoundNote',
    this.waiveKey = 'pdWaiveNote',
    this.showLine = true,
  });

  @override
  Widget build(BuildContext context) {
    final cc = cardCharge(due, forceMin: forceMin);
    if (!cc.isRound && !cc.isWaive) return const SizedBox.shrink();
    final tr = t(context);
    String fill(String s) => s.replaceAll('{amount}', kcExact(cc.due)).replaceAll('{rounding}', kcExact(cc.rounding.abs()));
    final note = fill(tr.tr(cc.isRound ? roundKey : waiveKey));
    final line = tr.tr(cc.isRound ? 'pdMinCardLine' : 'pdWaiveLine');
    final value = cc.isRound ? '+${kcExact(cc.rounding)}' : kcExact(cc.rounding);
    return MgStateBanner(tone: MgTone.info, title: mgStripEmoji(note), text: showLine ? '$line $value' : null);
  }
}

/// "✓ Cena ověřená serverem: {amount}" (the price the server confirmed).
class PayVerifiedLineV2 extends StatelessWidget {
  final String text;
  const PayVerifiedLineV2(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 1), child: MgIcon(MgIcons.check, size: 16, color: MgColors.link, stroke: 2.6)),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link))),
      ]);
}

/// One receipt row: optional icon tile, label 14/600 ink, value 14/800.
class PayRowV2 extends StatelessWidget {
  final String label;
  final String value;
  final String? icon;
  final Color? valueColor;
  const PayRowV2({super.key, required this.label, required this.value, this.icon, this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          if (icon != null) ...[MgIconTileLight(icon!, size: 32), const SizedBox(width: 10)],
          Expanded(child: MgWordFit(child: Text(label, style: MgType.body.copyWith(color: MgColors.ink)))),
          const SizedBox(width: 10),
          Text(value, style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w800, color: valueColor ?? MgColors.ink))),
        ]),
      );
}
