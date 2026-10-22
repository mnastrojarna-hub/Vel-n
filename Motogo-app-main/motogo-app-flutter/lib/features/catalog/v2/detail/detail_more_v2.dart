import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_row.dart';
import '../../moto_model.dart';
import '../../widgets/manual_card.dart';
import '../../widgets/moto_video_player.dart';
import 'detail_specs_v2.dart';
import 'detail_trip_card_v2.dart';
import '../catalog_price.dart';

/// Light sections under "Tvoje jízda": V kostce (`shortDescItems`, label +
/// value), Popis (localized plain description, 4 lines + Zobrazit víc),
/// Video (the UNCHANGED `MotoVideoPlayer`), Víc o motorce (all parameters
/// = old `SpecsSection` data, day price list = old `PricingTable` data,
/// the manual = `ManualCard` v2 look, branch). Nothing dropped.
class DetailMoreV2 extends StatefulWidget {
  final Motorcycle moto;
  final String branchInfo;
  const DetailMoreV2({super.key, required this.moto, required this.branchInfo});

  @override
  State<DetailMoreV2> createState() => _DetailMoreV2State();
}

class _DetailMoreV2State extends State<DetailMoreV2> {
  bool _desc = false;
  bool _params = false;
  bool _prices = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final m = widget.moto;
    final sd = m.shortDescItems(tr.tr);
    final desc = m.descriptionPlainFor(tr.lang);
    final specs = m.specList(tr.tr);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (sd.isNotEmpty)
        DetailSectionV2(
          title: tr.tr('v2DetGlance'),
          icon: MgIcons.list,
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final it in sd)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: MgColors.well,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: MgColors.line),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(it.label.toUpperCase(), style: MgType.micro.copyWith(color: MgColors.meta, letterSpacing: 0.6)),
                  const SizedBox(height: 4),
                  Text(it.value, style: MgType.tab(MgType.title.copyWith(color: MgColors.ink))),
                ]),
              ),
          ]),
        ),
      if (desc != null)
        DetailSectionV2(
          title: tr.tr('v2DetDescription'),
          icon: MgIcons.doc,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            catAnimatedSize(context, Text(
                desc,
                maxLines: _desc ? null : 4,
                overflow: _desc ? TextOverflow.visible : TextOverflow.ellipsis,
                style: MgType.body.copyWith(fontWeight: FontWeight.w500, color: MgColors.body2, height: 1.6),
              ),
            ),
            if (desc.length > 160)
              MgBtnText(
                label: tr.tr(_desc ? 'v2ShowLess' : 'v2ShowMore'),
                icon: _desc ? MgIcons.chevronUp : MgIcons.chevronDown,
                onTap: () => setState(() => _desc = !_desc),
              ),
          ]),
        ),
      if (m.videos.isNotEmpty)
        DetailSectionV2(
          title: tr.tr('v2DetVideo'),
          icon: MgIcons.play,
          child: MotoVideoPlayer(key: ValueKey('motovid-${m.id}'), urls: m.videos),
        ),
      DetailSectionV2(
        title: tr.tr('v2DetMore'),
        icon: MgIcons.moto,
        child: DetailCardV2(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (specs.isNotEmpty) ...[
              _toggleRow(tr.tr('v2DetAllParams'), MgIcons.gear, _params, () => setState(() => _params = !_params)),
              if (_params) Padding(padding: const EdgeInsets.only(bottom: 12), child: DetailAllParamsV2(specs: specs)),
            ],
            if (m.prices != null) ...[
              _toggleRow(tr.tr('v2DetPriceByDay'), MgIcons.receipt, _prices, () => setState(() => _prices = !_prices)),
              if (_prices) Padding(padding: const EdgeInsets.only(bottom: 12), child: DetailPriceTableV2(prices: m.prices!)),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ManualCard(moto: m),
            ),
            if (widget.branchInfo.isNotEmpty)
              MgRow(icon: MgIcons.pin, title: tr.tr('branchPrefix'), sub: widget.branchInfo),
          ]),
        ),
      ),
    ]);
  }

  Widget _toggleRow(String title, String icon, bool open, VoidCallback onTap) => Semantics(
        expanded: open,
        child: MgRow(
          icon: icon,
          title: title,
          divider: !open,
          onTap: onTap,
          trailing: AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: MgMotion.of(context, MgMotion.color),
            child: MgIcon(MgIcons.chevronDown, size: 20, color: MgColors.meta),
          ),
        ),
      );
}
