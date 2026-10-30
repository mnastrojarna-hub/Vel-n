// fix:reservations r1b — the r1 verify:render Rezervace findings as an
// always-on matrix: 8 languages × 320 / 360 / 412 dp × text scale 1.0 /
// 1.3. Each part is pumped at the width the app gives it, with the app's
// real strings, in a tall view (the whole part on screen), and the frame
// goes through the verifier's own inspector (render_inspect.dart): no
// FlutterError (RenderFlex overflow), no word of app copy split across
// lines, no cut / ellipsized app copy, no text wider than its box, nothing
// clipped. Covered (r1_area_issues.json → reservations):
//  1. list: "Moje rezervace" header + Živě pill, cards of every status
//     (Termín · Délka · Celkem labels, status pill next to Nezaplaceno /
//     ověřování, Detail · Upravit · Obnovit · Hodnotit · SOS actions) on
//     the dark strip of the list's one primary card and on the white one;
//  2. detail: journey timeline, Upravit / Zrušit tiles, documents, history,
//     payment rows + copy rows, gear chips, SOS photo chip, door-code
//     labels, the old modification history, the cancel dialog;
//  3. edit: header TEĎ row, chooser tiles, price total (Doplatek /
//     Vrácení), date boxes, shorten chips, gear pickers, paid add-on cards,
//     own-gear toggle.
// Findings in shared code reported to its owner (booking's address picker)
// are printed, failing only with MG_STRICT_SHARED=1; MG_FIT_DUMP=1 prints
// every failing finding. The full screens + scroll positions stay in the
// opt-in matrix: `MG_VERIFY_RENDER=1 [MG_VERIFY_SCALE=1.0] flutter test
// test/v2/render/render_res_test.dart`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/v2/res_cancel_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_list_header_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_status_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservation_card_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/render_harness.dart' show loadRenderFonts;
import '../render/render_inspect.dart';
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';
import 'reservations_cases.dart';

const _sizes = [Size(320, 690), Size(360, 780), Size(412, 915)];
final _loc = RegExp(r'(package:motogo_app/[^\s:)]+:\d+|file://[^\s)]+/lib/[^\s:)]+:\d+)');
const _scales = [1.0, 1.3];

/// Real Montserrat metrics (MG_FONTS_DIR or the pub-cache gallery fonts);
/// with the 1 em test font every word is wider → skip, not fail.
bool get _realFonts {
  final dir = Platform.environment['MG_FONTS_DIR'];
  return montserratLoaded || (dir != null && dir.isNotEmpty && Directory(dir).existsSync());
}

/// [child] at [scale]: a part in a vertical scroll view with [pad] dp on
/// both sides ([page] = a whole page that scrolls by itself).
Widget _frame(double scale, double pad, bool page, Widget child) => Builder(
      builder: (c) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: page
            ? child
            : SingleChildScrollView(
                child: Padding(padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8), child: child),
              ),
      ),
    );

class _Part {
  final String name;
  final Widget Function() build;
  final List<Override> Function() overrides;
  final double pad;
  final bool page;
  final Future<void> Function(WidgetTester, String lang)? after;

  /// View height: the whole part must be laid out (slivers past the view
  /// are not built, so an opened page needs a taller one).
  final double height;
  const _Part(this.name, this.build, this.overrides, {this.pad = 16, this.page = false, this.after, this.height = 2400});
}

/// Pumps [p] for every language × size × scale; returns every failing
/// finding ("name lang width ×scale: kind text detail").
Future<List<String>> _matrix(WidgetTester t, _Part p) async {
  final out = <String>[];
  for (final lang in kV2Langs) {
    for (final size in _sizes) {
      for (final scale in _scales) {
        final id = '${p.name} $lang ${size.width.toInt()} ×$scale';
        await t.pumpWidget(const SizedBox());
        MgMotion.resetSession();
        // EVERY FlutterError (not just the first): two overflows in one
        // frame are two findings.
        final errors = <(String, String)>[];
        final orig = FlutterError.onError;
        FlutterError.onError = (d) => errors.add((d.exceptionAsString().split('\n').first.trim(), d.toString()));
        try {
          // Tall view: the whole part / page is on screen (the inspector
          // skips what is scrolled away); the width is the phone's.
          await pumpV2(t, _frame(scale, p.pad, p.page, p.build()),
              lang: lang, size: Size(size.width, p.height), reducedMotion: true, overrides: p.overrides());
          await t.pump(const Duration(milliseconds: 700));
          if (p.after != null) await p.after!(t, lang);
        } finally {
          FlutterError.onError = orig;
        }
        for (final (first, e) in errors) {
          final loc = _loc.firstMatch(e)?.group(0)?.replaceAll('package:motogo_app/', 'lib/').replaceAll(RegExp(r'^.*?/lib/'), 'lib/') ?? '';
          out.add('$id: exception $first @ $loc');
        }
        for (final f in inspectFrame(t.binding.renderViews.first, lang, size)) {
          if (f.fail) out.add('$id: ${f.kind} "${f.text}" ${f.detail}');
        }
        // Timers of the page (5 s refresh, pings) end with the tree.
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 6));
      }
    }
  }
  return out;
}

/// Shared code that shows a finding inside a Rezervace page and was
/// reported to its owner (booking: the address picker's "Récupération à
/// votre adresse" at fr 320 dp ×1.3) — printed here, failing only with
/// MG_STRICT_SHARED=1. Everything else must be clean, also findings located
/// in shared v2 widgets (a too narrow slot given by a Rezervace layout).
const _reported = ['@ lib/features/booking/widgets/address_picker.dart:'];

void _expectClean(List<String> found) {
  final strict = Platform.environment['MG_STRICT_SHARED'] != null;
  final other = found.where((f) => _reported.any(f.contains)).toList();
  for (final f in other) {
    debugPrint('shared (reported, not reservations): $f');
  }
  final fails = strict ? found : found.where((f) => !other.contains(f)).toList();
  if (Platform.environment['MG_FIT_DUMP'] != null) {
    for (final f in fails) {
      debugPrint('FIT: $f');
    }
  }
  expect(fails, isEmpty, reason: fails.take(12).join('\n'));
}

Future<void> _tapText(WidgetTester t, String lang, String key) async {
  final f = find.text(translations[lang]?[key] ?? key);
  if (f.evaluate().isEmpty) return;
  await t.tap(f.first, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

/// Every card kind; [primary] false = the white strip of the list's other
/// cards (btnGhostLight + btnText, R5.2).
Widget _cards({bool primary = true}) {
  final unpaid = resv('u1', status: 'pending', pay: 'unpaid', from: 9, to: 11, bike: 'BMW R 1200 GS Adventure');
  final sos = resv('s1', status: 'active', from: -1, to: 2, sosReplacement: true, handedOver: rday(-1));
  Widget card(Reservation r, {ResPayFlag flag = ResPayFlag.none}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ReservationCardV2(
            reservation: r, payFlag: flag, primary: primary, onTap: () {}, onEdit: () {}, onRestore: () {}),
      );
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    for (final r in sampleList()) card(r),
    card(unpaid, flag: ResPayFlag.unpaid),
    card(unpaid, flag: ResPayFlag.verifying),
    card(sos),
  ]);
}

void main() {
  setUpAll(() async {
    await loadRenderFonts();
    registerReservationStrings();
    mockPathProvider();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final detail = detailCases();
  final edit = editCases();
  _Part detailPart(String k, {Future<void> Function(WidgetTester, String)? after}) =>
      _Part('detail-$k', detail[k]!.$1, detail[k]!.$2, page: true, after: after, height: after == null ? 3600 : 7000);
  _Part editPart(String k) => _Part('edit-$k', edit[k]!.$1, edit[k]!.$2, page: true, height: 3600);

  testWidgets('1 list: header title + Živě, card labels, status pill, actions', (tester) async {
    if (!_realFonts) return;
    _expectClean([
      ...await _matrix(tester, _Part('list-header', () => const ResListHeaderV2(), () => resOverrides(), pad: 0)),
      ...await _matrix(tester, const _Part('cards', _cards, resOverrides, height: 3200)),
      ...await _matrix(tester, _Part('cards-light', () => _cards(primary: false), resOverrides, height: 3200)),
    ]);
  });

  testWidgets('2 detail: timeline, tiles, docs, history, payment rows, chips, cancel', (tester) async {
    if (!_realFonts) return;
    _expectClean([
      for (final k in ['unpaid', 'ready', 'active', 'docs', 'sos', 'done-0']) ...await _matrix(tester, detailPart(k)),
      ...await _matrix(
          tester,
          detailPart('done-5', after: (tt, lang) async {
            await _tapText(tt, lang, 'paymentDetailsTab');
            await _tapText(tt, lang, 'v2ResHistory');
          })),
      ...await _matrix(
          tester,
          _Part(
              'cancel-confirm',
              () => Builder(
                  builder: (c) => ResCancelConfirmV2(
                      motoName: 'Husqvarna 701 SM',
                      dateRange: '16. 10. – 18. 10. 2026',
                      pct: 50,
                      refundLine: t(c).tr('currentlyRefund').replaceAll('{pct}', '50').replaceAll('{amount}', '6014'),
                      loading: false,
                      onReason: (_) {},
                      onKeep: () {},
                      onCancel: () {})),
              () => resOverrides(),
              pad: 0,
              page: true)),
    ]);
  });

  testWidgets('3 edit: header, chooser, price, dates, chips, gear, add-ons', (tester) async {
    if (!_realFonts) return;
    _expectClean([
      for (final k in ['chooser', 'chooser-active', 'chooser-changed', 'extend', 'shorten', 'gear', 'place', 'time', 'active-extend'])
        ...await _matrix(tester, editPart(k)),
    ]);
  });
}
