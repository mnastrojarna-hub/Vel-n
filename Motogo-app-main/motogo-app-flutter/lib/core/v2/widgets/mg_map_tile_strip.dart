import 'package:flutter/material.dart';

import '../../i18n/i18n_provider.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_type.dart';

/// Map tiles do not load (offline / key quota / 403) — the v2 face of the
/// old `MapTileErrorChip` (V22 §5.2 T4 strip, the look of the offline
/// strip): night glass r14, the wifi-off disc, the same text and the same
/// ONE action "Zkusit znovu" ([onRetry] = `MapTileErrors.retry`). Placed
/// under the screen's header / HUD, never under it.
class MgMapTileStrip extends StatelessWidget {
  final VoidCallback onRetry;
  const MgMapTileStrip({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final retry = tr.tr('eoRetry');
    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const ValueKey('map-tiles-strip-v2'),
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          color: MgColors.nightA(0.94),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MgColors.white(0.10)),
          boxShadow: MgShadows.dark,
        ),
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: MgColors.white(0.10), shape: BoxShape.circle),
            child: const Center(child: MgIcon(MgIcons.wifiOff, size: 16, color: MgColors.onDark)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(tr.tr('eoMapTilesFail'), style: MgType.meta.copyWith(color: MgColors.onDark)),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: retry,
            excludeSemantics: true,
            child: MgPress(
              key: const ValueKey('map-tiles-retry-v2'),
              onTap: onRetry,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    widthFactor: 1,
                    child: Text(retry,
                        maxLines: 1,
                        softWrap: false,
                        style: MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.neon)),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
