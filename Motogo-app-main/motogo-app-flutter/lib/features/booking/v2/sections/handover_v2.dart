import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_space.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../booking_v2_parts.dart';

/// Address row of a delivery choice (data of the old `bookingAddrTile`).
class BkAddress {
  final String? city;
  final String? address;
  final double? distKm;
  final double? delivFee;
  final VoidCallback onTap;
  const BkAddress({required this.city, required this.address, required this.onTap, this.distKm, this.delivFee});
}

/// v2 look of the pickup / return sections (V branch of
/// `BookingFormPickupSection` / `BookingFormReturnSection`): the same two
/// choices with the SAME closures — branch (address of the bike's branch,
/// free) and delivery (price info, "od 1 000 Kč") or the locked tile
/// ([locked], the existing `BookingLockedOptionTile`) — and the address
/// row that opens the existing address sheet.
class BookingHandoverV2 extends StatelessWidget {
  final String title;
  final String icon;
  final String branchSub;
  final bool storeSelected;
  final bool deliverySelected;
  final String deliveryTitle;
  final VoidCallback onStore;
  final VoidCallback onDelivery;

  /// Non-null = delivery is not offered here (self-service branch).
  final Widget? locked;

  /// Shown under the choices while delivery is selected.
  final BkAddress? address;

  const BookingHandoverV2({
    super.key,
    required this.title,
    required this.icon,
    required this.branchSub,
    required this.storeSelected,
    required this.deliverySelected,
    required this.deliveryTitle,
    required this.onStore,
    required this.onDelivery,
    this.locked,
    this.address,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return BkCard(
      icon: icon,
      title: title,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BkOptionRow(
          title: tr.tr('atBranch'),
          sub: branchSub,
          trailing: tr.free,
          selected: storeSelected,
          onTap: onStore,
        ),
        const SizedBox(height: 8),
        locked ??
            BkOptionRow(
              title: deliveryTitle,
              sub: tr.tr('deliveryPriceInfo'),
              trailing: tr.tr('deliveryFrom'),
              selected: deliverySelected,
              onTap: onDelivery,
            ),
        if (address != null) ...[
          const SizedBox(height: 10),
          MgEnter(child: _AddressRow(a: address!)),
        ],
      ]),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final BkAddress a;
  const _AddressRow({required this.a});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final hasAddr = a.city?.isNotEmpty == true;
    final text = hasAddr ? '${a.address ?? ""}, ${a.city}' : tr.tr('v2BkEnterAddress');
    final fee = a.delivFee;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        button: true,
        label: hasAddr ? tr.trArgs('v2BkAddressA11y', {'address': text}) : text,
        excludeSemantics: true,
        onTap: a.onTap,
        child: MgPress(
          onTap: a.onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(MgRadius.button),
              border: Border.all(color: hasAddr ? MgColors.lineInput : MgColors.link, width: 1.5),
            ),
            child: Row(children: [
              MgIcon(MgIcons.pin, size: 20, color: MgColors.link),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: hasAddr
                        ? MgType.body.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink)
                        : MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
              ),
              const SizedBox(width: 8),
              MgIcon(hasAddr ? MgIcons.edit : MgIcons.chevronRight, size: 18, color: MgColors.link),
            ]),
          ),
        ),
      ),
      if (fee != null && fee > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: MgColors.well,
              borderRadius: BorderRadius.circular(MgRadius.action),
              border: Border.all(color: MgColors.line),
            ),
            child: Row(children: [
              MgIcon(MgIcons.route, size: 16, color: MgColors.link),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  a.distKm != null ? '~${a.distKm!.toStringAsFixed(0)} km · ${bkMoney(fee)}' : bkMoney(fee),
                  style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// v2 look of `BookingLockedOptionTile` (V branch): looks like an option
/// row but cannot be chosen — lock disc, short reason, tap toggles the
/// explanation (the tile's own `_open` state).
class BookingLockedOptionV2View extends StatelessWidget {
  final String label;
  final String shortReason;
  final String info;
  final bool open;
  final VoidCallback onToggle;

  const BookingLockedOptionV2View({
    super.key,
    required this.label,
    required this.shortReason,
    required this.info,
    required this.open,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Semantics(
      button: true,
      expanded: open,
      label: '${tr.trArgs('v2BkLockedA11y', {'label': label})}. $shortReason',
      onTap: onToggle,
      child: MgPress(
        onTap: onToggle,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: MgColors.well,
            borderRadius: BorderRadius.circular(MgRadius.button),
            border: Border.all(color: MgColors.line),
          ),
          child: ExcludeSemantics(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MgColors.surface,
                    border: Border.all(color: MgColors.line, width: 1.5),
                  ),
                  child: Center(child: MgIcon(MgIcons.lock, size: 13, color: MgColors.meta)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.meta, height: 1.3)),
                    const SizedBox(height: 2),
                    Text(shortReason, style: MgType.small.copyWith(color: MgColors.meta)),
                  ]),
                ),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: MgMotion.of(context, MgMotion.color),
                  child: MgIcon(MgIcons.chevronDown, size: 18, color: MgColors.meta),
                ),
              ]),
              if (open)
                Padding(
                  padding: const EdgeInsets.only(top: 10, left: 36),
                  child: MgEnter(child: Text(info, style: MgType.small.copyWith(color: MgColors.body2))),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
