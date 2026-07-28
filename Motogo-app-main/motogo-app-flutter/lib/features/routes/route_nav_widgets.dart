import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import 'my_experiences_provider.dart' show VisitResult;

/// Widgety navigační obrazovky — HUD, kompas, markery, karta dojezdu na bod,
/// karta dokončení trasy a sheet se zastávkami trasy.

String formatNavDist(double m) =>
    m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

/// Kompas — ukazuje sever; klik vrátí mapu na sever.
class NavCompassButton extends StatelessWidget {
  final double rotationDeg;
  final VoidCallback onTap;
  const NavCompassButton({super.key, required this.rotationDeg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: MotoGoShadows.cardSmall,
        ),
        child: Transform.rotate(
          angle: rotationDeg * math.pi / 180,
          child: const Icon(Icons.navigation, size: 22, color: Color(0xFFD93636)),
        ),
      ),
    );
  }
}

/// Pilulka „příští zastávka" + vzdálenost + pořadí (klik = seznam zastávek).
class NavNextStopPill extends StatelessWidget {
  final String name;
  final double? distanceM;
  final String? progress; // např. „3/8"
  final VoidCallback? onTap;
  const NavNextStopPill({
    super.key,
    required this.name,
    this.distanceM,
    this.progress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = distanceM == null ? null : formatNavDist(distanceM!);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoRadius.pill),
          boxShadow: MotoGoShadows.cardSmall,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.place, size: 15, color: MotoGoColors.greenDark),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '${t(context).tr('routeNavNext')}: $name${d == null ? '' : ' · $d'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: MotoGoTypo.sizeMd,
                    fontWeight: MotoGoTypo.w700,
                    color: MotoGoColors.black,
                    decoration: TextDecoration.none),
              ),
            ),
            if (progress != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: MotoGoColors.greenPale,
                  borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                ),
                child: Text(
                  progress!,
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeSm,
                      fontWeight: MotoGoTypo.w800,
                      color: MotoGoColors.greenDarker,
                      decoration: TextDecoration.none),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Spodní HUD navigace — velký tachometr + zbývá / čas / příjezd / výška + progress.
class NavHud extends StatelessWidget {
  final double? remainingM;
  final double speedKmh;
  final double? altitude;
  final double fraction;
  /// ETA v minutách z routingu (přesnější než odhad z rychlosti); null = odhad.
  final double? etaMinutes;
  const NavHud({
    super.key,
    required this.remainingM,
    required this.speedKmh,
    required this.altitude,
    required this.fraction,
    this.etaMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final arrived = remainingM != null && remainingM! < 40;
    final remTxt = remainingM == null ? '–' : formatNavDist(remainingM!);
    // ETA: preferuj čas z routing API (škálovaný na zbytek trasy), jinak
    // odhad z aktuální rychlosti (min. 50 km/h — vedlejší silnice).
    String etaTxt = '–';
    String arrTxt = '–';
    if (remainingM != null) {
      int mins;
      if (etaMinutes != null && etaMinutes!.isFinite && etaMinutes! >= 0) {
        mins = etaMinutes!.round();
      } else {
        final mPerS = speedKmh > 8 ? speedKmh / 3.6 : 50 / 3.6;
        mins = (remainingM! / mPerS / 60).round();
      }
      etaTxt = mins < 1 ? '<1 min' : (mins >= 60 ? '${mins ~/ 60} h ${mins % 60} min' : '$mins min');
      final arr = DateTime.now().add(Duration(minutes: mins));
      arrTxt = '${arr.hour.toString().padLeft(2, '0')}:${arr.minute.toString().padLeft(2, '0')}';
    }
    final altTxt = altitude == null ? '–' : '${altitude!.round()} m';

    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.of(context).padding.bottom + 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: MotoGoShadows.cardSmall,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 5,
              backgroundColor: MotoGoColors.g200,
              valueColor: const AlwaysStoppedAnimation(MotoGoColors.greenDark),
            ),
          ),
          const SizedBox(height: 12),
          arrived
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    t(context).tr('routeNavArrived'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeH3,
                        fontWeight: MotoGoTypo.w900,
                        color: MotoGoColors.greenDarker,
                        decoration: TextDecoration.none),
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _speedBlock(),
                    Container(width: 1, height: 56, color: MotoGoColors.g200),
                    Expanded(
                      child: Column(
                        children: [
                          Row(children: [
                            _stat(Icons.flag_outlined, remTxt, t(context).tr('routeNavRemaining')),
                            _stat(Icons.schedule, etaTxt, t(context).tr('routeNavEta')),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            _stat(Icons.access_time_filled, arrTxt, t(context).tr('routeNavArrival')),
                            _stat(Icons.terrain, altTxt, t(context).tr('routeNavAltitude')),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _speedBlock() => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${speedKmh.round()}',
              style: const TextStyle(
                  fontSize: 34,
                  height: 1.0,
                  fontWeight: MotoGoTypo.w900,
                  color: MotoGoColors.black,
                  decoration: TextDecoration.none),
            ),
            const Text(
              'km/h',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: MotoGoTypo.w700,
                  color: MotoGoColors.g500,
                  decoration: TextDecoration.none),
            ),
          ],
        ),
      );

  Widget _stat(IconData icon, String value, String label) => Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: MotoGoColors.greenDark),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeLg,
                        fontWeight: MotoGoTypo.w900,
                        color: MotoGoColors.black,
                        decoration: TextDecoration.none),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: MotoGoTypo.w600,
                  color: MotoGoColors.g500,
                  decoration: TextDecoration.none),
            ),
          ],
        ),
      );
}

/// Modrý marker aktuální polohy se šipkou směru jízdy.
class NavMeMarker extends StatelessWidget {
  final double? arrowDeg; // směr šipky na obrazovce (stupně, po směru hod. ručiček)
  const NavMeMarker({super.key, this.arrowDeg});

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.5), blurRadius: 8)],
      ),
    );
    if (arrowDeg == null) return dot;
    return Transform.rotate(
      angle: arrowDeg! * math.pi / 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned(top: 0, child: Icon(Icons.navigation, size: 16, color: Color(0xFF2563EB))),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.5), blurRadius: 8)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Číslovaný pin bodu zájmu (zaškrtnutý = navštívený).
class NavNumPin extends StatelessWidget {
  final int index;
  final bool visited;
  const NavNumPin({super.key, required this.index, this.visited = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: visited ? MotoGoColors.g400 : MotoGoColors.greenDarker,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: visited
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : Text('${index + 1}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    decoration: TextDecoration.none)),
      ),
    );
  }
}

/// Karta „dojel jsi na bod" — objevení místa + tlačítko na další bod trasy.
class StopReachedCard extends StatelessWidget {
  final String name;
  final VisitResult? visit; // null = nepřihlášen / ještě se ukládá
  final String? nextLabel; // null = tohle byl poslední bod
  final VoidCallback onNext;
  final VoidCallback onChoose;
  final VoidCallback onClose;
  final VoidCallback? onRate; // hodnocení + komentář dosaženého bodu zájmu
  const StopReachedCard({
    super.key,
    required this.name,
    this.visit,
    this.nextLabel,
    required this.onNext,
    required this.onChoose,
    required this.onClose,
    this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: MotoGoShadows.motoCard,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🎉', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(context).tr('navStopReached'),
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeMd,
                          fontWeight: MotoGoTypo.w600,
                          color: MotoGoColors.g500,
                          decoration: TextDecoration.none),
                    ),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeXl,
                          fontWeight: MotoGoTypo.w900,
                          color: MotoGoColors.black,
                          decoration: TextDecoration.none),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, size: 20, color: MotoGoColors.g400),
                ),
              ),
            ],
          ),
          if (visit != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: MotoGoColors.greenPale,
                borderRadius: BorderRadius.circular(MotoGoRadius.pill),
              ),
              child: Text(
                visit!.firstVisit
                    ? '✨ ${t(context).tr('navPlaceDiscovered')} · ${t(context).tr('navPlacesTotal').replaceFirst('{n}', '${visit!.totalPlaces}')}'
                    : '✅ ${t(context).tr('navVisited')}',
                style: const TextStyle(
                    fontSize: MotoGoTypo.sizeMd,
                    fontWeight: MotoGoTypo.w800,
                    color: MotoGoColors.greenDarker,
                    decoration: TextDecoration.none),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  // Vždy [onNext] = RUČNÍ potvrzení dojezdu — bod se odškrtne
                  // až tímto tlačítkem (i u posledního bodu trasy).
                  onTap: onNext,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: MotoGoColors.green,
                      borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.navigation, size: 17, color: MotoGoColors.black),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            nextLabel != null
                                ? t(context).tr('navNextStopBtn').replaceFirst('{name}', nextLabel!)
                                : t(context).tr('routeNavArrived'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: MotoGoTypo.sizeLg,
                                fontWeight: MotoGoTypo.w800,
                                color: MotoGoColors.black,
                                decoration: TextDecoration.none),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (onRate != null) ...[
                const SizedBox(width: 8),
                // Ohodnotit dosažený bod (hvězdy + komentář v detailu bodu).
                GestureDetector(
                  onTap: onRate,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: MotoGoColors.greenPale,
                      borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                      border: Border.all(color: MotoGoColors.green, width: 1.3),
                    ),
                    child: const Icon(Icons.star, size: 20, color: Color(0xFFF5B301)),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onChoose,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: MotoGoColors.greenPale,
                    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                    border: Border.all(color: MotoGoColors.green, width: 1.3),
                  ),
                  child: const Icon(Icons.checklist, size: 20, color: MotoGoColors.greenDarker),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Karta „trasa dokončena" — hodnocení trasy / uložení vlastní vyjížďky.
class RouteDoneCard extends StatelessWidget {
  final bool canRate; // trasa z DB → nabídni recenzi
  final bool canSave; // vlastní vyjížďka → nabídni uložení do Mých tras
  final VoidCallback onRate;
  final VoidCallback onSave;
  final VoidCallback onClose;
  const RouteDoneCard({
    super.key,
    required this.canRate,
    required this.canSave,
    required this.onRate,
    required this.onSave,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData ic, String label, VoidCallback onTap, {bool primary = false}) =>
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: primary ? MotoGoColors.green : MotoGoColors.greenPale,
                borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                border: primary ? null : Border.all(color: MotoGoColors.green, width: 1.3),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(ic, size: 17,
                      color: primary ? MotoGoColors.black : MotoGoColors.greenDarker),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: MotoGoTypo.sizeLg,
                          fontWeight: MotoGoTypo.w800,
                          color: primary ? MotoGoColors.black : MotoGoColors.greenDarker,
                          decoration: TextDecoration.none),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: MotoGoShadows.motoCard,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏁', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t(context).tr('navRouteDone'),
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeXl,
                      fontWeight: MotoGoTypo.w900,
                      color: MotoGoColors.black,
                      decoration: TextDecoration.none),
                ),
              ),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, size: 20, color: MotoGoColors.g400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (canRate) btn(Icons.star, t(context).tr('navRateRoute'), onRate, primary: true),
              if (canRate && canSave) const SizedBox(width: 8),
              if (canSave) btn(Icons.bookmark_add, t(context).tr('navSaveRoute'), onSave, primary: !canRate),
            ],
          ),
        ],
      ),
    );
  }
}

/// Náhled zastávky pro sheet se zastávkami trasy.
class NavStopView {
  final int index;
  final String label;
  final bool reached;
  final bool isNext;
  final bool hasPoi;
  const NavStopView({
    required this.index,
    required this.label,
    required this.reached,
    required this.isNext,
    required this.hasPoi,
  });
}

/// Sheet se zastávkami trasy — odškrtnuté projeté, klepnutí na budoucí bod
/// = navigovat rovnou na něj (dřívější nedojeté body se přeskočí).
void showNavStopsSheet(
  BuildContext context, {
  required List<NavStopView> stops,
  required void Function(int index) onNavigateTo,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sc) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(sc).size.height * 0.72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: MotoGoColors.g200, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t(sc).tr('navStopsTitle'),
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeH2,
                          fontWeight: MotoGoTypo.w900,
                          color: MotoGoColors.black,
                          decoration: TextDecoration.none),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  t(sc).tr('navStopsSkipHint'),
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeMd,
                      fontWeight: MotoGoTypo.w600,
                      color: MotoGoColors.g500,
                      decoration: TextDecoration.none),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                itemCount: stops.length,
                itemBuilder: (c, i) {
                  final s = stops[i];
                  return ListTile(
                    dense: true,
                    leading: SizedBox(
                      width: 30,
                      height: 30,
                      child: NavNumPin(index: s.index, visited: s.reached),
                    ),
                    title: Text(
                      s.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: MotoGoTypo.sizeLg,
                        fontWeight: s.isNext ? MotoGoTypo.w900 : MotoGoTypo.w700,
                        color: s.reached ? MotoGoColors.g400 : MotoGoColors.black,
                        decoration: s.reached
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                    subtitle: s.isNext
                        ? Text(
                            t(sc).tr('routeNavNext'),
                            style: const TextStyle(
                                fontSize: MotoGoTypo.sizeSm,
                                fontWeight: MotoGoTypo.w700,
                                color: MotoGoColors.greenDark),
                          )
                        : null,
                    trailing: s.reached
                        ? const Icon(Icons.check_circle,
                            size: 20, color: MotoGoColors.greenDark)
                        : TextButton(
                            onPressed: () {
                              Navigator.of(sc).pop();
                              onNavigateTo(s.index);
                            },
                            child: Text(
                              t(sc).tr('navNavigateHere'),
                              style: const TextStyle(
                                  fontSize: MotoGoTypo.sizeMd,
                                  fontWeight: MotoGoTypo.w800,
                                  color: MotoGoColors.greenDarker),
                            ),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
