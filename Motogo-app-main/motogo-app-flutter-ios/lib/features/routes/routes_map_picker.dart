import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/moto_fx.dart';
import 'routes_map_provider.dart' show fmtRideMinutes;
import 'routes_model.dart';
import 'routes_provider.dart' show polylineLengthM;

/// Výška spodního panelu s kartami tras — mapa tras podle ní posouvá kulatá
/// tlačítka a čip „Tvoje trasa", aby je panel nepřekryl.
const double kRoutesMapPickerHeight = 150;

/// Barvy tras na mapě tras — každá trasa vybraného bodu má svou, karta dole
/// nese stejnou, takže je jasné, která čára je která.
const List<Color> kRoutesMapPalette = [
  Color(0xFF1A8A18), // zelená (brand)
  Color(0xFF1D4ED8), // modrá
  Color(0xFFE11D48), // červená
  Color(0xFFD97706), // oranžová
  Color(0xFF7C3AED), // fialová
];

Color routesMapColor(int index) =>
    kRoutesMapPalette[index % kRoutesMapPalette.length];

/// Šířka karty + mezera — podle toho se panel doscrolluje na zvolenou kartu.
const double _kCardW = 250;
const double _kCardGap = 10;

/// Spodní panel mapy tras: jedna karta pro KAŽDOU trasu, která vede přes
/// vybraný bod. Klepnutí na kartu trasu zvýrazní na mapě a přiblíží ji,
/// „Detail" otevře její stránku (navigace, úprava, recenze). Když se trasa
/// zvolí jinde (štítek na čáře, čip „Další trasa"), panel na její kartu
/// doscrolluje.
///
/// Zadání uživatele (2026-10-04): „když vyberu místo, přes které vedou dvě
/// trasy, ukáže mi to jen jednu a nemůžu si vybrat, kterou pojedu — dole
/// to má nabídnout aspoň dva seznamy, když jsou tam dvě možnosti."
class RoutesMapPicker extends StatefulWidget {
  final List<RouteItem> routes;
  final Map<String, RouteBranch> branches;
  final String lang;
  final String? activeId;

  /// Spočtené čáry po silnici podle id trasy (chybí = ještě se počítá,
  /// prázdná = routing selhal). Z čáry se bere REÁLNÁ délka po silnici.
  final Map<String, List<LatLng>> lines;
  final Set<String> computing;
  final void Function(RouteItem route) onPick;
  final void Function(RouteItem route) onOpen;

  const RoutesMapPicker({
    super.key,
    required this.routes,
    required this.branches,
    required this.lang,
    required this.activeId,
    required this.lines,
    required this.computing,
    required this.onPick,
    required this.onOpen,
  });

  @override
  State<RoutesMapPicker> createState() => _RoutesMapPickerState();
}

class _RoutesMapPickerState extends State<RoutesMapPicker> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Panel může vzniknout už se zvolenou trasou (výběr zrušený ✕ a znovu
    // zaškrtnutý v detailu místa drží `_activeId`) — karta musí být vidět
    // hned, bez animace od začátku seznamu.
    _scrollToActive(animate: false);
  }

  @override
  void didUpdateWidget(RoutesMapPicker old) {
    super.didUpdateWidget(old);
    if (widget.activeId != old.activeId) _scrollToActive();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToActive({bool animate = true}) {
    final id = widget.activeId;
    if (id == null) return;
    final i = widget.routes.indexWhere((r) => r.id == id);
    if (i < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = (i * (_kCardW + _kCardGap))
          .clamp(0.0, _scroll.position.maxScrollExtent);
      if (!animate) {
        _scroll.jumpTo(target);
        return;
      }
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final routes = widget.routes;
    return SizedBox(
      height: kRoutesMapPickerHeight,
      child: Container(
        color: MotoGoColors.g100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${t(context).tr('routesMapPickTitle')} · ${routes.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: MotoGoTypo.sizeLg,
                        fontWeight: MotoGoTypo.w900,
                        color: MotoGoColors.black,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  Text(
                    t(context).tr('routesMapPickHint'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: MotoGoTypo.sizeSm,
                      fontWeight: MotoGoTypo.w600,
                      color: MotoGoColors.g500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                itemCount: routes.length,
                separatorBuilder: (_, __) => const SizedBox(width: _kCardGap),
                itemBuilder: (context, i) => _card(context, routes[i], i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, RouteItem r, int i) {
    final color = routesMapColor(i);
    final active = r.id == widget.activeId;
    final line = widget.lines[r.id];
    final busy = widget.computing.contains(r.id);
    final failed = line != null && line.length < 2 && !busy;
    // Reálná délka po silnici ze spočtené čáry; než doběhne, délka z DB.
    final km = (line != null && line.length >= 2)
        ? polylineLengthM(line) / 1000
        : r.distanceKm;
    final branch = r.branchId != null ? widget.branches[r.branchId] : null;
    final meta = <String>[
      if (km != null) '${km.toStringAsFixed(0)} km',
      if (r.durationMin != null) fmtRideMinutes(r.durationMin!),
      if (r.difficulty != null) _difficulty(context, r.difficulty!),
    ];
    return PressableScale(
      pressedScale: 0.97,
      onTap: () => widget.onPick(r),
      child: Container(
        width: _kCardW,
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoRadius.card),
          border: Border.all(
            color: active ? color : MotoGoColors.g200,
            width: active ? 2 : 1,
          ),
          boxShadow: MotoGoShadows.cardSmall,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    r.nameFor(widget.lang),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: MotoGoTypo.sizeLg,
                      fontWeight: MotoGoTypo.w900,
                      color: active ? color : MotoGoColors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    busy
                        ? t(context).tr('routesMapComputing')
                        : failed
                            ? t(context).tr('routesMapLineFailed')
                            : meta.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: MotoGoTypo.sizeMd,
                      fontWeight: MotoGoTypo.w700,
                      color: MotoGoColors.g600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (branch != null)
                    Text(
                      branch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: MotoGoTypo.sizeSm,
                        fontWeight: MotoGoTypo.w600,
                        color: MotoGoColors.g400,
                        decoration: TextDecoration.none,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Vnitřní GestureDetector vyhraje arénu gest nad kartou, takže
            // „Detail" neprovede zároveň i zvýraznění.
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onOpen(r),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: MotoGoColors.greenPale,
                    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                    border: Border.all(color: MotoGoColors.green, width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t(context).tr('routesMapDetail'),
                        style: const TextStyle(
                          fontSize: MotoGoTypo.sizeMd,
                          fontWeight: MotoGoTypo.w800,
                          color: MotoGoColors.greenDarker,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 16, color: MotoGoColors.greenDarker),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _difficulty(BuildContext context, String d) {
    switch (d) {
      case 'easy':
        return t(context).tr('routeDiffEasy');
      case 'medium':
        return t(context).tr('routeDiffMedium');
      case 'hard':
        return t(context).tr('routeDiffHard');
    }
    return d;
  }
}
