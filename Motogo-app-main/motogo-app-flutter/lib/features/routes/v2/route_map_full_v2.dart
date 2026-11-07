import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_format.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../../core/widgets/map_tile_errors.dart';
import '../route_export.dart';
import '../routes_model.dart';
import 'review_editor_v2.dart' show rtSheetScrimV2;
import 'rt_sheet_v2.dart';
import 'rt_v2_text.dart';

/// "Zobrazit na mapě" in the v2 look (board TrasaDetail "mapa na celou
/// obrazovku"): the EXISTING route map full screen under a night gradient
/// head — ✕ 44 (viewer = close, V22 §6.2) + route name 17/800 + "40 km ·
/// 5 míst". [onClose] = the old pop.
class RouteFullMapV2 extends StatelessWidget {
  final Widget map;
  final String title;
  final String? sub;
  final VoidCallback onClose;
  const RouteFullMapV2({super.key, required this.map, required this.title, this.sub, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return MgStatusBar(
      dark: true,
      child: Material(
        color: MgColors.canvas,
        child: Stack(children: [
          // Map tiles failing: the strip goes under the header (1–2 lines).
          Positioned.fill(child: MapTileErrorInset(child: map)),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
              padding: EdgeInsets.fromLTRB(16, top + 8, 16, 28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [MgColors.night, MgColors.nightA(0.92), MgColors.nightA(0)],
                  stops: const [0, 0.62, 1],
                ),
              ),
              child: Row(children: [
                MgV2Back(onTap: onClose, close: true, style: MgBackStyle.dark),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Semantics(
                      header: true,
                      child: MgWordFit(
                        minScale: 0.85,
                        child: Text(title, maxLines: 2, style: MgType.section.copyWith(color: MgColors.onDark)),
                      ),
                    ),
                    if (sub != null) Text(sub!, style: MgType.tab(MgType.meta.copyWith(color: MgColors.onDarkMeta))),
                  ]),
                ),
              ]),
              ),
              const MapTileErrorStripV2(padding: EdgeInsets.symmetric(horizontal: 16)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// One external-navigation target (Mapy.com / Google Maps / Apple Maps).
class RtExportTargetV2 {
  final String label;
  final String icon;
  final bool dark;
  final VoidCallback onTap;
  const RtExportTargetV2(this.label, this.icon, this.onTap, {this.dark = false});
}

/// "Otevřít v jiné aplikaci" (board TrasaDetail): light sheet, route line
/// "5 míst · Okruh · 40 km", well rows with a 44 icon tile, name + what is
/// sent ("6 bodů"), ↗; or the T3 note when the route has < 2 points
/// (`routeNoNavData`, Stavy 16.28) instead of a snack.
class RouteExportSheetV2 extends StatelessWidget {
  final String? sub;
  final String? rowSub;
  final List<RtExportTargetV2> targets;
  final String? error;
  const RouteExportSheetV2({super.key, this.sub, this.rowSub, required this.targets, this.error});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return RtSheetV2(
      title: tr.tr('routeNavExternal'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (sub != null) ...[Text(sub!, style: MgType.tab(MgType.small.copyWith(color: MgColors.meta))), const SizedBox(height: 14)],
        if (error != null) MgStateBanner(tone: MgTone.warn, title: error!),
        for (final tg in targets) _Row(target: tg, sub: rowSub),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final RtExportTargetV2 target;
  final String? sub;
  const _Row({required this.target, this.sub});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: MgSpace.s12),
        child: Semantics(
          button: true,
          label: target.label,
          excludeSemantics: true,
          child: MgPress(
            onTap: () {
              Navigator.of(context).pop();
              target.onTap();
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 68),
              padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
              decoration: BoxDecoration(
                color: MgColors.well,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MgColors.line),
              ),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: target.dark ? MgColors.panel : MgColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: target.dark ? null : Border.all(color: MgColors.line),
                  ),
                  alignment: Alignment.center,
                  child: MgIcon(target.icon, size: 22, color: target.dark ? MgColors.neon : MgColors.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(target.label, style: MgType.title.copyWith(color: MgColors.ink)),
                    if (sub != null) Text(sub!, style: MgType.tab(MgType.small.copyWith(color: MgColors.meta))),
                  ]),
                ),
                const SizedBox(width: 8),
                const MgIcon(MgIcons.external, size: 20, color: MgColors.ink),
              ]),
            ),
          ),
        ),
      );
}

/// Opens [RouteExportSheetV2] (light sheet, v2 scrim and motion).
Future<void> rtShowExportSheetV2(BuildContext context,
        {String? sub, String? rowSub, required List<RtExportTargetV2> targets, String? error}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: rtSheetScrimV2,
      sheetAnimationStyle: MgMotion.sheetStyle(context),
      builder: (_) => RouteExportSheetV2(sub: sub, rowSub: rowSub, targets: targets, error: error),
    );

/// "5 míst · Okruh · 40 km" (existing data only).
String rtRouteLine(AppTranslations tr, RouteItem r, double? realKm) {
  final km = realKm ?? r.distanceKm;
  return [
    if (r.pois.isNotEmpty) rtPlural(tr, 'v2RtPlaces', r.pois.length),
    tr.tr(r.isLoop ? 'routeTypeLoop' : 'routeTypePoi'),
    if (km != null) '${mgNum(km, tr.lang)}\u00A0km',
  ].join(' · ');
}

/// What is sent: "Okruh od bodu nejblíž tobě · 6 bodů".
String rtExportRowSub(AppTranslations tr, bool loopFromMe, int points) =>
    [if (loopFromMe) tr.tr('v2UxRrLoopNearest'), rtPlural(tr, 'v2UxRrPoints', points)].join(' · ');

String rtExportIcon(RouteExportTarget t) => switch (t) {
      RouteExportTarget.mapy => MgIcons.map,
      RouteExportTarget.googleMaps => MgIcons.pin,
      RouteExportTarget.appleMaps => MgIcons.globe,
    };
