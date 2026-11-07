import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'res_fit_v2.dart';

/// One action tile of the detail (Reservation board `.at`): icon, label and
/// the EXISTING action it runs. [destructive] = the red storno tile.
class ResActionTile {
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  const ResActionTile(this.icon, this.label, this.onTap, {this.destructive = false});
}

/// Action tiles under CO TEĎ (Reservation board): up to four equal white
/// tiles (min-h 72, r16, 36 px icon tile, label 12.5/800). They sit in one
/// row when every label fits its tile in whole words at ≥ 85 %, else in a
/// 2 × 2 grid (de / fr at 320 dp) — never a word broken in half. Every tile
/// calls an action the detail already has (edit route, navigation, scroll
/// to a section, storno dialog, book again, final invoice).
class ResActionTilesV2 extends StatelessWidget {
  final List<ResActionTile> tiles;
  const ResActionTilesV2({super.key, required this.tiles});

  static final labelStyle = MgType.small.copyWith(fontWeight: FontWeight.w800, height: 1.2);

  /// Horizontal padding + border of a tile around its label.
  static const _chrome = 2 * 6 + 2.0;
  static const _gap = 8.0;
  static const _minScale = 0.85;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final n = tiles.length;
      final w = (c.maxWidth - _gap * (n - 1)) / n - _chrome;
      final oneRow =
          !c.maxWidth.isFinite || tiles.every((x) => resWordsFit(context, x.label, labelStyle, w, minScale: _minScale));
      Widget cell(int i) => _Tile(key: ValueKey('res-tile-$i'), tile: tiles[i]);
      if (oneRow) {
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < n; i++) ...[if (i > 0) const SizedBox(width: _gap), Expanded(child: cell(i))],
          ]),
        );
      }
      // 2 × 2 (3 tiles: 2 + 1 přes celou šířku), dlaždice v řádku stejně vysoké.
      final rows = <Widget>[];
      for (var i = 0; i < n; i += 2) {
        if (i > 0) rows.add(const SizedBox(height: _gap));
        rows.add(IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: cell(i)),
            if (i + 1 < n) ...[const SizedBox(width: _gap), Expanded(child: cell(i + 1))],
          ]),
        ));
      }
      return Column(key: const ValueKey('res-tiles-grid'), crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    });
  }
}

class _Tile extends StatelessWidget {
  final ResActionTile tile;
  const _Tile({super.key, required this.tile});

  @override
  Widget build(BuildContext context) {
    final red = tile.destructive;
    return Semantics(
      button: true,
      label: tile.label,
      excludeSemantics: true,
      child: MgPress(
        onTap: tile.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MgColors.line),
            boxShadow: MgShadows.card,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: red ? MgColors.errBg : MgColors.well,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: red ? MgColors.errBorder : MgColors.line),
              ),
              child: Center(child: MgIcon(tile.icon, size: 20, color: red ? MgColors.err : MgColors.link)),
            ),
            const SizedBox(height: 6),
            MgWordFit(
              minScale: ResActionTilesV2._minScale,
              alignment: Alignment.center,
              child: Text(tile.label,
                  textAlign: TextAlign.center,
                  style: ResActionTilesV2.labelStyle.copyWith(color: red ? MgColors.err : MgColors.ink)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Icons of the board's tiles.
abstract final class ResTileIcons {
  static const edit = MgIcons.edit;
  static const navigate = MgIcons.navigate;
  static const docs = MgIcons.doc;
  static const cancel = MgIcons.close;
  static const rate = MgIcons.star;
  static const again = MgIcons.again;
  static const invoice = MgIcons.receipt;
  static const rides = MgIcons.route;
}

/// Scrolls [key]'s section into view over `MgMotion.sheet` (the "Dokumenty"
/// / "Hodnotit" / "Jízdy" tiles) — reduced motion jumps.
void resRevealSection(BuildContext context, GlobalKey key, Duration duration, Curve curve) {
  final c = key.currentContext;
  if (c == null) return;
  Scrollable.ensureVisible(c, alignment: 0.05, duration: duration, curve: curve);
}
