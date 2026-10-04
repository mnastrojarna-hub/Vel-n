import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/collapsible_section.dart';
import '../../core/widgets/net_image.dart';
import '../catalog/catalog_provider.dart';
import '../catalog/moto_model.dart';
import 'branches_widgets.dart';

/// „Motorky na pobočce“ v detailu pobočky (výchozí zabalené): motorky dané
/// pobočky z katalogu (`motorcyclesProvider`, stejné pořadí), klepnutí otevře
/// detail motorky. Pobočka bez motorek v nabídce sekci nezobrazí.
class BranchMotosSection extends ConsumerWidget {
  final String? branchId;
  const BranchMotosSection({super.key, required this.branchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = branchId;
    if (id == null) return const SizedBox.shrink();
    final async = ref.watch(motorcyclesProvider);
    if (async.hasError && !async.hasValue) return const SizedBox.shrink();
    final motos = async.valueOrNull?.where((m) => m.branchId == id).toList();
    if (motos != null && motos.isEmpty) return const SizedBox.shrink();
    final title = t(context).tr('branchMotosTitle');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CollapsibleSection(
        emoji: '🏍️',
        title: motos == null ? title : '$title (${motos.length})',
        decoration: branchesCardDecoration(),
        padding: const EdgeInsets.all(16),
        children: motos == null
            ? const [Center(child: CircularProgressIndicator(color: MotoGoColors.green))]
            : [for (final m in motos) _row(context, ref, m, motos)],
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, Motorcycle m, List<Motorcycle> all) {
    final img = m.displayImage;
    final lic = m.licenseGroupsOrFallback.where((g) => g != 'N').join(' / ');
    final spec = [
      if (m.engineCc != null) '${m.engineCc} cc',
      if (m.powerKw != null) '${m.powerKw} kW',
      if (lic.isNotEmpty) '${t(context).tr('licenseShort')} $lic',
    ].join(' · ');
    final ph = Container(
      width: 64, height: 46, color: MotoGoColors.g200,
      child: const Icon(Icons.motorcycle, size: 20, color: MotoGoColors.g400),
    );
    return GestureDetector(
      onTap: () {
        ref.read(filteredMotoIdsProvider.notifier).state = [for (final x in all) x.id];
        context.push('/moto/${m.id}');
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: MotoGoColors.g100, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: img.isEmpty
                ? ph
                : MgImage(img, thumbWidth: 200, width: 64, height: 46, fit: BoxFit.cover, error: ph),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.model, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
              if (spec.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(spec, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MotoGoColors.g400)),
              ],
            ]),
          ),
          const Icon(Icons.chevron_right, color: MotoGoColors.g400),
        ]),
      ),
    );
  }
}
