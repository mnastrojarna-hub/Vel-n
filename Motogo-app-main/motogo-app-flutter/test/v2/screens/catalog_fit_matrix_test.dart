// fix:catalog r1b — the r1 verify:render catalog findings as an always-on
// matrix: 8 languages × 320 / 360 / 412 dp × text scale 1.0 / 1.3. Each
// component is pumped at the width the app gives it, with the app's real
// strings, and the frame goes through the verifier's own inspector
// (render_inspect.dart): no FlutterError (RenderFlex overflow), no word of
// app copy split across lines, no cut / ellipsized app copy, no text wider
// than its box, nothing clipped by its card. Covered: spec tiles + all
// parameters (detail_specs_v2), the Motorky mode switch, the trip card
// (caps eyebrows, "Wybierz", loyalty-failure note), the grid card badge
// and the full photo card. Exact 800 / 900 weights need MG_FONTS_DIR
// (Montserrat Regular…Black); the pub-cache fallback has 400–700 only.
// The full screens stay in the opt-in matrix:
// `MG_VERIFY_RENDER=1 [MG_VERIFY_SCALE=1.0] flutter test test/v2/render/render_catalog_test.dart`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/booking/booking_quote.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode_switch_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_price.dart';
import 'package:motogo_app/features/catalog/v2/catalog_text.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_specs_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_trip_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_full_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_grid_v2.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';

import '../render/render_harness.dart' show loadRenderFonts;
import '../render/render_inspect.dart';
import '../support/fakes_catalog.dart';
import '../support/v2_harness.dart';

const _sizes = [Size(320, 690), Size(360, 780), Size(412, 915)];
const _scales = [1.0, 1.3];

/// Real Montserrat metrics (MG_FONTS_DIR or the pub-cache gallery fonts);
/// with the 1 em test font every word is wider → skip, not fail.
bool get _realFonts {
  final dir = Platform.environment['MG_FONTS_DIR'];
  return montserratLoaded || (dir != null && dir.isNotEmpty && Directory(dir).existsSync());
}

/// [child] at [scale] in a vertical scroll view of the phone width, with
/// [pad] dp on both sides (the app's page / sheet gutter).
Widget _frame(double scale, double pad, Widget child) => Builder(
      builder: (c) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: SingleChildScrollView(
          child: Padding(padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8), child: child),
        ),
      ),
    );

typedef _Build = Widget Function(AppTranslations tr, Size screen);

/// Pumps [build] for every language × size × scale; returns every failing
/// finding ("what lang width ×scale: kind text detail").
Future<List<String>> _matrix(WidgetTester t, String what, double pad, _Build build,
    {List<Override> Function()? overrides}) async {
  final out = <String>[];
  for (final lang in kV2Langs) {
    final tr = AppTranslations(lang);
    for (final size in _sizes) {
      for (final scale in _scales) {
        final id = '$what $lang ${size.width.toInt()} ×$scale';
        // A fresh tree per case (provider overrides differ between cases).
        await t.pumpWidget(const SizedBox());
        MgMotion.resetSession();
        // A tall view: the whole component is on screen (the inspector
        // skips what is scrolled away); widths are the phone's.
        await pumpV2(t, _frame(scale, pad, build(tr, size)),
            lang: lang, size: Size(size.width, 4000), reducedMotion: true, overrides: overrides?.call() ?? catalogOverrides());
        await t.pump(const Duration(milliseconds: 700));
        final ex = t.takeException();
        if (ex != null) out.add('$id: exception ${ex.toString().split('\n').first}');
        for (final f in inspectFrame(t.binding.renderViews.first, lang, size)) {
          if (f.fail) out.add('$id: ${f.kind} "${f.text}" ${f.detail}');
        }
      }
    }
  }
  return out;
}

/// Findings in shared v2 code (lib/core/…) are reported to the shared
/// owner, not fixed in the catalog area: printed here, failing only with
/// MG_STRICT_SHARED=1. Everything in lib/features/catalog must be clean.
void _expectClean(List<String> found) {
  final strict = Platform.environment['MG_STRICT_SHARED'] != null;
  final shared = found.where((f) => f.contains('@ lib/core/')).toList();
  for (final f in shared) {
    debugPrint('shared (reported, not catalog): $f');
  }
  final fails = strict ? found : found.where((f) => !shared.contains(f)).toList();
  expect(fails, isEmpty, reason: fails.take(12).join('\n'));
}

DetailTripCardV2 _trip(Motorcycle m, {DateTime? s, DateTime? e, LoyaltyStatus? loyalty}) {
  final has = s != null && e != null;
  return DetailTripCardV2(
    moto: m,
    selStart: s,
    selEnd: e,
    hasDates: has,
    dayCount: has ? catDayCount(s, e) : 0,
    listTotal: has ? listQuoteFor(m, s, e).total : 0,
    quote: has ? quoteFor(m, s, e, loyalty: loyalty) : null,
    calendarExpanded: false,
    onToggleCalendar: () {},
    onRangeSelected: (_, __) {},
    onStartSelected: (_) {},
    onReset: () {},
    bookedAsync: const AsyncData([]),
  );
}

void main() {
  setUpAll(() async {
    await loadRenderFonts();
    registerCatalogStrings();
  });
  final (ws, we) = futureWeekend();

  testWidgets('spec tiles + all parameters (detail_specs_v2)', (t) async {
    if (!_realFonts) return;
    _expectClean([
      ...await _matrix(t, 'tiles-bmw', 16, (tr, s) => DetailKeyTilesV2(moto: kBmw)),
      ...await _matrix(t, 'tiles-husq', 16, (tr, s) => DetailKeyTilesV2(moto: kHusq)),
      ...await _matrix(t, 'all-params', 16, (tr, s) => DetailCardV2(child: DetailAllParamsV2(specs: kBmw.specList(tr.tr)))),
    ]);
  });

  testWidgets('Motorky mode switch: whole words, subs never cut', (t) async {
    if (!_realFonts) return;
    _expectClean([
      for (final mode in CatalogMode.values)
        ...await _matrix(t, 'switch-${mode.name}', 16, (tr, s) => CatalogModeSwitchV2(mode: mode, onChanged: (_) {})),
    ]);
  });

  testWidgets('trip card: caps eyebrows, pick-date value, loyalty note', (t) async {
    if (!_realFonts) return;
    _expectClean([
      ...await _matrix(t, 'trip-nodates', 16, (tr, s) => _trip(kBmw)),
      ...await _matrix(t, 'trip-loyalty-fail', 16, (tr, s) => _trip(kBmw),
          overrides: () => catalogOverrides(loyaltyError: Exception('rpc'))),
      ...await _matrix(t, 'trip-dates', 16, (tr, s) => _trip(kBmw, s: ws, e: we, loyalty: kLoyalty3)),
      ...await _matrix(t, 'trip-dates-guest', 16, (tr, s) => _trip(kBmw, s: ws, e: we),
          overrides: () => catalogOverrides(loyalty: null)),
    ]);
  });

  testWidgets('grid cards: availability badge stays inside the card', (t) async {
    if (!_realFonts) return;
    Widget pair(AppTranslations tr, DateTime? s, DateTime? e, String key) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, m) in [kBmw, kHusq].indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: MotoCardGridV2(
                    moto: m, price: catCardPrice(tr, m, s, e, kLoyalty3), availability: tr.tr(key), onOpen: () {}),
              ),
            ],
          ]),
        );
    _expectClean([
      ...await _matrix(t, 'grid-dates', 16, (tr, s) => pair(tr, ws, we, 'v2CatFreeInRange')),
      ...await _matrix(t, 'grid-today', 16, (tr, s) => pair(tr, null, null, 'v2CatFreeToday')),
    ]);
  });

  testWidgets('full card: tags, name, price + CTA never clip', (t) async {
    if (!_realFonts) return;
    Widget card(AppTranslations tr, Size s, DateTime? from, DateTime? to) => MotoCardFullV2(
          moto: kBmw,
          price: catCardPrice(tr, kBmw, from, to, kLoyalty3),
          availability: tr.tr(from != null ? 'v2CatFreeInRange' : 'v2CatFreeToday'),
          ctaLabel: tr.tr(from != null ? 'v2CatCtaBook' : 'v2CatCtaPick'),
          height: (s.height * 0.72).clamp(460.0, 600.0),
          onOpen: () {},
        );
    _expectClean([
      ...await _matrix(t, 'full-dates', 0, (tr, s) => card(tr, s, ws, we)),
      ...await _matrix(t, 'full-nodates', 0, (tr, s) => card(tr, s, null, null)),
    ]);
  });
}
