import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../i18n/i18n_provider.dart';
import '../theme.dart';
import '../v2/flag/v2_scope.dart';
import '../v2/widgets/mg_map_tile_strip.dart';

/// Mapové podklady (Mapy.com) se nenačítají — offline, vyčerpaný limit
/// klíče / 403. Dřív šedá mapa bez vysvětlení (2026-10-16). Všechny
/// `TileLayer` hlásí chyby sem; [MapTileErrorChip] ukáže důvod a „Zkusit znovu".
class MapTileErrors {
  MapTileErrors._();

  static final ValueNotifier<DateTime?> failingSince = ValueNotifier(null);
  static final StreamController<void> _reset = StreamController<void>.broadcast();

  /// Pro `TileLayer(reset:)` — emitnutí načte dlaždice znovu.
  static final Stream<void> reset = _reset.stream;

  static DateTime? _windowStart;
  static int _count = 0;
  static Timer? _autoRetry;

  /// Pro `TileLayer(errorTileCallback:)`. Jedna vadná dlaždice nic nehlásí,
  /// až 3 chyby za 30 s.
  static void report(TileImage tile, Object error, StackTrace? stackTrace) {
    final now = DateTime.now();
    final start = _windowStart;
    if (start == null || now.difference(start) > const Duration(seconds: 30)) {
      _windowStart = now;
      _count = 0;
    }
    _count++;
    if (_count >= 3 && failingSince.value == null) failingSince.value = now;
    if (failingSince.value != null) {
      // Spojení se mohlo vrátit (i bez změny sítě) — 30 s po poslední chybě
      // podklady tiše zkusit znovu: štítek zmizí, a když chyba trvá, vrátí se.
      _autoRetry?.cancel();
      _autoRetry = Timer(const Duration(seconds: 30), retry);
    }
  }

  static void retry() {
    _autoRetry?.cancel();
    _autoRetry = null;
    failingSince.value = null;
    _windowStart = null;
    _count = 0;
    _reset.add(null);
  }
}

/// v2: wraps a map whose top the screen's chrome covers (header, HUD, back
/// button, expand disc). [top] = the tile strip is drawn over the map
/// [top] px from its top (above markers and lines); null = the screen's
/// chrome shows [MapTileErrorStripV2] itself (under a header of varying
/// height). Either way the [MapTileErrorChip] inside the map stays out.
/// Without one (a map in a card) the chip shows the strip at the map's top.
/// Flag off: no change — the old chip keeps its place.
class MapTileErrorInset extends StatelessWidget {
  final double? top;
  final Widget child;
  const MapTileErrorInset({super.key, this.top, required this.child});

  static bool placed(BuildContext context) => context.getInheritedWidgetOfExactType<_MapTileStripPlaced>() != null;

  @override
  Widget build(BuildContext context) {
    final marked = _MapTileStripPlaced(child: child);
    final t = top;
    if (t == null || !MgV2.on(context)) return marked;
    return Stack(fit: StackFit.expand, children: [
      marked,
      Positioned(top: t, left: 12, right: 12, child: const MapTileErrorStripV2()),
    ]);
  }
}

class _MapTileStripPlaced extends InheritedWidget {
  const _MapTileStripPlaced({required super.child});

  @override
  bool updateShouldNotify(_MapTileStripPlaced oldWidget) => false;
}

/// v2 tile strip placed by a screen's chrome (under its header); nothing
/// while the tiles load. Same text and retry as [MapTileErrorChip].
class MapTileErrorStripV2 extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const MapTileErrorStripV2({super.key, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DateTime?>(
        valueListenable: MapTileErrors.failingSince,
        builder: (context, since, _) => since == null
            ? const SizedBox.shrink()
            : Padding(padding: padding, child: const MgMapTileStrip(onRetry: MapTileErrors.retry)),
      );
}

/// [header] of a full-screen map; in v2 with the tile strip under it.
Widget mapHeaderWithTileStrip(BuildContext context, Widget header) => !MgV2.on(context)
    ? header
    : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        const MapTileErrorStripV2(padding: EdgeInsets.fromLTRB(12, 8, 12, 0)),
      ]);

/// Štítek „Mapové podklady se nenačetly – zkontroluj připojení" + Zkusit znovu.
/// Patří do `FlutterMap.children` (nahoru doprostřed mapy). v2: tmavý pruh
/// (`MgMapTileStrip`) pod hlavičkou obrazovky — viz [MapTileErrorInset].
class MapTileErrorChip extends StatelessWidget {
  const MapTileErrorChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: MapTileErrors.failingSince,
      builder: (context, since, _) {
        if (since == null) return const SizedBox.shrink();
        if (MgV2.on(context)) {
          if (MapTileErrorInset.placed(context)) return const SizedBox.shrink();
          return const Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: MgMapTileStrip(onRetry: MapTileErrors.retry),
            ),
          );
        }
        final tr = t(context);
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 8, left: 56, right: 56),
            child: Material(
              color: MotoGoColors.dark.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(tr.tr('eoMapTilesFail'),
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                  TextButton(
                    onPressed: MapTileErrors.retry,
                    child: Text(tr.tr('eoRetry'),
                        style: const TextStyle(
                            color: MotoGoColors.green, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
