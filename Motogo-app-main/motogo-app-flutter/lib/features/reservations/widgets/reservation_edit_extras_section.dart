import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/currency.dart';
import '../../booking/booking_models.dart';
import 'reservation_edit_widgets.dart';

/// Extras + gear size section for reservation edit.
///
/// Mirrors the booking-flow behaviour: the paid add-ons (passenger gear,
/// driver/passenger boots) open a size modal when checked and stay expanded
/// while selected so the chosen sizes can be changed for free. The base
/// driver gear (helmet, jacket, pants, gloves) is shown as free chip pickers
/// with an "I have my own gear" toggle.
class EditExtrasSection extends StatelessWidget {
  final Set<String> selectedExtras;
  final String pickupMethod;
  final String returnMethod;
  final bool isKids;
  final bool ownGear;
  final String? helmetSize, jacketSize, pantsSize, bootsSize, glovesSize;
  final String? passengerHelmetSize, passengerJacketSize, passengerPantsSize, passengerBootsSize;
  final ValueChanged<Set<String>> onExtrasChanged;
  final ValueChanged<bool> onOwnGearChanged;
  final ValueChanged<String?> onHelmetSize, onJacketSize, onPantsSize, onBootsSize, onGlovesSize;
  final ValueChanged<String?> onPassengerHelmetSize, onPassengerJacketSize, onPassengerPantsSize, onPassengerBootsSize;

  /// Aktuální věrnostní rank — od [loyaltyFreeGearLevel] je veškerá placená
  /// výbava (vč. obuvi a výbavy spolujezdce) zdarma i při úpravě.
  final int loyaltyLevel;

  const EditExtrasSection({
    super.key,
    required this.selectedExtras,
    required this.pickupMethod,
    required this.returnMethod,
    this.isKids = false,
    this.ownGear = false,
    this.loyaltyLevel = 0,
    required this.helmetSize, required this.jacketSize, required this.pantsSize,
    required this.bootsSize, required this.glovesSize,
    required this.passengerHelmetSize, required this.passengerJacketSize, required this.passengerPantsSize,
    required this.passengerBootsSize,
    required this.onExtrasChanged,
    required this.onOwnGearChanged,
    required this.onHelmetSize, required this.onJacketSize, required this.onPantsSize,
    required this.onBootsSize, required this.onGlovesSize,
    required this.onPassengerHelmetSize, required this.onPassengerJacketSize, required this.onPassengerPantsSize,
    required this.onPassengerBootsSize,
  });

  /// Od 3. ranku je veškerá placená výbava zdarma.
  bool get _gearFree => loyaltyLevel >= loyaltyFreeGearLevel;

  void _addExtra(String id) {
    if (selectedExtras.contains(id)) return;
    onExtrasChanged(Set<String>.from(selectedExtras)..add(id));
  }

  void _removeExtra(String id) {
    if (!selectedExtras.contains(id)) return;
    onExtrasChanged(Set<String>.from(selectedExtras)..remove(id));
  }

  /// Bottom-sheet size picker for a single-size paid add-on (driver/passenger
  /// boots). Selecting a chip adds the add-on and sets the size; an already
  /// selected add-on can be removed (refund) from the same sheet.
  void _showBootSizeSheet(
    BuildContext context, {
    required String title,
    required bool isSelected,
    required ValueChanged<String> onPick,
    required VoidCallback onRemove,
  }) {
    final sizes = gearSizesFor('boots', kids: isKids);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).padding.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: MotoGoColors.g200, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Text('${t(ctx).tr('selectSizeTitle')} – $title',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8,
            children: sizes.map((size) => GestureDetector(
              onTap: () { onPick(size); Navigator.pop(ctx); },
              child: Container(
                width: 52, height: 44,
                decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: MotoGoColors.green, width: 1.5)),
                child: Center(child: Text(size,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)))),
            )).toList()),
          if (isSelected) ...[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () { onRemove(); Navigator.pop(ctx); },
              icon: const Icon(Icons.delete_outline, size: 18, color: MotoGoColors.red),
              label: Text(t(ctx).tr('removeAddon'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.red))),
          ],
        ]),
      ),
    );
  }

  /// Bottom-sheet size picker for the passenger gear add-on (helmet, jacket,
  /// pants). Opened when the add-on is checked; the same sizes also stay
  /// expanded inline below the checkbox for free changes.
  void _showPassengerGearSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        String? ph = passengerHelmetSize, pj = passengerJacketSize, pp = passengerPantsSize;
        return StatefulBuilder(builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16,
            MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: MotoGoColors.g200, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Text('${t(ctx).tr('passengerGearLabel')} – ${t(ctx).tr('sizesLabel')}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            const SizedBox(height: 12),
            EditGearSizePicker(label: t(ctx).tr('helmet'), icon: Icons.sports_motorsports,
              sizes: gearSizesFor('helmet', kids: false), selectedSize: ph,
              onSizeSelected: (s) { setModal(() => ph = s); onPassengerHelmetSize(s); }),
            const SizedBox(height: 6),
            EditGearSizePicker(label: t(ctx).tr('jacket'), icon: Icons.checkroom,
              sizes: gearSizesFor('jacket', kids: false), selectedSize: pj,
              onSizeSelected: (s) { setModal(() => pj = s); onPassengerJacketSize(s); }),
            const SizedBox(height: 6),
            EditGearSizePicker(label: t(ctx).tr('pants'), icon: Icons.straighten,
              sizes: gearSizesFor('pants', kids: false), selectedSize: pp,
              onSizeSelected: (s) { setModal(() => pp = s); onPassengerPantsSize(s); }),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: MotoGoColors.green, foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))),
              child: Text(t(ctx).tr('doneLabel'), style: const TextStyle(fontWeight: FontWeight.w800)))),
            const SizedBox(height: 4),
            Center(child: TextButton.icon(
              onPressed: () {
                _removeExtra('spolujezdec');
                onPassengerHelmetSize(null);
                onPassengerJacketSize(null);
                onPassengerPantsSize(null);
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.delete_outline, size: 18, color: MotoGoColors.red),
              label: Text(t(ctx).tr('removeAddon'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.red)))),
          ]),
        ));
      },
    );
  }

  /// Paid add-on card (checkbox style) — whole card is tappable.
  Widget _paidCard({
    required bool checked,
    required String label,
    required String sub,
    required double price,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: checked ? MotoGoColors.greenPale : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: checked ? MotoGoColors.green : MotoGoColors.g200, width: checked ? 2 : 1)),
        child: Row(children: [
          Container(width: 20, height: 20,
            decoration: BoxDecoration(
              color: checked ? MotoGoColors.green : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: checked ? MotoGoColors.green : MotoGoColors.g200, width: 2)),
            child: checked ? const Icon(Icons.check, size: 14, color: Colors.black) : null),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
            Text(sub, style: TextStyle(fontSize: 10,
              fontWeight: checked ? FontWeight.w700 : FontWeight.w400,
              color: checked ? MotoGoColors.greenDark : MotoGoColors.g400)),
          ])),
          Text(_gearFree ? 'ZDARMA' : '+${Money.czk(price)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.greenDark)),
        ])),
    );
  }

  String _bootsSub(BuildContext context, bool checked, String? size) {
    if (!checked) return t(context).tr('specifySize');
    if (size == null) return t(context).tr('clickToSelectSize');
    return '${t(context).tr('sizeSingular')}: $size · ${t(context).tr('tapToChangeSize')}';
  }

  @override
  Widget build(BuildContext context) {
    final passengerSelected = !isKids && selectedExtras.contains('spolujezdec');
    return EditCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.backpack, size: 16, color: MotoGoColors.greenDark),
        const SizedBox(width: 6),
        Text(t(context).tr('addonsLabel'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
      ]),
      const SizedBox(height: 8),
      // Při přistavení potřebujeme velikosti — info banner.
      if (pickupMethod == 'delivery' || returnMethod == 'delivery')
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFFD54F).withValues(alpha: 0.5))),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 14, color: Color(0xFF92400E)),
            const SizedBox(width: 6),
            Expanded(child: Text(t(context).tr('deliverySizeInfo'),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF92400E)))),
          ]),
        )),

      // Od 3. ranku: veškerá výbava i obuv zdarma (i pro spolujezdce).
      if (_gearFree)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.5))),
          child: Row(children: [
            const Text('🏅', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text(t(context).tr('loyaltyGearBenefit'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker))),
          ]),
        )),

      // === Placené doplňky — modal na zaškrtnutí, rozbalené při výběru ===
      // Dětská motorka nikdy nemá spolujezdce → skryj výbavu i boty spolujezdce.
      if (!isKids)
        _paidCard(
          checked: passengerSelected,
          label: t(context).tr('passengerGearLabel'),
          sub: t(context).tr('passengerGearSub'),
          price: 690,
          onTap: () {
            if (passengerSelected) {
              _removeExtra('spolujezdec');
              onPassengerHelmetSize(null);
              onPassengerJacketSize(null);
              onPassengerPantsSize(null);
            } else {
              _addExtra('spolujezdec');
              _showPassengerGearSheet(context);
            }
          }),
      _paidCard(
        checked: selectedExtras.contains('boty_ridic'),
        label: t(context).tr('driverBootsLabel'),
        sub: _bootsSub(context, selectedExtras.contains('boty_ridic'), bootsSize),
        price: 290,
        onTap: () => _showBootSizeSheet(context,
          title: t(context).tr('driverBootsLabel'),
          isSelected: selectedExtras.contains('boty_ridic'),
          onPick: (s) { onBootsSize(s); _addExtra('boty_ridic'); },
          onRemove: () { onBootsSize(null); _removeExtra('boty_ridic'); })),
      if (!isKids)
        _paidCard(
          checked: selectedExtras.contains('boty_spolujezdec'),
          label: t(context).tr('bootsPassengerLabel'),
          sub: _bootsSub(context, selectedExtras.contains('boty_spolujezdec'), passengerBootsSize),
          price: 290,
          onTap: () => _showBootSizeSheet(context,
            title: t(context).tr('bootsPassengerLabel'),
            isSelected: selectedExtras.contains('boty_spolujezdec'),
            onPick: (s) { onPassengerBootsSize(s); _addExtra('boty_spolujezdec'); },
            onRemove: () { onPassengerBootsSize(null); _removeExtra('boty_spolujezdec'); })),

      // Rozbalené velikosti spolujezdce (zdarma měnit) když je výbava vybraná.
      if (passengerSelected) ...[
        const SizedBox(height: 6),
        Text('${t(context).tr('passengerGearLabel')}'.toUpperCase(),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
        const SizedBox(height: 6),
        EditGearSizePicker(label: t(context).tr('helmet'), icon: Icons.sports_motorsports,
          sizes: gearSizesFor('helmet', kids: false),
          selectedSize: passengerHelmetSize, onSizeSelected: onPassengerHelmetSize),
        const SizedBox(height: 6),
        EditGearSizePicker(label: t(context).tr('jacket'), icon: Icons.checkroom,
          sizes: gearSizesFor('jacket', kids: false),
          selectedSize: passengerJacketSize, onSizeSelected: onPassengerJacketSize),
        const SizedBox(height: 6),
        EditGearSizePicker(label: t(context).tr('pants'), icon: Icons.straighten,
          sizes: gearSizesFor('pants', kids: false),
          selectedSize: passengerPantsSize, onSizeSelected: onPassengerPantsSize),
      ],

      const Divider(height: 18),

      // === Výbava řidiče — zdarma, vždy rozbalená + „mám vlastní výbavu" ===
      Row(children: [
        Text(t(context).tr('rider'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
        const SizedBox(width: 6),
        const Text('· zdarma', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.g400)),
        const Spacer(),
        GestureDetector(
          onTap: () => onOwnGearChanged(!ownGear),
          child: Row(children: [
            Icon(ownGear ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18, color: ownGear ? MotoGoColors.green : MotoGoColors.g400),
            const SizedBox(width: 4),
            Text(t(context).tr('ownGear'),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: ownGear ? MotoGoColors.greenDarker : MotoGoColors.g400)),
          ])),
      ]),
      if (!ownGear) ...[
        const SizedBox(height: 6),
        EditGearSizePicker(label: t(context).tr('helmet'), icon: Icons.sports_motorsports,
          sizes: gearSizesFor('helmet', kids: isKids),
          selectedSize: helmetSize, onSizeSelected: onHelmetSize),
        const SizedBox(height: 6),
        EditGearSizePicker(label: t(context).tr('jacket'), icon: Icons.checkroom,
          sizes: gearSizesFor('jacket', kids: isKids),
          selectedSize: jacketSize, onSizeSelected: onJacketSize),
        const SizedBox(height: 6),
        EditGearSizePicker(label: t(context).tr('pants'), icon: Icons.straighten,
          sizes: gearSizesFor('pants', kids: isKids),
          selectedSize: pantsSize, onSizeSelected: onPantsSize),
        const SizedBox(height: 6),
        EditGearSizePicker(label: t(context).tr('gloves'), icon: Icons.back_hand_outlined,
          sizes: gearSizesFor('gloves', kids: isKids),
          selectedSize: glovesSize, onSizeSelected: onGlovesSize),
      ],
    ]));
  }
}
