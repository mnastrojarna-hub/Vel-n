import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../booking/booking_models.dart';
import 'reservation_edit_widgets.dart';

/// Extras + gear size section for reservation edit.
class EditExtrasSection extends StatelessWidget {
  final Set<String> selectedExtras;
  final String pickupMethod;
  final String returnMethod;
  final String? helmetSize, jacketSize, pantsSize, bootsSize, glovesSize;
  final String? passengerHelmetSize, passengerJacketSize, passengerPantsSize;
  final ValueChanged<Set<String>> onExtrasChanged;
  final ValueChanged<String?> onHelmetSize, onJacketSize, onPantsSize, onBootsSize, onGlovesSize;
  final ValueChanged<String?> onPassengerHelmetSize, onPassengerJacketSize, onPassengerPantsSize;

  const EditExtrasSection({
    super.key,
    required this.selectedExtras,
    required this.pickupMethod,
    required this.returnMethod,
    required this.helmetSize, required this.jacketSize, required this.pantsSize,
    required this.bootsSize, required this.glovesSize,
    required this.passengerHelmetSize, required this.passengerJacketSize, required this.passengerPantsSize,
    required this.onExtrasChanged,
    required this.onHelmetSize, required this.onJacketSize, required this.onPantsSize,
    required this.onBootsSize, required this.onGlovesSize,
    required this.onPassengerHelmetSize, required this.onPassengerJacketSize, required this.onPassengerPantsSize,
  });

  void _toggle(String id, bool v) {
    final next = Set<String>.from(selectedExtras);
    if (v) { next.add(id); } else { next.remove(id); }
    onExtrasChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return EditCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.backpack, size: 16, color: MotoGoColors.greenDark),
        SizedBox(width: 6),
        Text('DOPLŇKY', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
      ]),
      const SizedBox(height: 8),
      EditExtraCheckbox(id: 'spolujezdec', label: 'Výbava spolujezdce', sub: 'Helma, rukavice, vesta', price: 400,
        checked: selectedExtras.contains('spolujezdec'),
        onChanged: (v) => _toggle('spolujezdec', v)),
      EditExtraCheckbox(id: 'boty_ridic', label: 'Boty řidiče', sub: 'Uveďte velikost', price: 300,
        checked: selectedExtras.contains('boty_ridic'),
        onChanged: (v) => _toggle('boty_ridic', v)),
      EditExtraCheckbox(id: 'boty_spolujezdec', label: 'Boty spolujezdce', sub: 'Uveďte velikost', price: 300,
        checked: selectedExtras.contains('boty_spolujezdec'),
        onChanged: (v) => _toggle('boty_spolujezdec', v)),
      if (pickupMethod == 'delivery' || returnMethod == 'delivery') ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFFD54F).withValues(alpha: 0.5))),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 14, color: Color(0xFF92400E)),
            SizedBox(width: 6),
            Expanded(child: Text('Při přistavení potřebujeme znát velikosti výbavy',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF92400E)))),
          ]),
        ),
        const SizedBox(height: 8),
        Text(t(context).tr('rider'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
        const SizedBox(height: 6),
        EditGearSizePicker(label: 'Helma', icon: Icons.sports_motorsports,
          selectedSize: helmetSize, onSizeSelected: onHelmetSize),
        const SizedBox(height: 6),
        EditGearSizePicker(label: 'Bunda', icon: Icons.checkroom,
          selectedSize: jacketSize, onSizeSelected: onJacketSize),
        const SizedBox(height: 6),
        EditGearSizePicker(label: 'Kalhoty', icon: Icons.straighten,
          selectedSize: pantsSize, onSizeSelected: onPantsSize),
        const SizedBox(height: 6),
        EditGearSizePicker(label: 'Boty', icon: Icons.do_not_step,
          sizes: bootSizes,
          selectedSize: bootsSize, onSizeSelected: onBootsSize),
        const SizedBox(height: 6),
        EditGearSizePicker(label: 'Rukavice', icon: Icons.back_hand_outlined,
          selectedSize: glovesSize, onSizeSelected: onGlovesSize),
        if (selectedExtras.contains('spolujezdec')) ...[
          const SizedBox(height: 10),
          const Text('SPOLUJEZDEC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
          const SizedBox(height: 6),
          EditGearSizePicker(label: 'Helma', icon: Icons.sports_motorsports,
            selectedSize: passengerHelmetSize, onSizeSelected: onPassengerHelmetSize),
          const SizedBox(height: 6),
          EditGearSizePicker(label: 'Bunda', icon: Icons.checkroom,
            selectedSize: passengerJacketSize, onSizeSelected: onPassengerJacketSize),
          const SizedBox(height: 6),
          EditGearSizePicker(label: 'Kalhoty', icon: Icons.straighten,
            selectedSize: passengerPantsSize, onSizeSelected: onPassengerPantsSize),
        ],
      ],
    ]));
  }
}
