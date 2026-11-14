import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_row.dart';
import '../../moto_model.dart';
import '../../widgets/manual_card.dart';
import 'detail_specs_v2.dart';
import 'detail_trip_card_v2.dart';
import '../catalog_text.dart';

/// Light sections above "Tvoje jízda", in the OLD detail's order and all
/// open as there (owner 2026-11-07 "jen upgrade vzhledu"): branch
/// ("Pobočka: {name}, {city}" + type
/// and street address), the FULL localized plain description, all
/// parameters (old `SpecsSection` data) and the day price list (old
/// `PricingTable` data). The videos play in the photo hero (owner v5.0.1,
/// `DetailHeroV2`), so the old "Video" section is gone here — no second
/// player, no double download. The manual follows the trip card
/// ([DetailManualSectionV2]), as the old `ManualCard` followed the calendar.
class DetailMoreV2 extends StatelessWidget {
  final Motorcycle moto;
  final String branchInfo;
  const DetailMoreV2({super.key, required this.moto, required this.branchInfo});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final m = moto;
    final desc = m.descriptionPlainFor(tr.lang);
    final specs = m.specList(tr.tr);
    final branch = catBranchLineCity(tr, m) ?? branchInfo;
    final b = detailBranchRow(tr, m, branch);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (branch.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: DetailCardV2(
            child: MgRow(
              key: const ValueKey('det-branch'),
              icon: MgIcons.pin,
              title: '${tr.tr('detailBranchLabel')}${b.title}',
              sub: b.sub,
              divider: false,
            ),
          ),
        ),
      if (desc != null)
        DetailSectionV2(
          title: tr.tr('v2DetDescription'),
          icon: MgIcons.doc,
          child: Text(
            desc,
            key: const ValueKey('det-desc'),
            style: MgType.body.copyWith(fontWeight: FontWeight.w500, color: MgColors.body2, height: 1.6),
          ),
        ),
      if (specs.isNotEmpty)
        DetailSectionV2(
          title: tr.tr('v2DetAllParams'),
          icon: MgIcons.gear,
          child: DetailAllParamsV2(specs: specs),
        ),
      if (m.prices != null)
        DetailSectionV2(
          title: tr.tr('v2DetPriceByDay'),
          icon: MgIcons.receipt,
          child: DetailPriceTableV2(prices: m.prices!),
        ),
    ]);
  }
}

/// The manual (`ManualCard`, v2 look) under the trip card — the old order.
class DetailManualSectionV2 extends StatelessWidget {
  final Motorcycle moto;
  const DetailManualSectionV2({super.key, required this.moto});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: ManualCard(moto: moto),
      );
}

/// "Pobočka" row text: the branch name in the title, then its city, type
/// and street address under it (the old "{name}, {city} · type" + address,
/// all kept) — a long city ("Brno - Velké Němčice") is never cut by the
/// title's two lines.
({String title, String? sub}) detailBranchRow(AppTranslations tr, Motorcycle m, String fallback) {
  final name = (m.branchName ?? '').trim();
  final city = (m.branchCity ?? '').trim();
  final addr = (m.branchAddress ?? '').trim();
  if (name.isEmpty) return (title: fallback, sub: addr.isEmpty ? null : catBranchAddress(m));
  final type = catBranchType(tr, m);
  final lines = [
    if (city.isNotEmpty && !name.contains(city)) city,
    if (type != null) type,
    // Street address (the city is already named).
    if (addr.isNotEmpty) addr,
  ];
  return (title: name, sub: lines.isEmpty ? null : lines.join(' · '));
}
