import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_photo.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../catalog/moto_model.dart';

/// What the right side of a bike row says (the old row's same states).
enum EditMotoStatus { none, free, busy, loading, trailer }

/// A bike in the edit "Jiná motorka" / "Výměna motorky" lists in the v2
/// look (catalog calc rows): photo 72×56, name 15/800, licence · price per
/// day, and the old row's state on the right ("Volno" pill / "Obsazeno" pill /
/// "Vozík jen na obslužné" / spinner). Selected = the MgChoiceCard style.
/// [onTap] null = not selectable (as the old row).
class EditMotoRowV2 extends StatelessWidget {
  final Motorcycle moto;
  final bool selected;
  final bool dim;
  final EditMotoStatus status;
  final VoidCallback? onTap;

  const EditMotoRowV2({
    super.key,
    required this.moto,
    required this.selected,
    required this.status,
    this.dim = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final m = moto;
    final groups = m.licenseGroupsOrFallback.where((g) => g != 'N').join(' / ');
    final meta = '${groups.isEmpty ? '–' : groups} · ${m.priceLabel}${tr.tr('pricePerDay')}';
    final Widget? trailing = switch (status) {
      EditMotoStatus.trailer => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: Text(tr.tr('swap.trailerStaffedOnly'),
              textAlign: TextAlign.end, style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.warn)),
        ),
      EditMotoStatus.busy => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: MgColors.warnBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MgColors.warnBorder),
          ),
          child: Text(tr.tr('swap.occupied'), style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.warn)),
        ),
      EditMotoStatus.loading =>
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: MgColors.link)),
      EditMotoStatus.free => selected
          ? Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(color: MgColors.ink, shape: BoxShape.circle),
              child: const Center(child: MgIcon(MgIcons.check, size: 15, color: MgColors.onDark, stroke: 2.6)),
            )
          // E3-05: a free bike says "Volno" (a tick read as "already chosen").
          : Container(
              key: const ValueKey('edit-moto-free-pill'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: MgColors.tintOk,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: MgColors.tintOkBorder),
              ),
              child: Text(tr.tr('jxBikeFree'),
                  style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.onTintOk)),
            ),
      EditMotoStatus.none => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: onTap != null,
        selected: selected,
        child: MgPress(
          onTap: onTap,
          child: Opacity(
            opacity: dim ? 0.5 : 1,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected ? MgColors.tintOk : MgColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: selected ? MgColors.tintOkBorder : MgColors.line, width: selected ? 1.5 : 1),
              ),
              child: Row(children: [
                MgPhoto(
                  url: m.displayImage,
                  thumbWidth: 200,
                  width: 72,
                  height: 56,
                  glyph: MgIcons.moto,
                  borderRadius: BorderRadius.circular(MgRadius.thumb),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    MgWordFit(
                      minScale: 0.85,
                      child: Text(m.model,
                          style: MgType.title.copyWith(color: selected ? MgColors.onTintOk : MgColors.ink)),
                    ),
                    const SizedBox(height: 2),
                    Text(meta, style: MgType.tab(MgType.small.copyWith(color: MgColors.meta))),
                  ]),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// E3-04: one grey line under the bike lists — the licence filter (same as
/// the old look, unchanged) hides bikes the customer may not ride.
class EditLicenceHiddenNoteV2 extends StatelessWidget {
  const EditLicenceHiddenNoteV2({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        key: const ValueKey('edit-licence-hidden-note'),
        padding: const EdgeInsets.only(top: 2),
        child: Text(t(context).tr('jxLicenceHiddenNote'), style: MgType.small.copyWith(color: MgColors.meta)),
      );
}

/// v2 look of `EditBranchFilter`: the same choice (all branches / one
/// branch) as a scrolling row of filter chips instead of the Material
/// dropdown — the SAME [onChanged] with the branch id (null = all). Tapping
/// the chip already chosen changes nothing (as re-picking in the dropdown).
class EditBranchFilterV2 extends StatelessWidget {
  final List<Map<String, dynamic>> branches;
  final String? value;
  final ValueChanged<String?> onChanged;
  const EditBranchFilterV2({super.key, required this.branches, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget chip(String label, String? id) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: MgFilterChip(
            label: label,
            icon: id == null ? MgIcons.pin : null,
            selected: value == id,
            onTap: value == id ? null : () => onChanged(id),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(children: [
          chip(tr.tr('filtersAllBranches'), null),
          for (final b in branches) chip('${b['name']}', b['id'] as String?),
        ]),
      ),
    );
  }
}
