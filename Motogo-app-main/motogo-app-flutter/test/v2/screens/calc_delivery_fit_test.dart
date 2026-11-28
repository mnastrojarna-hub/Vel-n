// Calculator with delivery (owner 2026-11-27) — fit matrix of the new step
// and the receipt rows: 8 languages × 320×640 / 360×780 × text scale
// 1.0 / 1.3, pumped at the width the app gives them (page gutter 16, step
// card) with the app's real strings and checked by the render inspector:
// no FlutterError (overflow), no app copy cut or wider than its box, no
// word split across lines. States: delivery + collection with address, fee,
// "same address" note and the lead-time warning; delivery without an
// address; self-service lock (collapsed + explanation open); no bike; the
// receipt and total with both fee rows.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/booking_address_carry.dart';
import 'package:motogo_app/core/booking_form_locked_option.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_quote.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_parts_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_receipt_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_step_handover_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_total_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';

import '../render/render_harness.dart' show loadRenderFonts;
import '../render/render_inspect.dart';
import '../support/fakes_booking.dart' show registerBookingStrings;
import '../support/fakes_calc_delivery.dart';
import '../support/fakes_catalog.dart';
import '../support/v2_harness.dart';

const _sizes = [Size(320, 640), Size(360, 780)];
const _scales = [1.0, 1.3];

bool get _realFonts {
  final dir = Platform.environment['MG_FONTS_DIR'];
  return montserratLoaded || (dir != null && dir.isNotEmpty && Directory(dir).existsSync());
}

Widget _frame(double scale, Widget child) => Builder(
      builder: (c) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child)),
      ),
    );

/// Step ④ as the calculator shows it for [moto] and [own] (null = untouched).
Widget _step(Motorcycle? moto, HandoverChoice? own, DateTime start) => Consumer(builder: (ctx, ref, _) {
      final st = CalcState(
          motoId: moto?.id,
          start: start,
          end: start,
          handover: own == null ? null : CalcHandover(choice: own, branchId: moto?.branchId));
      final hv = moto == null ? null : calcHandoverView(ref, st, moto, t(ctx).lang);
      return CalcStepCardV2(
        n: 4,
        done: hv != null && hv.missingAddressKey == null,
        title: t(ctx).tr('v2CalcStepHandover'),
        child: CalcStepHandoverV2(moto: moto, st: st, view: hv),
      );
    });

typedef _After = Future<void> Function(WidgetTester t);

Future<List<String>> _matrix(WidgetTester t, String what, Widget Function() build, {_After? after}) async {
  final out = <String>[];
  for (final lang in kV2Langs) {
    for (final size in _sizes) {
      for (final scale in _scales) {
        final id = '$what $lang ${size.width.toInt()} ×$scale';
        await t.pumpWidget(const SizedBox());
        MgMotion.resetSession();
        // A tall view: the whole component is on screen; the width is the phone's.
        await pumpV2(t, _frame(scale, build()),
            lang: lang, size: Size(size.width, 3200), reducedMotion: true, overrides: catalogOverrides(profile: kProfileJihlava));
        await t.pump(const Duration(milliseconds: 700));
        if (after != null) await after(t);
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

/// Findings inside the booking form's OWN widgets (the reused sections,
/// option rows and locked tile — the same pixels as in the form) are
/// reported to their owner, not fixed here: printed, failing only with
/// MG_STRICT_SHARED=1 (the convention of `catalog_fit_matrix_test.dart`).
/// Everything of the calculator itself must be clean.
void _expectClean(List<String> found) {
  final strict = Platform.environment['MG_STRICT_SHARED'] != null;
  final form = found.where((f) => f.contains('@ lib/features/booking/') || f.contains('@ lib/core/')).toList();
  for (final f in form) {
    debugPrint('booking form widget (reported, not calculator): $f');
  }
  final fails = strict ? found : found.where((f) => !form.contains(f)).toList();
  expect(fails, isEmpty, reason: fails.take(12).join('\n'));
}

void main() {
  setUpAll(() async {
    await loadRenderFonts();
    registerCatalogStrings();
    registerBookingStrings();
  });
  final (ws, we) = futureWeekend();
  final now = DateTime.now();
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  final longAddr = HandoverChoice(
    draft: BookingDraft(
      pickupMethod: 'delivery',
      returnMethod: 'delivery',
      pickupCity: 'Nové Město na Moravě',
      pickupAddress: 'Vratislavovo náměstí 103',
      returnCity: 'Nové Město na Moravě',
      returnAddress: 'Vratislavovo náměstí 103',
    ),
    pickupFee: 3212,
    pickupKm: 55.3,
    returnFee: 3212,
    returnKm: 55.3,
  );

  testWidgets('step ④: delivery + collection with address, fee, note and lead-time warning', (t) async {
    if (!_realFonts) return;
    _expectClean(await _matrix(t, 'both', () => _step(kBmw, longAddr, yesterday)));
  });

  testWidgets('step ④: untouched and delivery without an address', (t) async {
    if (!_realFonts) return;
    _expectClean([
      ...await _matrix(t, 'untouched', () => _step(kBmw, null, ws)),
      ...await _matrix(t, 'no-address', () => _step(kBmw, HandoverChoice(draft: BookingDraft(pickupMethod: 'delivery')), ws)),
    ]);
  });

  testWidgets('step ④: self-service lock (collapsed and open) and no bike', (t) async {
    if (!_realFonts) return;
    _expectClean([
      ...await _matrix(t, 'locked', () => _step(kHusq, null, ws)),
      ...await _matrix(t, 'locked-open', () => _step(kHusq, null, ws), after: (t) async {
        await t.tap(find.byType(BookingLockedOptionTile).first);
        await t.pump(const Duration(milliseconds: 400));
      }),
      ...await _matrix(t, 'no-bike', () => _step(null, null, ws)),
    ]);
  });

  // The real Motorky screen (calculator mode) at the two phone sizes: the
  // step, the receipt and the total scroll by without any overflow.
  testWidgets('smoke: Motorky → Spočítat cenu with delivery, 320×640 / 360×780 × 8 languages', (t) async {
    final own = CalcHandover(choice: longAddr, branchId: kBmw.branchId);
    for (final lang in kV2Langs) {
      for (final size in _sizes) {
        for (final st in [
          CalcState(motoId: 'm-bmw', start: ws, end: we, handover: own),
          CalcState(motoId: 'm-husq', start: ws, end: we),
        ]) {
          await t.pumpWidget(const SizedBox());
          MgMotion.resetSession();
          await pumpV2(t, const MotorkyScreenV2(), lang: lang, size: size, reducedMotion: true, overrides: [
            ...catalogOverrides(calc: st, profile: kProfileJihlava),
            catalogCalcRequestProvider.overrideWith((ref) => true),
          ]);
          await t.pump(const Duration(milliseconds: 600));
          final id = '$lang ${size.width.toInt()}×${size.height.toInt()} ${st.motoId}';
          expect(t.takeException(), isNull, reason: id);
          for (final type in [CalcStepHandoverV2, CalcReceiptV2, CalcTotalV2]) {
            await t.scrollUntilVisible(find.byType(type), 300, scrollable: find.byType(Scrollable).first);
            await t.pump(const Duration(milliseconds: 300));
            expect(t.takeException(), isNull, reason: '$id $type');
          }
        }
      }
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('receipt and total with both fee rows and the missing-address hint', (t) async {
    if (!_realFonts) return;
    final q = quoteFor(kBmw, ws, we, loyalty: kLoyalty3, pickupDeliveryFee: 3212, returnDeliveryFee: 13960);
    final q12 = quoteFor(kBmw, ws, we, pickupTime: '12:00', loyalty: kLoyalty3, pickupDeliveryFee: 3212, returnDeliveryFee: 13960);
    _expectClean(await _matrix(
        t,
        'receipt',
        () => Builder(
            builder: (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CalcReceiptV2(moto: kBmw, start: ws, end: we, q: q),
                  const SizedBox(height: 12),
                  CalcTotalV2(
                      q: q,
                      q12: q12,
                      rankName: q.loyaltyRankName,
                      onBook: () {},
                      onRetryLoyalty: () {},
                      note: _hint(c)),
                ]))));
  });
}

/// The form's missing-address hint in the pumped language.
String _hint(BuildContext c) => t(c).tr('efoNoAddrCtx');
