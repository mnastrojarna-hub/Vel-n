import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../documents/booking_doc_viewer.dart';
import '../res_actions.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import '../widgets/res_modification_history.dart';

/// "Dokumenty" (one white band): the SAME documents as today's detail —
/// completed: final invoice, contract, then the signed protocols; during
/// the rental (calendar term or handed over): contract + protocols when
/// they exist (`bookingDocsProvider`, real 1:1 documents only).
class ResDocsV2 extends ConsumerWidget {
  final Reservation res;
  final Future<void> Function(BuildContext, String) onOpenFinalInvoice;
  final Future<void> Function(BuildContext, String) onOpenContract;
  const ResDocsV2({super.key, required this.res, required this.onOpenFinalInvoice, required this.onOpenContract});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final st = res.displayStatus;
    final docs = ref.watch(bookingDocsProvider(res.id)).valueOrNull ?? const <String, BookingDocSource>{};
    bool has(String type) => docs.containsKey(type);
    final items = <(String, String, VoidCallback)>[];
    void bookingDocs({required bool includeContract}) {
      if (includeContract && has('contract')) {
        items.add((MgIcons.doc, tr.tr('rentalContract'), () => openBookingDoc(context, res, 'contract', tr.tr('rentalContract'))));
      }
      if (has('protocol')) {
        items.add((MgIcons.protocol, tr.tr('handoverProtocol'), () => openBookingDoc(context, res, 'protocol', tr.tr('handoverProtocol'))));
      }
      if (has('protocol_damage')) {
        items.add((MgIcons.warn, tr.tr('damageProtocol'), () => openBookingDoc(context, res, 'protocol_damage', tr.tr('damageProtocol'))));
      }
    }

    if (st == ResStatus.dokoncene) {
      items.add((MgIcons.receipt, tr.tr('finalInvoice'), () => onOpenFinalInvoice(context, res.id)));
      items.add((MgIcons.doc, tr.tr('rentalContract'), () => onOpenContract(context, res.id)));
      bookingDocs(includeContract: false);
    } else if (res.inRentalTerm || st == ResStatus.aktivni) {
      bookingDocs(includeContract: true);
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      color: MgColors.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgEyebrow(tr.tr('documentsSection'), dark: false),
        const SizedBox(height: 4),
        for (var i = 0; i < items.length; i++)
          _DocRow(icon: items[i].$1, label: items[i].$2, onTap: items[i].$3, divider: i < items.length - 1),
      ]),
    );
  }
}

class _DocRow extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool divider;
  const _DocRow({required this.icon, required this.label, required this.onTap, required this.divider});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: MgPress(
        scale: 0.98,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          decoration: BoxDecoration(
            border: divider ? const Border(bottom: BorderSide(color: MgColors.line)) : null,
          ),
          child: Row(children: [
            MgIconTileLight(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: MgType.body.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink))),
            const SizedBox(width: 8),
            Text(tr.tr('v2ResOpenDoc'), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
            const MgIcon(MgIcons.chevronRight, size: 18, color: MgColors.link),
          ]),
        ),
      ),
    );
  }
}

/// "Historie rezervace" — a collapsed row that opens today's
/// `ResModificationHistory` (timeline, changes, SOS, storno) unchanged.
class ResHistoryV2 extends ConsumerStatefulWidget {
  final Reservation res;
  const ResHistoryV2({super.key, required this.res});

  @override
  ConsumerState<ResHistoryV2> createState() => _ResHistoryV2State();
}

class _ResHistoryV2State extends ConsumerState<ResHistoryV2> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final sos = ref.watch(sosIncidentsProvider(widget.res.id)).valueOrNull ?? <SosIncident>[];
    final n = widget.res.modificationHistory.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        button: true,
        expanded: _open,
        label: tr.tr('v2ResHistory'),
        excludeSemantics: true,
        child: MgPress(
          scale: 0.99,
          onTap: () => setState(() => _open = !_open),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MgColors.line),
            ),
            child: Row(children: [
              const MgIconTileLight(MgIcons.history),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr.tr('v2ResHistory'), style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
                  if (n > 0) Text(tr.trArgs('v2ResHistoryCount', {'n': n}), style: MgType.meta.copyWith(color: MgColors.meta)),
                ]),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: MgMotion.of(context, MgMotion.pop),
                child: const MgIcon(MgIcons.chevronDown, size: 20, color: MgColors.link),
              ),
            ]),
          ),
        ),
      ),
      AnimatedSize(
        duration: MgMotion.of(context, MgMotion.pop),
        curve: MgMotion.out,
        alignment: Alignment.topCenter,
        child: _open
            ? Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ResModificationHistory(res: widget.res, sosIncidents: sos),
              )
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}
