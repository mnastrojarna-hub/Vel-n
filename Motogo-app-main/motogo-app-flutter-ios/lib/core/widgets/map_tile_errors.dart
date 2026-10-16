import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../i18n/i18n_provider.dart';
import '../theme.dart';

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
  }

  static void retry() {
    failingSince.value = null;
    _windowStart = null;
    _count = 0;
    _reset.add(null);
  }
}

/// Štítek „Mapové podklady se nenačetly – zkontroluj připojení" + Zkusit znovu.
/// Patří do `FlutterMap.children` (nahoru doprostřed mapy).
class MapTileErrorChip extends StatelessWidget {
  const MapTileErrorChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: MapTileErrors.failingSince,
      builder: (context, since, _) {
        if (since == null) return const SizedBox.shrink();
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
