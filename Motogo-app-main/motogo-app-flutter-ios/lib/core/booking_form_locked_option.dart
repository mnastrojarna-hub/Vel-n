import 'package:flutter/material.dart';

/// Zabalená (nedostupná) volba převzetí/vrácení — samoobslužná pobočka bez
/// přistavení a odvozu na adresu (2026-09-28). Vypadá jako radio dlaždice
/// (`bookingRadio`), ale nejde vybrat: šedý zámek, krátký důvod a po klepnutí
/// se rozbalí vysvětlení. Zůstává ve formuláři i v úpravě rezervace, aby
/// zákazník viděl, že volba existuje a proč ji teď nemá.
class BookingLockedOptionTile extends StatefulWidget {
  const BookingLockedOptionTile({
    super.key,
    required this.label,
    required this.shortReason,
    required this.info,
  });

  /// Název volby („Přistavení na vaši adresu“ / „Odvoz z vaší adresy“).
  final String label;

  /// Krátký důvod pod názvem („Na samoobslužné pobočce zatím není k dispozici“).
  final String shortReason;

  /// Vysvětlení po rozbalení.
  final String info;

  @override
  State<BookingLockedOptionTile> createState() => _BookingLockedOptionTileState();
}

class _BookingLockedOptionTileState extends State<BookingLockedOptionTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    const noDec = TextDecoration.none;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAF8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD4E8E0), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFB9CFC4), width: 2),
                ),
                child: const Icon(Icons.lock, size: 10, color: Color(0xFF8AAB99)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF8AAB99),
                            decoration: noDec)),
                    Text(widget.shortReason,
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF8AAB99), decoration: noDec)),
                  ],
                ),
              ),
              Icon(_open ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: const Color(0xFF8AAB99)),
            ]),
            if (_open)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(widget.info,
                    style: const TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: Color(0xFF4A6357),
                        decoration: noDec)),
              ),
          ],
        ),
      ),
    );
  }
}
