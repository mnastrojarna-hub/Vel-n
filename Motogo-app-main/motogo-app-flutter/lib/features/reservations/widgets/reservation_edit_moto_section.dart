import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../catalog/moto_model.dart';
import '../../catalog/catalog_provider.dart';
import 'reservation_edit_widgets.dart';

/// Moto change collapsible card for reservation edit.
class EditMotoChangeSection extends ConsumerWidget {
  final String currentMotoName;
  final String? currentMotoId;
  final String? newMotoId;
  final bool expanded;
  final String? userLicense;
  final ValueChanged<String?> onMotoSelected;
  final VoidCallback onToggleExpanded;

  const EditMotoChangeSection({
    super.key,
    required this.currentMotoName,
    required this.currentMotoId,
    required this.newMotoId,
    required this.expanded,
    required this.userLicense,
    required this.onMotoSelected,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final motosAsync = ref.watch(motorcyclesProvider);

    return EditCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: onToggleExpanded,
        child: Row(children: [
          const Icon(Icons.swap_horiz, size: 16, color: MotoGoColors.greenDark),
          const SizedBox(width: 6),
          const Expanded(child: Text('ZMĚNA MOTORKY', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
          Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: MotoGoColors.g400),
        ]),
      ),
      const SizedBox(height: 8),
      // Current moto
      Container(padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Text('AKTUÁLNÍ MOTORKA  ', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker)),
          Expanded(child: Text(currentMotoName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
        ])),
      if (expanded) ...[
        const SizedBox(height: 8),
        const Text('VYBERTE NOVOU MOTORKU', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.g400)),
        const SizedBox(height: 6),
        motosAsync.when(
          data: (motos) {
            final available = motos.where((m) {
              if (m.id == currentMotoId) return false;
              if (userLicense != null && m.licenseRequired != null) {
                const hierarchy = ['AM', 'A1', 'A2', 'A', 'N'];
                final userIdx = hierarchy.indexOf(userLicense!);
                final motoIdx = hierarchy.indexOf(m.licenseRequired!);
                if (userIdx >= 0 && motoIdx >= 0 && motoIdx > userIdx) return false;
              }
              return true;
            }).toList();
            return Column(children: available.map((m) {
              final selected = newMotoId == m.id;
              return GestureDetector(
                onTap: () => onMotoSelected(selected ? null : m.id),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: selected ? MotoGoColors.greenPale : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? MotoGoColors.green : MotoGoColors.g200, width: selected ? 2 : 1)),
                  child: Row(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(6),
                      child: m.displayImage.isNotEmpty
                          ? CachedNetworkImage(imageUrl: m.displayImage, width: 48, height: 36, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(width: 48, height: 36, color: MotoGoColors.g200))
                          : Container(width: 48, height: 36, color: MotoGoColors.g200)),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.model, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                      Text('${m.licenseRequired ?? '–'} · ${m.priceLabel}/den',
                        style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
                    ])),
                  ]),
                ),
              );
            }).toList());
          },
          loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
          error: (_, __) => const Text('Chyba načítání', style: TextStyle(color: MotoGoColors.red)),
        ),
      ],
    ]));
  }
}
