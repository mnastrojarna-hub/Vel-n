import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../catalog/moto_model.dart';
import '../../catalog/catalog_provider.dart';
import '../../booking/booking_validator.dart';
import 'reservation_edit_widgets.dart';

/// Moto change collapsible card for reservation edit.
/// Nabízí JEN motorky volné v termínu rezervace (vč. zvolené změny termínu) —
/// obsazené jsou šedé „Obsazeno" a nejdou vybrat (stejně jako výměna/swap).
class EditMotoChangeSection extends ConsumerStatefulWidget {
  final String bookingId;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final String currentMotoName;
  final String? currentMotoId;
  final String? newMotoId;
  final bool expanded;
  final String? userLicense;
  /// Rezervace má přiřazený vozík (`bookings.trailer_moto_id`). Pak nelze
  /// přejet na motorku ze SAMOOBSLUŽNÉ pobočky — vozík tam nikdo nevydá.
  /// Bez téhle zábrany by zápis spadl až PO zaplacení doplatku na Stripe
  /// (změnu aplikuje server z `PaymentContext.pendingEditChanges`).
  final bool hasTrailer;
  final ValueChanged<String?> onMotoSelected;
  final VoidCallback onToggleExpanded;

  const EditMotoChangeSection({
    super.key,
    required this.bookingId,
    required this.rangeStart,
    required this.rangeEnd,
    required this.currentMotoName,
    required this.currentMotoId,
    required this.newMotoId,
    required this.expanded,
    required this.userLicense,
    this.hasTrailer = false,
    required this.onMotoSelected,
    required this.onToggleExpanded,
  });

  @override
  ConsumerState<EditMotoChangeSection> createState() => _EditMotoChangeSectionState();
}

class _EditMotoChangeSectionState extends ConsumerState<EditMotoChangeSection> {
  // motoId -> volná v termínu? (null = ještě nezjištěno / počítá se)
  final Map<String, bool> _avail = {};
  bool _availLoading = false;
  int _availToken = 0; // proti zápisu zastaralého výsledku
  String? _rangeKey;   // "start|end" — detekce změny termínu
  String? _branch;     // filtr dle pobočky (null = všechny)

  Future<void> _recomputeAvail(List<Motorcycle> motos) async {
    final token = ++_availToken;
    setState(() => _availLoading = true);
    final cands = motos.where((m) => m.id != widget.currentMotoId).toList();
    final results = await Future.wait(cands.map((m) => checkMotoAvailability(
          m.id,
          widget.rangeStart,
          widget.rangeEnd,
          excludeBookingId: widget.bookingId,
        )));
    if (!mounted || token != _availToken) return;
    setState(() {
      _avail.clear();
      for (var i = 0; i < cands.length; i++) {
        _avail[cands[i].id] = results[i];
      }
      _availLoading = false;
    });
    // Zvolená motorka se změnou termínu přestala být volná → zruš výběr.
    if (widget.newMotoId != null && _avail[widget.newMotoId] == false) {
      widget.onMotoSelected(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final motosAsync = ref.watch(motorcyclesProvider);
    final hasChange = widget.newMotoId != null && widget.newMotoId != widget.currentMotoId;
    String? newMotoName;
    if (hasChange) {
      for (final m in (motosAsync.valueOrNull ?? const <Motorcycle>[])) {
        if (m.id == widget.newMotoId) { newMotoName = m.model; break; }
      }
      newMotoName ??= widget.newMotoId;
    }

    // Přepočet dostupnosti při prvním zobrazení a při každé změně termínu.
    final motosData = motosAsync.valueOrNull;
    final rangeKey = '${widget.rangeStart.toIso8601String()}|${widget.rangeEnd.toIso8601String()}';
    if (motosData != null && rangeKey != _rangeKey) {
      _rangeKey = rangeKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _recomputeAvail(motosData);
      });
    }

    return EditCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: widget.onToggleExpanded,
        child: Row(children: [
          const Icon(Icons.swap_horiz, size: 16, color: MotoGoColors.greenDark),
          const SizedBox(width: 6),
          Expanded(child: Text(t(context).tr('motoChange'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
          if (widget.expanded && _availLoading)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: MotoGoColors.green)),
            ),
          if (hasChange && !widget.expanded)
            Container(margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(6)),
              child: Text(t(context).tr('changeBtn'),
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black))),
          Icon(widget.expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: MotoGoColors.g400),
        ]),
      ),
      const SizedBox(height: 8),
      // Před/po: po zavření rozbalovacího menu ukaž změnu motorky.
      if (hasChange && !widget.expanded)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MotoGoColors.green, width: 1.5)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t(context).tr('currentMoto'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MotoGoColors.g400)),
              Text(widget.currentMotoName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
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
      if (!(hasChange && !widget.expanded))
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Text('${t(context).tr('currentMoto')}  ', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker)),
            Expanded(child: Text(widget.currentMotoName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
          ])),
      if (widget.expanded) ...[
        const SizedBox(height: 8),
        Text(t(context).tr('selectNewMoto'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.g400)),
        const SizedBox(height: 6),
        // Filtr dle pobočky — zvolená motorka mimo pobočku se odznačí.
        EditBranchFilter(
          value: _branch,
          onChanged: (v) {
            setState(() => _branch = v);
            if (v != null && widget.newMotoId != null) {
              final list = motosAsync.valueOrNull ?? const <Motorcycle>[];
              final keep = list.any((m) => m.id == widget.newMotoId && m.branchId == v);
              if (!keep) widget.onMotoSelected(null);
            }
          },
        ),
        motosAsync.when(
          data: (motos) {
            final available = motos.where((m) {
              if (m.id == widget.currentMotoId) return false;
              if (_branch != null && m.branchId != _branch) return false;
              // OR-match přes přijímané skupiny ŘP vozidla (vč. B pro skútry/přívěs).
              if (widget.userLicense != null) {
                final ok = BookingValidator.checkLicense(
                  userLicenseGroups: [widget.userLicense!],
                  motoLicenseGroups: m.licenseGroupsOrFallback,
                ) == null;
                if (!ok) return false;
              }
              return true;
            }).toList();
            return Column(children: available.map((m) {
              final free = _avail[m.id];
              // Vozík jen na obslužné pobočce — kus ze samoobsluhy nenabízej.
              // Tady jde VŽDY o přepis moto_id na řádku s vozíkem (na rozdíl od
              // „Výměny motorky", kde SPLIT rezervaci s vozíkem nechává být),
              // takže se blokuje bez další podmínky. Serverová pojistka:
              // process-payment (doplatek) + trg_check_trailer_overlap (20260921f).
              final trailerBlocked =
                  widget.hasTrailer && m.branchType == 'samoobslužná';
              final selectable = free == true && !trailerBlocked;
              final selected = widget.newMotoId == m.id;
              return GestureDetector(
                onTap: selectable
                    ? () => widget.onMotoSelected(selected ? null : m.id)
                    : null,
                child: Opacity(
                  opacity: (free == false || trailerBlocked) ? 0.45 : 1,
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
                            ? MgImage(m.displayImage, thumbWidth: 150, width: 48, height: 36, fit: BoxFit.cover,
                                error: Container(width: 48, height: 36, color: MotoGoColors.g200))
                            : Container(width: 48, height: 36, color: MotoGoColors.g200)),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.model, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                        Text('${m.licenseGroupsOrFallback.where((g) => g != 'N').join(' / ').isEmpty ? '–' : m.licenseGroupsOrFallback.where((g) => g != 'N').join(' / ')} · ${m.priceLabel}/den',
                          style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
                      ])),
                      const SizedBox(width: 6),
                      if (trailerBlocked)
                        Flexible(
                            child: Text(t(context).tr('swap.trailerStaffedOnly'),
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: MotoGoColors.red)))
                      else if (free == false)
                        Text(t(context).tr('swap.occupied'),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.red))
                      else if (free == null && _availLoading)
                        const SizedBox(width: 12, height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: MotoGoColors.green))
                      else if (free == true)
                        const Icon(Icons.check_circle, size: 18, color: MotoGoColors.greenDarker),
                    ]),
                  ),
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
