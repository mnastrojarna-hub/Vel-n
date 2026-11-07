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
    final retryStyle = MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.neon);
    final disc = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: MgColors.white(0.10), shape: BoxShape.circle),
      child: const Center(child: MgIcon(MgIcons.wifiOff, size: 16, color: MgColors.onDark)),
    );
    final text = Semantics(
      liveRegion: true,
      child: Text(tr.tr('eoMapTilesFail'), style: MgType.meta.copyWith(color: MgColors.onDark)),
    );
    Widget link(EdgeInsets pad) => Semantics(
          button: true,
          label: retry,
          excludeSemantics: true,
          child: MgPress(
            key: const ValueKey('map-tiles-retry-v2'),
            onTap: onRetry,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              child: Padding(
                padding: pad,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(retry, maxLines: 1, softWrap: false, style: retryStyle),
                ),
              ),
            ),
          ),
        );
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(builder: (context, c) {
        // A narrow strip (map card, 320 dp) puts the link under the text,
        // so no word is ever split.
        final tp = TextPainter(
          text: TextSpan(text: retry, style: retryStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final stacked = c.maxWidth - 46 - (tp.width + 24) < 180;
        tp.dispose();
        return Container(
          key: const ValueKey('map-tiles-strip-v2'),
          padding: EdgeInsets.fromLTRB(10, stacked ? 8 : 0, stacked ? 12 : 0, 0),
          decoration: BoxDecoration(
            // Solid like the status strips: a translucent fill let the shadow
            // and the map ghost through.
            color: MgColors.night,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MgColors.white(0.10)),
            boxShadow: MgShadows.dark,
          ),
          child: stacked
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  disc,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(padding: const EdgeInsets.only(top: 5), child: text),
                      link(const EdgeInsets.only(right: 12)),
                    ]),
                  ),
                ])
              : Row(children: [
                  disc,
                  const SizedBox(width: 8),
                  Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: text)),
                  link(const EdgeInsets.symmetric(horizontal: 12)),
                ]),
        );
      }),
    );
  }
}
