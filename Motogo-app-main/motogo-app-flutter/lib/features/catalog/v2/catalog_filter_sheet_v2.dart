import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../catalog_provider.dart';
import '../widgets/moto_filter_panel.dart';

/// "Filtry" light sheet of the v2 Motorky tab (PLAN §2.2.1): hosts the
/// UNCHANGED shared `MotoFilterPanel` (category, ŘP, branch, kW / sedlo /
/// Nm / kg sliders, dnes volné, řazení, reset — every change applies at
/// once, exactly as before), opened, without the dates (they live in the
/// date pill, like the old screen's calendar above the panel). The footer
/// only closes the sheet and shows the live result count.
Future<void> showCatalogFilterSheet(BuildContext context) => showMgSheet<void>(
      context,
      title: t(context).tr('v2CatFilters'),
      builder: (_) => const MotoFilterPanel(initiallyOpen: true, embedded: true),
      footer: const _ResultsButton(),
    );

class _ResultsButton extends ConsumerWidget {
  const _ResultsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final n = ref.watch(filteredMotorcyclesProvider).valueOrNull?.length;
    final label = n == null ? tr.tr('v2CatShowResults') : '${tr.tr('v2CatShowResults')} · $n';
    return MgBtnInk(label: label, onTap: () => Navigator.of(context).maybePop());
  }
}
