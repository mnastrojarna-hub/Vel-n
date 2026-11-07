import 'package:flutter/material.dart';

import '../../../core/booking_address_carry.dart';

/// Rychlé volby v listu adresy (2026-10-22, „nic nevyplňovat dvakrát“):
/// adresa druhé strany předání a adresa z profilu jedním klepnutím. Volba
/// jde stejnou cestou jako položka našeptávače (`_pick` listu: geokódování,
/// vzdálenost, cena) — zákazník pak jen potvrdí. Sdílí oba stromy appky.
class AddressQuickOptions extends StatelessWidget {
  final List<AddrQuick> options;
  final ValueChanged<AddrQuick> onPick;

  const AddressQuickOptions({super.key, required this.options, required this.onPick});

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Semantics(
                button: true,
                label: '${o.label}: ${o.line}',
                excludeSemantics: true,
                child: Material(
                  color: const Color(0xFFE8FFE8),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onPick(o),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(children: [
                          const Icon(Icons.home_outlined, size: 18, color: Color(0xFF1A8A18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(o.label,
                                    style: const TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1A8A18))),
                                const SizedBox(height: 2),
                                Text(o.line,
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F1A14))),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 18, color: Color(0xFF1A8A18)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
