import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
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
    final hasChange = newMotoId != null && newMotoId != currentMotoId;
    String? newMotoName;
    if (hasChange) {
      for (final m in (motosAsync.valueOrNull ?? const [])) {
        if (m.id == newMotoId) { newMotoName = m.model; break; }
      }
      newMotoName ??= newMotoId;
    }

    return EditCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: onToggleExpanded,
        child: Row(children: [
          const Icon(Icons.swap_horiz, size: 16, color: MotoGoColors.greenDark),
          const SizedBox(width: 6),
          Expanded(child: Text(t(context).tr('motoChange'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
          if (hasChange && !expanded)
            Container(margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(6)),
              child: Text(t(context).tr('changeBtn'),
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black))),
          Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: MotoGoColors.g400),
        ]),
      ),
      const SizedBox(height: 8),
      // Před/po: po zavření rozbalovacího menu ukaž změnu motorky.
      if (hasChange && !expanded)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MotoGoColors.green, width: 1.5)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t(context).tr('currentMoto'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MotoGoColors.g400)),
              Text(currentMotoName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: MotoGoColors.g400, decoration: TextDecoration.lineThrough)),
            ])),
            const Icon(Icons.arrow_forward, size: 18, color: MotoGoColors.greenDarker),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(t(context).tr('newMotoLabel'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
              Text(newMotoName ?? '', textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
            ])),
          ])),
      // Current moto (jen když není rozpracovaná změna v náhledu)
      if (!(hasChange && !expanded))
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Text('${t(context).tr('currentMoto')}  ', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker)),
            Expanded(child: Text(currentMotoName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
          ])),
      if (expanded) ...[
        const SizedBox(height: 8),
        Text(t(context).tr('selectNewMoto'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.g400)),
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
          error: (_, __) => Text(t(context).tr('loadingError'), style: const TextStyle(color: MotoGoColors.red)),
        ),
      ],
    ]));
  }
}
