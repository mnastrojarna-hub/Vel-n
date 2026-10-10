import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import 'document_models.dart';
import 'docs_gate_provider.dart';

/// UI k bráně dokladů (2026-10-10) pro obrazovku Moje doklady — mimo
/// `documents_screen.dart` kvůli limitu velikosti souboru.

/// Volba dokladu a strany pro fotku z galerie — bez ní se fotka dřív
/// ukládala vždy jako OP bez strany a pro vydání kódů se nepočítala.
/// Vrací (typ, strana, stepKey pro saveOcrToProfile); pas = jedna strana.
Future<(ScanDocType, String?, String)?> pickGalleryDocKind(BuildContext context) {
  final tr = t(context).tr;
  final options = <(String, String, ScanDocType, String?, String)>[
    ('🪪', '${tr('idCard')} – ${tr('frontSide')}', ScanDocType.idCard, 'front', 'id_front'),
    ('🪪', '${tr('idCard')} – ${tr('backSide')}', ScanDocType.idCard, 'back', 'id_back'),
    ('📕', tr('passport'), ScanDocType.passport, null, 'passport_front'),
    ('🏍️', '${tr('driversLicense')} – ${tr('frontSide')}', ScanDocType.driversLicense, 'front', 'dl_front'),
    ('🏍️', '${tr('driversLicense')} – ${tr('backSide')}', ScanDocType.driversLicense, 'back', 'dl_back'),
  ];
  return showModalBottomSheet<(ScanDocType, String?, String)>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t(ctx).tr('galleryPickDocType'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
          const SizedBox(height: 16),
          ...options.map((o) => ListTile(
                leading: Text(o.$1, style: const TextStyle(fontSize: 22)),
                title: Text(o.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, (o.$3, o.$4, o.$5)),
              )),
        ]),
      ),
    ),
  );
}

/// Jeden řádek „Chybí: …“ dle brány dokladů (co ještě drží přístupové kódy).
class DocsGateMissingLine extends StatelessWidget {
  final DocsGateChecklist gate;
  const DocsGateMissingLine({super.key, required this.gate});

  @override
  Widget build(BuildContext context) {
    final items = docsGateMissingLabels(context, gate);
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('${t(context).tr('missing')}: ${items.join(', ')}',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF78350F), height: 1.4)),
    );
  }
}
