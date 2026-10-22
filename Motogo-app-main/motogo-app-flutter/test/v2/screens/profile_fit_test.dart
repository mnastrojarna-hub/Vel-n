// fix:profile (verify:render r1) — Profil v2 layout guards in all 8
// languages × 320 / 360 / 412 dp × text 1.0 / 1.3 (reduced motion): no
// overflow, no cut / clipped / truncated UI text and no word broken in half
// (render_inspect.dart, the verify:render rules) on a tall surface, so every
// section is laid out and visible. Covers the hub tiles (2 × 3 grid → one
// per row), the rank strip eyebrow, Osobní údaje (summary pairs, the form's
// date dropdowns with values and with empty hints), Moje doklady cards,
// Faktury rows, Dokumenty a smlouvy rows and the Zprávy segments — plus the
// layout switches themselves.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/features/documents/contracts_screen.dart';
import 'package:motogo_app/features/documents/documents_screen.dart';
import 'package:motogo_app/features/documents/invoices_screen.dart';
import 'package:motogo_app/features/documents/v2/docs_parts_v2.dart';
import 'package:motogo_app/features/messages/messages_screen.dart';
import 'package:motogo_app/features/profile/v2/profile_tiles_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/render_harness.dart' show loadRenderFonts;
import '../render/render_inspect.dart';
import '../support/fakes_home.dart' show loyaltyAt, mockPathProvider;
import '../support/fakes_profile.dart';
import '../support/fakes_profile_sub.dart';
import '../support/profile_harness.dart';
import '../support/v2_harness.dart';

const _widths = [320.0, 360.0, 412.0];
const _scales = [1.0, 1.3];

/// Real Montserrat metrics (MG_FONTS_DIR with ExtraBold / Black, or the
/// pub-cache 400–700 set) — with the 1 em test font every check is moot.
bool _fonts = false;

Widget _scaled(double scale, Widget child) => Builder(
      builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child),
    );

/// Pumps [build] in every language × width × text scale on a [height] tall
/// surface and returns every failing finding (empty = clean). [check] runs
/// extra layout assertions per combination.
Future<List<String>> _sweep(
  WidgetTester t,
  Widget Function() build,
  List<Override> Function() overrides, {
  double height = 2400,
  int level = 3,
  void Function(String lang, double width, double scale)? check,
}) async {
  final fails = <String>[];
  for (final lang in kV2Langs) {
    for (final w in _widths) {
      for (final s in _scales) {
        MgMotion.resetSession();
        final size = Size(w, height);
        await pumpV2(t, _scaled(s, build()),
            lang: lang, size: size, overrides: overrides(), reducedMotion: true, rank: RankTokens.forLevel(level));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 400));
        final id = '$lang ${w.toInt()} ×$s';
        final e = t.takeException();
        if (e != null) fails.add('$id exception: ${'$e'.split('\n').first}');
        for (final f in inspectFrame(t.binding.renderViews.first, lang, size)) {
          if (f.fail) fails.add('$id ${f.kind}: ${f.text} (${f.detail})');
        }
        check?.call(lang, w, s);
      }
    }
  }
  await t.pumpWidget(const SizedBox());
  return fails;
}

double _top(WidgetTester t, Finder f) => t.getRect(f).top;

void main() {
  setUpAll(() async {
    await loadRenderFonts();
    final dir = Platform.environment['MG_FONTS_DIR'];
    _fonts = montserratLoaded || (dir != null && dir.isNotEmpty && Directory(dir).existsSync());
    registerProfileStrings();
    mockPathProvider();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hub: tiles, rank strip, summary and groups keep whole words', (t) async {
    if (!_fonts) return markTestSkipped('no Montserrat');
    final fails = await _sweep(t, () => const PfHubHarness(), () => profileOverrides(eshop: true, unread: 12, loyalty: loyaltyAt(17)),
        height: 3600, level: 17, check: (lang, w, s) {
      // Grid while the labels fit (cs, 412 dp), one tile per row otherwise.
      Finder tile(String key) =>
          find.descendant(of: find.byType(ProfileTilesV2), matching: find.text(translations[lang]![key]!));
      final grid = _top(t, tile('messagesTitle')) == _top(t, tile('documents'));
      if (lang == 'cs' && w == 412 && s == 1.0) expect(grid, isTrue, reason: 'grid at 412');
      if (lang == 'de' && w == 320) expect(grid, isFalse, reason: 'one per row at 320 ×$s');
    });
    expect(fails, isEmpty, reason: fails.take(20).join('\n'));
  });

  testWidgets('hub form: date dropdowns never cut "05" / "1990" or the hints', (t) async {
    if (!_fonts) return markTestSkipped('no Montserrat');
    for (final fresh in [false, true]) {
      final fails = await _sweep(
        t,
        () => const PfHubHarness(expanded: true),
        () => fresh ? profileOverrides(profile: kProfileNew, docs: PfDocs.none, unread: 0) : profileOverrides(),
        height: 4200,
        check: (lang, w, s) {
          final dd = find.byType(DropdownButtonFormField<int>);
          expect(dd, findsNWidgets(6));
          final day = t.getRect(dd.at(0)), month = t.getRect(dd.at(1)), year = t.getRect(dd.at(2));
          if (!fresh && w == 412 && s == 1.0 && lang == 'cs') {
            // Today's 3 : 5 : 4 row where it fits.
            expect({day.top, month.top, year.top}.length, 1);
            expect(day.width / year.width, closeTo(3 / 4, 0.02));
          }
          if (w == 320 && s == 1.3) expect(year.top, greaterThan(day.bottom), reason: '$lang: year on its own line');
          // 360 dp (the usual phone): one row again once a date is filled in.
          if (!fresh && w == 360 && s == 1.0) expect(year.top, day.top, reason: '$lang: one row at 360');
        },
      );
      expect(fails, isEmpty, reason: '${fresh ? 'empty' : 'filled'}:\n${fails.take(20).join('\n')}');
    }
  });

  testWidgets('Moje doklady: cards side by side only when every word fits', (t) async {
    if (!_fonts) return markTestSkipped('no Montserrat');
    for (final st in [DocsState.ok, DocsState.missing, DocsState.none]) {
      final fails = await _sweep(t, () => const DocumentsScreen(), () => docsStatusOverrides(st), height: 1600, check: (lang, w, s) {
        final cards = find.byType(DocCardV2);
        expect(cards, findsNWidgets(2));
        final side = t.getRect(cards.at(0)).top == t.getRect(cards.at(1)).top;
        if (lang == 'cs' && w == 412 && s == 1.0) expect(side, isTrue, reason: 'side by side at 412');
        if (lang == 'de' && w == 320 && s == 1.3) expect(side, isFalse, reason: 'stacked at 320 × 1.3');
      });
      expect(fails, isEmpty, reason: '$st:\n${fails.take(20).join('\n')}');
    }
  });

  testWidgets('Faktury: the amount moves under a long title instead of splitting it', (t) async {
    if (!_fonts) return markTestSkipped('no Montserrat');
    final fails = await _sweep(t, () => const InvoicesScreen(), () => docListOverrides(), height: 1600, check: (lang, w, s) {
      if (lang != 'de') return;
      final title = t.getRect(find.text('Endrechnung')), amount = t.getRect(find.text('8450 Kč'));
      if (w == 320 && s == 1.3) expect(amount.top, greaterThan(title.bottom), reason: 'amount under the title');
      if (w == 412 && s == 1.0) expect(amount.left, greaterThan(title.right), reason: 'amount beside the title');
    });
    expect(fails, isEmpty, reason: fails.take(20).join('\n'));
  });

  testWidgets('Dokumenty a smlouvy + Zprávy: rows and segments keep whole words', (t) async {
    if (!_fonts) return markTestSkipped('no Montserrat');
    final fails = [
      ...await _sweep(t, () => const ContractsScreen(), () => docListOverrides(), height: 1800),
      ...await _sweep(t, () => const MessagesScreen(), () => messagesOverrides(unread: 3), height: 1600),
    ];
    expect(fails, isEmpty, reason: fails.take(20).join('\n'));
  });
}
