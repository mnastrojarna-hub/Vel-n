// verify:render cases — v5.0.1 shared pieces: the motorcycle glyph in its
// real surroundings (menu, tiles, placeholders), the neon bottom menu on
// every tab, the branch chip on a bike photo.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/core/v2/widgets/mg_branch_chip.dart';
import 'package:motogo_app/core/v2/widgets/mg_icon_tile.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';

import 'render_harness.dart';

/// Material icons from the Flutter SDK cache (the test font draws boxes) —
/// the motorcycle and the active menu icons are font glyphs.
Future<void> loadMaterialIconsFont() async {
  try {
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final f = File('${artifacts.path}/material_fonts/MaterialIcons-Regular.otf');
    if (!f.existsSync()) return;
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer))))
        .load();
  } catch (_) {}
}

Widget _row(List<Widget> c) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.center, children: c),
    );

/// The motorcycle next to its line-icon neighbours at the sizes in use.
Widget _iconSheet() => ListView(padding: const EdgeInsets.all(12), children: [
      for (final px in [15.0, 20.0, 24.0])
        _row([
          for (final n in [MgIcons.home, MgIcons.moto, MgIcons.calendarCheck, MgIcons.route, MgIcons.bike, MgIcons.helmet])
            Container(color: const Color(0x14000000), child: MgIcon(n, size: px, color: MgColors.ink)),
        ]),
      _row(const [
        MgIconTileLight(MgIcons.moto),
        MgIconTileLight(MgIcons.calc),
        MgIconTileDark(MgIcons.moto, size: 36),
        MgIconTileDark(MgIcons.bike, size: 44),
        MgIconTileDark(MgIcons.route, size: 36),
      ]),
      Container(
        height: 130,
        margin: const EdgeInsets.only(top: 8),
        decoration: const BoxDecoration(
          gradient: RadialGradient(colors: [Color(0xFF14402A), MgColors.night], radius: 0.9),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          MgIcon(MgIcons.moto, size: 44, color: MgColors.neonA(0.33)),
          MgIcon(MgIcons.moto, size: 56, color: MgColors.neonA(0.33)),
          MgIcon(MgIcons.moto, size: 64, color: MgColors.white(0.4)),
        ]),
      ),
    ]);

/// The bottom menu with each tab active (dot on Rezervace, badge on Profil).
Widget _navSheet() => ColoredBox(
      color: MgColors.canvas,
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: V2NavBar(activeIndex: i, onTap: (_) {}, bookingsNeedAction: true, profileBadge: i == 4 ? 12 : 3),
          ),
      ]),
    );

/// A 220 px "photo" ([bright] sky / dark night) with the top-left pills
/// the chip must leave room for and the chip top-right.
Widget _photo(BuildContext context, Motorcycle m, bool bright) => LayoutBuilder(builder: (context, c) {
      final label = mgBikeBranchChipLabel(t(context), m) ?? '';
      return Container(
        height: 200,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: bright
                ? const [Color(0xFFF2F7FF), Color(0xFFFFF3C4), Color(0xFF9CC7E8)]
                : const [Color(0xFF1C2A22), MgColors.night],
          ),
        ),
        child: Stack(children: [
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: MgColors.nightA(0.8), borderRadius: BorderRadius.circular(999)),
              child: Text('1 / 4', style: TextStyle(color: MgColors.onDark, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: MgBranchChip(
              label: label,
              shortLabel: mgBranchShortName(m.branchName, m.branchCity),
              maxWidth: mgBranchChipMaxWidth(c.maxWidth),
            ),
          ),
        ]),
      );
    });

/// Full-width photos, as on the Home / Motorky cards.
Widget _chipSheet() => Builder(
      builder: (context) => ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
        for (final m in const [
          Motorcycle(id: 'a', model: 'A', branchName: 'MotoGo24 Mezná', branchType: 'obslužná'),
          Motorcycle(id: 'b', model: 'B', branchName: 'MotoGo24 Velké Němčice', branchType: 'samoobslužná'),
        ]) ...[
          _photo(context, m, true),
          _photo(context, m, false),
        ],
      ]),
    );

List<RenderCase> v501CoreCases() => [
      RenderCase('v501', 'icons', 'moto_glyph', _iconSheet, () => const [], level: 1),
      RenderCase('v501', 'nav', 'tabs_l1', _navSheet, () => const [], level: 1),
      RenderCase('v501', 'nav', 'tabs_l12', _navSheet, () => const [], level: 12),
      // Green ranks: the ring + arc keep their night disc on the neon pill.
      RenderCase('v501', 'nav', 'tabs_l3', _navSheet, () => const [], level: 3),
      RenderCase('v501', 'nav', 'tabs_l4', _navSheet, () => const [], level: 4),
      RenderCase('v501', 'branch_chip', 'photos', _chipSheet, () => const []),
    ];
