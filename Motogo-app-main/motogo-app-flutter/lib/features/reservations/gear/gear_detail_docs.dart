import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/i18n/server_reasons.dart';
import '../../../core/v2/flag/v2_scope.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../reservation_models.dart';
import '../widgets/res_detail_button.dart';
import 'gear_booking_api.dart';
import 'gear_note.dart';

/// Doklad totožnosti ke KONKRÉTNÍ výpůjčce výbavy (web „Doklad totožnosti“):
/// stav z `check_booking_docs_status_for` (null = OK). Jen OP (obě strany)
/// nebo pas + 18+ — řidičák ne. Nahrání = scanner v režimu `missing_id`
/// s návratem na detail; chybí-li datum narození (OCR ho nepřečetlo),
/// odkaz do Profilu → osobní údaje.
class GearDocsCard extends ConsumerWidget {
  final Reservation res;
  const GearDocsCard({super.key, required this.res});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = {'pending', 'reserved', 'active'}.contains(res.status) &&
        res.displayStatus != ResStatus.cancelled &&
        res.displayStatus != ResStatus.dokoncene;
    if (!live) return const SizedBox.shrink();
    final tr = t(context);
    final reason = ref.watch(gearDocsStatusProvider(res.id)).valueOrNull;
    final loaded = ref.watch(gearDocsStatusProvider(res.id)).hasValue;
    if (!loaded || reason == '?') return const SizedBox.shrink();
    if (reason == null) {
      return GearNoteBox(
        key: const ValueKey('gear-docs-ok'),
        tone: MgTone.ok,
        title: tr.tr('gearDocsLabel'),
        text: tr.tr('gearDocsOk'),
      );
    }
    final dob = reason.contains('narození');
    // Důvody serveru (`; `): „chybí OP (líc a rub) nebo pas“ jen opakuje
    // výzvu k nahrání → bez něj; jiné (strana OP, datum narození, 18+) zůstanou.
    final parts = reason.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final idMissing = parts.any((p) => p.contains('OP') || p.contains('pas')) || (!dob && !reason.contains('18'));
    final why = [
      for (final p in parts)
        if (p != 'Chybí OP (líc a rub) nebo pas') localizeServerReason(tr, p),
    ].whereType<String>().where((s) => s.isNotEmpty);
    final lines = [
      if (idMissing) tr.tr('gearDocsMissing'),
      ...why,
      if (dob) tr.tr('gearDocsDobHint'),
      if (idMissing) tr.tr('gearDocsIdOnly'),
    ];
    final text = (lines.isEmpty ? [tr.tr('gearDocsMissing')] : lines).join('\n');
    void upload() => openGearIdDocs(context, ref, res.id);
    return GearNoteBox(
      key: const ValueKey('gear-docs-missing'),
      tone: MgTone.warn,
      title: tr.tr('gearDocsLabel'),
      text: text,
      actions: [
        if (MgV2.on(context))
          MgBtnInk(
            key: const ValueKey('gear-docs-btn'),
            label: tr.tr('gearDocsCta'),
            icon: MgIcons.idCard,
            height: 44,
            onTap: upload,
          )
        else
          ResDetailButton.primary(key: const ValueKey('gear-docs-btn'), emoji: '🪪', label: tr.tr('gearDocsCta'), onTap: upload),
      ],
    );
  }
}
