import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_photo.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../catalog/catalog_provider.dart' show MotoCategory;
import '../../catalog/moto_model.dart';
import 'sos_actions_v2.dart';
import 'sos_header_v2.dart';
import 'sos_widgets_v2.dart';

/// Rows shown before "Zobrazit další (n)".
const kSosReplacementFirst = 6;

/// v2 "Náhradní motorka – zdarma" (SOS board): green bike header, free bikes
/// as photo rows (first 6, then "Zobrazit další (n)"), delivery address
/// (the screen's own address widgets), night dock with the neon confirm
/// above the nonstop line. Selection / confirm = the screen's own.
class SosReplacementViewV2 extends StatefulWidget {
  final AsyncValue<List<Motorcycle>> motos;
  final String? selectedId;
  final ValueChanged<Motorcycle> onSelect;
  final bool loading;
  final VoidCallback onConfirm;
  final VoidCallback onBack;
  final Widget hereAddress;
  final Widget addressField;
  final Widget Function(Object error) error;
  final Widget callButton;
  const SosReplacementViewV2({
    super.key,
    required this.motos,
    required this.selectedId,
    required this.onSelect,
    required this.loading,
    required this.onConfirm,
    required this.onBack,
    required this.hereAddress,
    required this.addressField,
    required this.error,
    required this.callButton,
  });

  @override
  State<SosReplacementViewV2> createState() => _SosReplacementViewV2State();
}

class _SosReplacementViewV2State extends State<SosReplacementViewV2> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final Widget list = widget.motos.when(
      data: (motos) {
        if (motos.isEmpty) {
          return MgStateBanner(
            tone: MgTone.warn,
            title: tr.tr('v2UxAsmNoBikesTitle'),
            text: tr.tr('sosNoMotos'),
            actions: [widget.callButton],
          );
        }
        final shown = _all ? motos : motos.take(kSosReplacementFirst).toList();
        final more = motos.length - shown.length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MgAnimatedSize(
            duration: MgMotion.of(context, MgMotion.sticky),
            curve: MgMotion.emphasized,
            alignment: Alignment.topCenter,
            child: Column(children: [
              for (final m in shown) ...[
                _SosBikeRowV2(moto: m, selected: widget.selectedId == m.id, onTap: () => widget.onSelect(m)),
                const SizedBox(height: 8),
              ],
            ]),
          ),
          if (more > 0)
            Center(
              child: MgBtnText(
                label: tr.trArgs('v2UxAsmShowMore', {'n': more}),
                icon: MgIcons.chevronDown,
                onTap: () => setState(() => _all = true),
              ),
            ),
        ]);
      },
      loading: () => const Column(children: [
        MgSkeletonRow(thumb: 64, lines: 2),
        SizedBox(height: 8),
        MgSkeletonRow(thumb: 64, lines: 2),
        SizedBox(height: 8),
        MgSkeletonRow(thumb: 64, lines: 2),
      ]),
      error: (e, _) => widget.error(e),
    );
    return SosPageV2(
      onBack: widget.onBack,
      header: SosHeaderV2(
        onBack: widget.onBack,
        icon: MgIcons.bike,
        tint: SosTint.green,
        eyebrow: tr.tr('replacementMoto'),
        title: tr.tr('replacementFree'),
        sub: tr.tr('breakdownFreeBannerDesc'),
      ),
      dock: SosDockV2(
        cta: SosNeonButtonV2(
          label: tr.tr('v2UxAsmConfirmFree'),
          icon: MgIcons.checkCircle,
          busy: widget.loading,
          onTap: widget.onConfirm,
        ),
      ),
      sections: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SosEyebrowV2(tr.tr('v2UxAsmPickBike')),
          list,
        ]),
        const SizedBox(height: 4),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SosEyebrowV2(tr.tr('deliveryAddress')),
          widget.hereAddress,
          const SizedBox(height: 8),
          widget.addressField,
        ]),
      ],
    );
  }
}

class _SosBikeRowV2 extends StatelessWidget {
  final Motorcycle moto;
  final bool selected;
  final VoidCallback onTap;
  const _SosBikeRowV2({required this.moto, required this.selected, required this.onTap});

  String _category(BuildContext context) {
    final cat = moto.category;
    if (cat == null || cat.isEmpty) return '';
    final key = MotoCategory.labelKey(cat);
    return key == 'all' ? cat : t(context).tr(key);
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final cat = _category(context);
    final d = MgMotion.of(context, MgMotion.color);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: '${moto.model}${cat.isEmpty ? '' : ', $cat'}, ${tr.free}',
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: AnimatedContainer(
          duration: d,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? MgColors.tintOk : MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? MgColors.tintOkBorder : MgColors.line, width: selected ? 1.5 : 1),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: d,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? MgColors.link : MgColors.surface,
                border: Border.all(color: selected ? MgColors.link : MgColors.lineInput, width: 2),
              ),
              child: selected ? const Center(child: MgIcon(MgIcons.check, size: 14, color: MgColors.onDark)) : null,
            ),
            const SizedBox(width: 10),
            MgPhoto(
              url: moto.imageUrl ?? (moto.images.isEmpty ? '' : moto.images.first),
              width: 72,
              height: 56,
              thumbWidth: 216,
              glyph: MgIcons.bike,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(moto.model, style: MgType.small.copyWith(fontSize: 14, fontWeight: FontWeight.w800, color: MgColors.ink)),
                if (cat.isNotEmpty)
                  MgWordFit(minScale: 0.7, child: Text(cat, style: MgType.micro.copyWith(fontSize: 12, color: MgColors.meta))),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: MgColors.tintOk, borderRadius: BorderRadius.circular(999)),
                  child: Text(tr.free, style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.onTintOk)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
