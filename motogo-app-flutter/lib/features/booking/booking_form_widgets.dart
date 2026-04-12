import 'package:flutter/material.dart';
import 'booking_models.dart';

/// Pure UI helper widgets for inline booking form.
/// NO ConsumerStatefulWidget, NO Riverpod — just widget builders.

const _noDec = TextDecoration.none;

/// Numbered section card.
Widget bookingCard(int n, String title, Widget content) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 12)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Row(children: [
          Container(width: 24, height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFF74FB71),
              shape: BoxShape.circle),
            child: Center(child: Text('$n',
              style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.white, decoration: _noDec)))),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F1A14), decoration: _noDec)),
        ]),
        const SizedBox(height: 12),
        content,
      ])));
}

/// Radio option tile for pickup/return.
Widget bookingRadio(String label, String sub, String price,
    bool sel, VoidCallback onTap) {
  return GestureDetector(onTap: onTap,
    child: Container(padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: sel ? const Color(0xFFE8FFE8) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: sel ? const Color(0xFF74FB71)
              : const Color(0xFFD4E8E0),
          width: sel ? 2 : 1)),
      child: Row(children: [
        Container(width: 18, height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: sel ? const Color(0xFF74FB71)
                  : const Color(0xFF8AAB99), width: 2)),
          child: sel ? Center(child: Container(
            width: 10, height: 10,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF74FB71)))) : null),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(label, style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w700, decoration: _noDec)),
          Text(sub, style: const TextStyle(fontSize: 10,
            color: Color(0xFF8AAB99), decoration: _noDec)),
        ])),
        Text(price, style: TextStyle(fontSize: 11,
          fontWeight: FontWeight.w700,
          color: sel ? const Color(0xFF1A8A18)
              : const Color(0xFF8AAB99),
          decoration: _noDec)),
      ])));
}

/// Consent checkbox.
Widget bookingCheckbox(String label, bool val, ValueChanged<bool> cb) {
  return GestureDetector(onTap: () => cb(!val),
    child: Row(children: [
      Container(width: 20, height: 20,
        decoration: BoxDecoration(
          color: val ? const Color(0xFF74FB71)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: val ? const Color(0xFF74FB71)
                : const Color(0xFFD4E8E0), width: 2)),
        child: val ? const Icon(Icons.check,
          size: 14, color: Colors.white) : null),
      const SizedBox(width: 8),
      Expanded(child: Text(label,
        style: const TextStyle(fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF4A6357), decoration: _noDec))),
    ]));
}

/// Price row.
Widget bookingPriceRow(String label, String value,
    {bool subtle = false, Color? color}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label, style: TextStyle(fontSize: 12,
          fontWeight: subtle ? FontWeight.w500 : FontWeight.w600,
          color: subtle ? const Color(0xFF8AAB99)
              : const Color(0xFF4A6357),
          decoration: _noDec))),
        Text(value, style: TextStyle(fontSize: 12,
          fontWeight: color != null ? FontWeight.w800
              : FontWeight.w600,
          color: color ?? (subtle ? const Color(0xFF8AAB99)
              : const Color(0xFF0F1A14)),
          decoration: _noDec)),
      ]));
}

/// Gear size picker row.
Widget bookingGearRow(String label, String? selected,
    ValueChanged<String?> onChanged) {
  return Padding(padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
      Text(label, style: const TextStyle(fontSize: 12,
        fontWeight: FontWeight.w700, decoration: _noDec)),
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 6,
        children: gearSizes.map((s) {
          final a = selected == s;
          return GestureDetector(
            onTap: () => onChanged(a ? null : s),
            child: Container(
              width: 46, height: 36,
              decoration: BoxDecoration(
                color: a ? const Color(0xFF1A8A18)
                    : const Color(0xFFE8FFE8),
                borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text(s,
                style: TextStyle(fontSize: 12,
                  fontWeight: a ? FontWeight.w900
                      : FontWeight.w600,
                  color: a ? Colors.white
                      : const Color(0xFF0F1A14),
                  decoration: _noDec)))));
        }).toList()),
    ]));
}
