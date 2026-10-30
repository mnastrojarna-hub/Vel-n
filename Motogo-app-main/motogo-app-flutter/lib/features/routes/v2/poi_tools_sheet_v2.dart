import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import 'rt_sheet_rows_v2.dart';
import 'rt_sheet_v2.dart';

/// v2 look of Místa → "Řadit a filtrovat" (board TrasyHub `sht.tools`):
/// search, sort, categories (line icons instead of emoji), states, the
/// hidden min-rating chips and the pinned "Zobrazit (n)". Working copies,
/// the live count and every callback stay in `all_pois_screen.dart`.
class PoiToolsSheetV2 extends StatelessWidget {
  final TextEditingController query;
  final ValueChanged<String> onQuery;
  final bool hasQuery;
  final VoidCallback onClearQuery;
  final List<RtOpt> sorts;
  final List<RtOpt> cats;
  final List<RtOpt> countriesTop;
  final List<RtOpt> countriesRest;
  final bool moreCountries;
  final VoidCallback onMoreCountries;
  final bool showRating;
  final VoidCallback onRating;
  final List<RtOpt> ratings;
  final int count;
  final VoidCallback onApply;
  final VoidCallback onClear;
  const PoiToolsSheetV2({
    super.key,
    required this.query,
    required this.onQuery,
    required this.hasQuery,
    required this.onClearQuery,
    required this.sorts,
    required this.cats,
    required this.countriesTop,
    required this.countriesRest,
    required this.moreCountries,
    required this.onMoreCountries,
    required this.showRating,
    required this.onRating,
    required this.ratings,
    required this.count,
    required this.onApply,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return RtSheetV2(
      title: tr.tr('poiToolsTitle'),
      clearLabel: tr.tr('routesFilterClear'),
      onClear: onClear,
      footer: MgBtnInk(label: '${tr.tr('poiFilterApply')} ($count)', onTap: onApply),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 4),
        RtSearchV2(
          controller: query,
          hint: tr.tr('poiSearch'),
          onChanged: onQuery,
          showClear: hasQuery,
          onClear: onClearQuery,
        ),
        RtSectionV2(tr.tr('sortTitle')),
        RtChipsV2(sorts),
        RtSectionV2(tr.tr('poiFilterCategory')),
        RtChipsV2(cats),
        if (countriesTop.isNotEmpty || countriesRest.isNotEmpty) ...[
          RtSectionV2(tr.tr('poiFilterCountry')),
          RtCountriesV2(top: countriesTop, rest: countriesRest, open: moreCountries, onMore: onMoreCountries),
        ],
        const SizedBox(height: 12),
        RtExpandLinkV2(label: tr.tr('poiFilterMinRating'), open: showRating, onTap: onRating),
        MgAnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: showRating
              ? Padding(padding: const EdgeInsets.only(top: 4), child: RtChipsV2(ratings))
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

/// v2 look of Místa → "Vyber trasu": search on top, a lazy list ("Všechny
/// trasy" first, then the routes with their place counts) and a clear
/// "nothing found" line. [rowAt] builds the screen's existing rows.
class RoutePickSheetV2 extends StatelessWidget {
  final TextEditingController query;
  final ValueChanged<String> onQuery;
  final int itemCount;
  final ({RtOpt opt, int count}) Function(int i) rowAt;

  /// The search found no route (the query is shown in the note).
  final String? emptyQuery;
  const RoutePickSheetV2({
    super.key,
    required this.query,
    required this.onQuery,
    required this.itemCount,
    required this.rowAt,
    this.emptyQuery,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final empty = emptyQuery != null;
    return RtSheetV2(
      title: tr.tr('poiRoutePickTitle'),
      scroll: false,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: RtSearchV2(
            controller: query,
            hint: tr.tr('poiRouteSearch'),
            onChanged: onQuery,
            showClear: false,
            onClear: () {},
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: itemCount + (empty ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i == itemCount) return _Empty(emptyQuery!);
              final r = rowAt(i);
              return RtPickRowV2(r.opt, r.count);
            },
          ),
        ),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  final String query;
  const _Empty(this.query);

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: MgColors.well,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MgColors.line),
          ),
          child: Row(children: [
            const MgIcon(MgIcons.search, size: 20, color: MgColors.meta),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t(context).tr('routesFilterEmpty'), style: MgType.title.copyWith(color: MgColors.ink)),
                Text(query, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.small.copyWith(color: MgColors.meta)),
              ]),
            ),
          ]),
        ),
      );
}
