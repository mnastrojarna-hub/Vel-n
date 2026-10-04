import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../catalog_provider.dart';

/// Zvolená pobočka u SBALENÉHO panelu filtrů ([MotoFilterPanel]) — po
/// „Rezervovat" z detailu pobočky je hned vidět, že výpis ukazuje jen motorky
/// této pobočky (jinak by to prozradil jen počet v odznaku). Bez zvolené
/// pobočky (nebo než se načte její název) nezobrazí nic.
class FilterBranchChip extends ConsumerWidget {
  const FilterBranchChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(catalogFilterProvider.select((f) => f.branch));
    if (id == null) return const SizedBox.shrink();
    String? name;
    for (final b in ref.watch(branchesProvider)) {
      if (b['id'] == id) name = b['name'] as String?;
    }
    if (name == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: MotoGoColors.greenPale,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_outlined, size: 15, color: MotoGoColors.greenDarker),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${t(context).tr('branchPrefix')}: $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: MotoGoColors.greenDarker,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
