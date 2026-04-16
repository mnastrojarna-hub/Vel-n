import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../booking_models.dart';

/// Accessories selector — only 3 fixed items matching Capacitor.
/// Size selection via bottom sheet dialog.
/// When [isDelivery] is true, shows gear size pickers (helmet, jacket, pants).
class ExtrasSelector extends StatefulWidget {
  final List<ExtraCatalogItem> catalog;
  final List<SelectedExtra> selected;
  final ValueChanged<List<SelectedExtra>> onChanged;
  final bool isDelivery;
  final String? helmetSize;
  final String? jacketSize;
  final String? pantsSize;
  final String? bootsSize;
  final String? glovesSize;
  final ValueChanged<String?>? onHelmetSizeChanged;
  final ValueChanged<String?>? onJacketSizeChanged;
  final ValueChanged<String?>? onPantsSizeChanged;
  final ValueChanged<String?>? onBootsSizeChanged;
  final ValueChanged<String?>? onGlovesSizeChanged;
  final String? passengerHelmetSize;
  final String? passengerJacketSize;
  final String? passengerPantsSize;
  final ValueChanged<String?>? onPassengerHelmetSizeChanged;
  final ValueChanged<String?>? onPassengerJacketSizeChanged;
  final ValueChanged<String?>? onPassengerPantsSizeChanged;

  const ExtrasSelector({
    super.key,
    required this.catalog,
    required this.selected,
    required this.onChanged,
    this.isDelivery = false,
    this.helmetSize,
    this.jacketSize,
    this.pantsSize,
    this.bootsSize,
    this.glovesSize,
    this.onHelmetSizeChanged,
    this.onJacketSizeChanged,
    this.onPantsSizeChanged,
    this.onBootsSizeChanged,
    this.onGlovesSizeChanged,
    this.passengerHelmetSize,
    this.passengerJacketSize,
    this.passengerPantsSize,
    this.onPassengerHelmetSizeChanged,
    this.onPassengerJacketSizeChanged,
    this.onPassengerPantsSizeChanged,
  });

  @override
  State<ExtrasSelector> createState() => _ExtrasSelectorState();
}

class _ExtrasSelectorState extends State<ExtrasSelector> {
  late List<SelectedExtra> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selected);
  }

  @override
  void didUpdateWidget(covariant ExtrasSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_listEquals(oldWidget.selected, widget.selected)) {
      _selected = List.from(widget.selected);
    }
  }

  bool _listEquals(List<SelectedExtra> a, List<SelectedExtra> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].size != b[i].size) return false;
    }
    return true;
  }

  bool _isSelected(String id) => _selected.any((e) => e.id == id);

  void _toggle(ExtraCatalogItem item) {
    if (_isSelected(item.id)) {
      setState(() => _selected.removeWhere((e) => e.id == item.id));
      widget.onChanged(List.of(_selected));
    } else if (item.needsSize && item.sizes.isNotEmpty) {
      _showSizeDialog(item);
    } else {
      setState(() => _selected.add(SelectedExtra(id: item.id, name: item.name, price: item.price)));
      widget.onChanged(List.of(_selected));
    }
  }

  void _showSizeDialog(ExtraCatalogItem item) {
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
          Text('Vyberte velikost – ${item.name}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 4),
          Text(item.description ?? '', style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8,
            children: item.sizes.map((size) => GestureDetector(
              onTap: () {
                setState(() {
                  _selected.removeWhere((e) => e.id == item.id);
                  _selected.add(SelectedExtra(id: item.id, name: item.name, price: item.price, size: size));
                });
                widget.onChanged(List.of(_selected));
                Navigator.pop(ctx);
              },
              child: Container(
                width: 52, height: 44,
                decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: MotoGoColors.green, width: 1.5)),
                child: Center(child: Text(size,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)))),
            )).toList()),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only use the 3 fixed items
    final items = defaultExtras;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Free base gear
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.3))),
        child: const Row(children: [
          Icon(Icons.shield, size: 20, color: MotoGoColors.greenDarker),
          SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Základní výbava zdarma', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
            Text('Helma, rukavice, bunda, kalhoty', style: TextStyle(fontSize: 11, color: MotoGoColors.g600)),
          ])),
          Icon(Icons.check_circle, size: 18, color: MotoGoColors.green),
        ])),
      // Gear size pickers — shown only when delivery selected
      if (widget.isDelivery) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFFD54F).withValues(alpha: 0.5))),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 16, color: Color(0xFF92400E)),
            SizedBox(width: 8),
            Expanded(child: Text('Při přistavení potřebujeme znát velikosti výbavy',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF92400E)))),
          ]),
        ),
        const SizedBox(height: 8),
        Text(t(context).tr('rider'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
        const SizedBox(height: 6),
        _GearSizePicker(label: 'Helma', icon: Icons.sports_motorsports,
          selectedSize: widget.helmetSize,
          onSizeSelected: (s) => widget.onHelmetSizeChanged?.call(s)),
        const SizedBox(height: 6),
        _GearSizePicker(label: 'Bunda', icon: Icons.checkroom,
          selectedSize: widget.jacketSize,
          onSizeSelected: (s) => widget.onJacketSizeChanged?.call(s)),
        const SizedBox(height: 6),
        _GearSizePicker(label: 'Kalhoty', icon: Icons.straighten,
          selectedSize: widget.pantsSize,
          onSizeSelected: (s) => widget.onPantsSizeChanged?.call(s)),
        const SizedBox(height: 6),
        _GearSizePicker(label: 'Boty', icon: Icons.do_not_step,
          sizes: bootSizes,
          selectedSize: widget.bootsSize,
          onSizeSelected: (s) => widget.onBootsSizeChanged?.call(s)),
        const SizedBox(height: 6),
        _GearSizePicker(label: 'Rukavice', icon: Icons.back_hand_outlined,
          selectedSize: widget.glovesSize,
          onSizeSelected: (s) => widget.onGlovesSizeChanged?.call(s)),
        // Passenger gear sizes — shown when delivery + passenger equipment selected
        if (_isSelected('extra-spolujezdec')) ...[
          const SizedBox(height: 10),
          const Text('SPOLUJEZDEC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
          const SizedBox(height: 6),
          _GearSizePicker(label: 'Helma', icon: Icons.sports_motorsports,
            selectedSize: widget.passengerHelmetSize,
            onSizeSelected: (s) => widget.onPassengerHelmetSizeChanged?.call(s)),
          const SizedBox(height: 6),
          _GearSizePicker(label: 'Bunda', icon: Icons.checkroom,
            selectedSize: widget.passengerJacketSize,
            onSizeSelected: (s) => widget.onPassengerJacketSizeChanged?.call(s)),
          const SizedBox(height: 6),
          _GearSizePicker(label: 'Kalhoty', icon: Icons.straighten,
            selectedSize: widget.passengerPantsSize,
            onSizeSelected: (s) => widget.onPassengerPantsSizeChanged?.call(s)),
        ],
      ],
      const SizedBox(height: 10),

      // 3 paid extras
      ...items.map((item) {
        final selected = _isSelected(item.id);
        final selectedExtra = _selected.where((e) => e.id == item.id).firstOrNull;
        return GestureDetector(
          onTap: () => _toggle(item),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? MotoGoColors.greenPale : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? MotoGoColors.green : MotoGoColors.g200, width: selected ? 2 : 1)),
            child: Row(children: [
              Container(width: 20, height: 20,
                decoration: BoxDecoration(
                  color: selected ? MotoGoColors.green : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: selected ? MotoGoColors.green : MotoGoColors.g200, width: 2)),
                child: selected ? const Icon(Icons.check, size: 14, color: Colors.black) : null),
              const SizedBox(width: 10),
              Text(item.icon ?? '', style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                Text(
                  selected && selectedExtra?.size != null
                      ? 'Velikost: ${selectedExtra!.size}'
                      : item.description ?? '',
                  style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
              ])),
              Text('+${item.price.toStringAsFixed(0)} Kč',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.greenDark)),
            ]),
          ),
        );
      }),
    ]);
  }
}

/// Size picker row for a single gear item (helmet, jacket, pants).
class _GearSizePicker extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? selectedSize;
  final ValueChanged<String?> onSizeSelected;
  final List<String> sizes;

  const _GearSizePicker({
    required this.label,
    required this.icon,
    required this.selectedSize,
    required this.onSizeSelected,
    this.sizes = gearSizes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selectedSize != null ? MotoGoColors.greenPale : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selectedSize != null ? MotoGoColors.green : MotoGoColors.g200,
          width: selectedSize != null ? 2 : 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: MotoGoColors.greenDarker),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
          const Spacer(),
          if (selectedSize != null)
            Text('Zvoleno: $selectedSize',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MotoGoColors.greenDark)),
          const Text('  ZDARMA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.g400)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6,
          children: sizes.map((size) {
            final active = selectedSize == size;
            return GestureDetector(
              onTap: () => onSizeSelected(active ? null : size),
              child: Container(
                width: 46, height: 36,
                decoration: BoxDecoration(
                  color: active ? MotoGoColors.greenDarker : MotoGoColors.greenPale,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: active ? MotoGoColors.greenDarker : MotoGoColors.green, width: 1.5)),
                child: Center(child: Text(size,
                  style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                    color: active ? Colors.black : MotoGoColors.black)))),
            );
          }).toList()),
      ]),
    );
  }
}
