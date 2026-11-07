import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_photo.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../catalog/moto_model.dart';
import 'res_detail_bits_v2.dart';
import 'res_edit_moto_rows_v2.dart';
import 'res_edit_sections_v2.dart';

/// v2 look of `EditMotoChangeSection` ("Jiná motorka"): a DUMB view — the
/// section's State keeps availability, the branch filter and the list rule
/// ([available]), the screen keeps the chosen bike and the expand state.
/// Header row (tap = the same toggle), the current bike (photo + name),
/// the before → after row while a change is folded, and — open — the
/// branch chips + the bike rows (only a free bike is selectable; a trailer
/// booking never moves to a self-service branch). Same texts.
class EditMotoChangeViewV2 extends StatelessWidget {
  final String currentMotoName;
  final Motorcycle? currentMoto;
  final String? newMotoName;
  final bool expanded;
  final bool availLoading;
  final VoidCallback onToggleExpanded;
  final Widget branchFilter;
  final AsyncValue<List<Motorcycle>> motos;
  final List<Motorcycle> Function(List<Motorcycle>) available;
  final Map<String, bool> avail;
  final String? selectedId;
  final bool Function(Motorcycle) trailerBlocked;
  final void Function(Motorcycle m, bool selected) onTapMoto;

  const EditMotoChangeViewV2({
    super.key,
    required this.currentMotoName,
    required this.currentMoto,
    required this.newMotoName,
    required this.expanded,
    required this.availLoading,
    required this.onToggleExpanded,
    required this.branchFilter,
    required this.motos,
    required this.available,
    required this.avail,
    required this.selectedId,
    required this.trailerBlocked,
    required this.onTapMoto,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final change = newMotoName != null;
    return EditCardV2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          expanded: expanded,
          child: MgPress(
            key: const ValueKey('edit-moto-v2-toggle'),
            onTap: onToggleExpanded,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(children: [
                const MgIcon(MgIcons.swap, size: 18, color: MgColors.link),
                const SizedBox(width: 8),
                Expanded(child: MgWordFit(child: Text(tr.tr('motoChange'), style: MgType.title.copyWith(color: MgColors.ink)))),
                if (expanded && availLoading)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 8),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: MgColors.link)),
                  ),
                if (change && !expanded)
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(999)),
                    child: Text(tr.tr('changeBtn'), style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.neon)),
                  ),
                MgIcon(expanded ? MgIcons.chevronUp : MgIcons.chevronDown, size: 20, color: MgColors.meta),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (change && !expanded)
          _BeforeAfter(from: currentMotoName, to: newMotoName!)
        else
          Row(children: [
            MgPhoto(
              url: currentMoto?.displayImage ?? '',
              thumbWidth: 200,
              width: 72,
              height: 56,
              glyph: MgIcons.moto,
              borderRadius: BorderRadius.circular(MgRadius.thumb),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ResSectionEyebrowV2(tr.tr('currentMoto')),
                const SizedBox(height: 2),
                MgWordFit(minScale: 0.85, child: Text(currentMotoName, style: MgType.title.copyWith(color: MgColors.ink))),
              ]),
            ),
          ]),
        if (expanded) ...[
          const SizedBox(height: 14),
          Text(tr.tr('selectNewMoto'), style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.lead)),
          const SizedBox(height: 8),
          branchFilter,
          motos.when(
            data: (list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final m in available(list))
                Builder(builder: (context) {
                  final free = avail[m.id];
                  final blocked = trailerBlocked(m);
                  final selected = selectedId == m.id;
                  return EditMotoRowV2(
                    moto: m,
                    selected: selected,
                    dim: free == false || blocked,
                    status: blocked
                        ? EditMotoStatus.trailer
                        : free == false
                            ? EditMotoStatus.busy
                            : (free == null && availLoading)
                                ? EditMotoStatus.loading
                                : free == true
                                    ? EditMotoStatus.free
                                    : EditMotoStatus.none,
                    onTap: free == true && !blocked ? () => onTapMoto(m, selected) : null,
                  );
                }),
            ]),
            loading: () => const Column(children: [
              MgSkeletonRow(thumb: 56, lines: 2),
              SizedBox(height: 8),
              MgSkeletonRow(thumb: 56, lines: 2),
            ]),
            error: (_, __) => Text(tr.tr('loadingError'), style: MgType.body.copyWith(color: MgColors.err)),
          ),
        ],
      ]),
    );
  }
}

/// "Aktuální motorka (přeškrtnutá) → NOVÁ MOTORKA" while a change is folded.
class _BeforeAfter extends StatelessWidget {
  final String from;
  final String to;
  const _BeforeAfter({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MgColors.tintOk,
        borderRadius: BorderRadius.circular(MgRadius.action),
        border: Border.all(color: MgColors.tintOkBorder, width: 1.5),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr.tr('currentMoto'), style: MgType.micro.copyWith(color: MgColors.meta)),
            Text(from,
                style: MgType.small.copyWith(
                    fontWeight: FontWeight.w700, color: MgColors.meta, decoration: TextDecoration.lineThrough)),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: MgIcon(MgIcons.arrowRight, size: 18, color: MgColors.onTintOk),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(tr.tr('newMotoLabel'), style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.onTintOk)),
            Text(to, textAlign: TextAlign.end, style: MgType.body.copyWith(fontWeight: FontWeight.w900, color: MgColors.ink)),
          ]),
        ),
      ]),
    );
  }
}
