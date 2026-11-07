import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../shop_models.dart';
import '../shop_provider.dart';
import 'ship_card.dart';

/// Shipping method selector + collapsible delivery address fields.
/// Mirrors original s-checkout: address fields hidden behind a toggle.
class CheckoutShippingSection extends ConsumerStatefulWidget {
  final TextEditingController nameCtrl;
  final TextEditingController streetCtrl;
  final TextEditingController zipCtrl;
  final TextEditingController cityCtrl;

  const CheckoutShippingSection({
    super.key,
    required this.nameCtrl,
    required this.streetCtrl,
    required this.zipCtrl,
    required this.cityCtrl,
  });

  @override
  ConsumerState<CheckoutShippingSection> createState() =>
      CheckoutShippingSectionState();
}

class CheckoutShippingSectionState
    extends ConsumerState<CheckoutShippingSection> {
  bool _addressOpen = false;

  /// Pokladna nahlásila chybějící údaje → rozbalit adresu a ukázat ji.
  void reveal() {
    if (!mounted) return;
    setState(() => _addressOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.1);
    });
  }

  /// Sbalená hlavička: „jméno · ulice, obec“ (dřív jen jméno).
  String _summary() => [
        widget.nameCtrl.text.trim(),
        [widget.streetCtrl.text.trim(), widget.cityCtrl.text.trim()]
            .where((x) => x.isNotEmpty)
            .join(', '),
      ].where((x) => x.isNotEmpty).join(' · ');

  @override
  Widget build(BuildContext context) {
    final shipMode = ref.watch(shipModeProvider);

    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [
          BoxShadow(
              color: MotoGoColors.black.withValues(alpha: 0.1),
              blurRadius: 20)
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📦 ${t(context).tr('deliveryDetails').toUpperCase()}',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: MotoGoColors.g400,
                letterSpacing: 0.5)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: ShipCard(
              icon: '📮',
              label: t(context).tr('shippingByPost'),
              sublabel: t(context).tr('shippingPostInfo'),
              active: shipMode == ShipMode.post,
              onTap: () =>
                  ref.read(shipModeProvider.notifier).state = ShipMode.post,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ShipCard(
              icon: '🏪',
              label: t(context).tr('personalPickup'),
              sublabel: t(context).tr('personalPickupInfo'),
              active: shipMode == ShipMode.pickup,
              onTap: () =>
                  ref.read(shipModeProvider.notifier).state = ShipMode.pickup,
            ),
          ),
        ]),
        // Collapsible address toggle + fields (only for post)
        if (shipMode == ShipMode.post) ...[
          const SizedBox(height: 8),
          const Divider(height: 1, color: MotoGoColors.g100),
          // Toggle header — matches original toggleShipDetails()
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _addressOpen = !_addressOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    // Poslouchá pole (i doplnění z profilu po načtení).
                    child: ListenableBuilder(
                      listenable: Listenable.merge(
                          [widget.nameCtrl, widget.streetCtrl, widget.cityCtrl]),
                      builder: (context, _) {
                        final summary = _summary();
                        return Row(children: [
                          Text('📋 ${t(context).tr('deliveryDetails')}',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700)),
                          if (summary.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '· $summary',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: MotoGoColors.g400),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ]);
                      },
                    ),
                  ),
                  AnimatedRotation(
                    turns: _addressOpen ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Text('›',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: MotoGoColors.g400)),
                  ),
                ],
              ),
            ),
          ),
          // Address fields — collapsible with animation
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: widget.nameCtrl,
                    decoration: InputDecoration(
                        labelText: t(context).tr('fullNameLabel'))),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                        controller: widget.cityCtrl,
                        decoration: InputDecoration(
                            labelText: t(context).tr('city'))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: widget.zipCtrl,
                      decoration:
                          InputDecoration(labelText: t(context).tr('zip')),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(
                    controller: widget.streetCtrl,
                    decoration: InputDecoration(
                        labelText: t(context).tr('streetShort'))),
              ],
            ),
            crossFadeState: _addressOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ]),
    );
  }
}
