import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../booking/booking_models.dart';

// ignore_for_file: library_private_types_in_public_api

// ─── _Card ────────────────────────────────────────────────────────────────────

class EditCard extends StatelessWidget {
  final Widget child;
  const EditCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    child: Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)]),
      child: child));
}

// ─── _DateBox ─────────────────────────────────────────────────────────────────

class EditDateBox extends StatelessWidget {
  final String label, date;
  const EditDateBox({super.key, required this.label, required this.date});
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(10),
      border: Border.all(color: MotoGoColors.green, width: 1.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MotoGoColors.greenDark)),
      Text(date, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
    ])));
}

// ─── _PriceRow ────────────────────────────────────────────────────────────────

class EditPriceRow extends StatelessWidget {
  final String label, value;
  const EditPriceRow(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.black)),
    ]));
}

// ─── _LegendDot ───────────────────────────────────────────────────────────────

class EditLegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool hasBorder;
  const EditLegendDot({super.key, required this.color, required this.label, this.hasBorder = false});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 10, height: 10,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3),
        border: hasBorder ? Border.all(color: MotoGoColors.g200) : null)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
  ]);
}

// ─── _TabBtn ──────────────────────────────────────────────────────────────────

class EditTabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const EditTabBtn({super.key, required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(child: GestureDetector(onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: active ? MotoGoColors.green : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? MotoGoColors.green : MotoGoColors.g200)),
      child: Center(child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
          color: active ? Colors.black : MotoGoColors.greenDark))))));
}

// ─── _TimePicker ──────────────────────────────────────────────────────────────

class EditTimePicker extends StatelessWidget {
  final String label;
  final String value; // "HH:MM"
  final ValueChanged<String> onChanged;
  const EditTimePicker({super.key, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final parts = value.split(':');
    final hour = parts.isNotEmpty ? parts[0] : '09';
    final minute = parts.length > 1 ? parts[1] : '00';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.g400)),
      const SizedBox(height: 4),
      Row(children: [
        // Hours
        Expanded(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: MotoGoColors.greenPale,
            borderRadius: BorderRadius.circular(10), border: Border.all(color: MotoGoColors.green, width: 1.5)),
          child: DropdownButtonHideUnderline(child: DropdownButton<String>(
            value: hour, isExpanded: true,
            dropdownColor: Colors.white,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: MotoGoColors.black),
            items: List.generate(24, (i) {
              final h = i.toString().padLeft(2, '0');
              return DropdownMenuItem(value: h, child: Center(child: Text(h)));
            }),
            onChanged: (v) => onChanged('${v ?? hour}:$minute'),
          )))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: MotoGoColors.black))),
        // Minutes
        Expanded(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: MotoGoColors.greenPale,
            borderRadius: BorderRadius.circular(10), border: Border.all(color: MotoGoColors.green, width: 1.5)),
          child: DropdownButtonHideUnderline(child: DropdownButton<String>(
            value: _nearestQuarter(minute), isExpanded: true,
            dropdownColor: Colors.white,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: MotoGoColors.black),
            items: ['00', '15', '30', '45'].map((m) =>
              DropdownMenuItem(value: m, child: Center(child: Text(m)))).toList(),
            onChanged: (v) => onChanged('$hour:${v ?? minute}'),
          )))),
        const SizedBox(width: 6),
        const Text('hod', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
      ]),
    ]);
  }

  String _nearestQuarter(String min) {
    final m = int.tryParse(min) ?? 0;
    if (m < 8) return '00';
    if (m < 23) return '15';
    if (m < 38) return '30';
    return '45';
  }
}

// ─── _ExtraCheckbox ───────────────────────────────────────────────────────────

class EditExtraCheckbox extends StatelessWidget {
  final String id, label, sub;
  final double price;
  final bool checked;
  final ValueChanged<bool> onChanged;
  const EditExtraCheckbox({super.key, required this.id, required this.label, required this.sub,
    required this.price, required this.checked, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!checked),
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
          Text(sub, style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
        ])),
        Text('+${price.toStringAsFixed(0)} Kč',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.greenDark)),
      ])));
}

// ─── _EditGearSizePicker ──────────────────────────────────────────────────────

/// Gear size picker for reservation edit screen.
class EditGearSizePicker extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? selectedSize;
  final ValueChanged<String?> onSizeSelected;
  final List<String> sizes;

  const EditGearSizePicker({
    super.key,
    required this.label,
    required this.icon,
    required this.selectedSize,
    required this.onSizeSelected,
    this.sizes = gearSizes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selectedSize != null ? MotoGoColors.greenPale : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selectedSize != null ? MotoGoColors.green : MotoGoColors.g200,
          width: selectedSize != null ? 2 : 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: MotoGoColors.greenDarker),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
          const Spacer(),
          if (selectedSize != null)
            Text('Zvoleno: $selectedSize',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.greenDark)),
          const Text('  ZDARMA', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MotoGoColors.g400)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 5, runSpacing: 5,
          children: sizes.map((size) {
            final active = selectedSize == size;
            return GestureDetector(
              onTap: () => onSizeSelected(active ? null : size),
              child: Container(
                width: 42, height: 32,
                decoration: BoxDecoration(
                  color: active ? MotoGoColors.greenDarker : MotoGoColors.greenPale,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: active ? MotoGoColors.greenDarker : MotoGoColors.green, width: 1.5)),
                child: Center(child: Text(size,
                  style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                    color: active ? Colors.black : MotoGoColors.black)))),
            );
          }).toList()),
      ]),
    );
  }
}
