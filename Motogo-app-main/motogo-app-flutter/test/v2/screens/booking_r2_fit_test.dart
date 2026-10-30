// fix:booking:r2 fit: the address picker's method options never split a
// word (price moves under the text when needed — shared widget, both
// looks), the date card's new states (booked day in the range, "Ponechat
// termín") and the error banner's fix actions fit in 8 languages × 2 sizes.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/features/booking/v2/booking_date_v2.dart';
import 'package:motogo_app/features/booking/v2/booking_warning_v2.dart';
import 'package:motogo_app/features/booking/widgets/address_picker.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';

import '../render/render_inspect.dart' show inspectFrame, midWordBreak;
import '../support/fakes_booking.dart' show futureWeekend;
import '../support/v2_harness.dart';

String _tr(String lang, String key) => translations[lang]?[key] ?? translations['cs']![key]!;

Widget _host(Widget child, double width, double scale) => Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: SingleChildScrollView(
          child: Align(alignment: Alignment.topCenter, child: SizedBox(width: width, child: child)),
        ),
      ),
    );

void main() {
  setUpAll(loadMontserrat);
  final (s, e) = futureWeekend();

  for (final lang in kV2Langs) {
    for (final pickup in [true, false]) {
      // 288 = 320 screen − gutters; 256 / 240 = inside a card (res. edit "Místo", saved-delivery host).
      for (final width in [288.0, 256.0, 240.0]) {
        testWidgets('address options $lang ${pickup ? 'pickup' : 'return'} $width ×1.3: no mid-word break', (t) async {
          await pumpV2(
            t,
            _host(
              AddressPickerWidget(
                label: 'x',
                isPickup: pickup,
                method: 'delivery',
                onMethodChanged: (_) {},
                onAddressChanged: (_) {},
                onDeliveryFeeChanged: (_) {},
              ),
              width,
              1.3,
            ),
            lang: lang,
            size: const Size(320, 690),
          );
          await t.pump();
          expect(t.takeException(), isNull);
          final title = _tr(lang, pickup ? 'deliveryToAddress' : 'returnFromAddress');
          for (final text in [_tr(lang, 'atBranch'), title]) {
            if (montserratLoaded) expect(midWordBreak(t.renderObject<RenderParagraph>(find.text(text))), isNull, reason: text);
          }
        });
      }
    }
  }

  for (final lang in kV2Langs) {
    for (final size in kV2Sizes) {
      testWidgets('date card busy / keep + error actions $lang ${size.width.toInt()}', (t) async {
        Widget card(bool busy) => BookingDateCardV2(
              start: s,
              end: e,
              hasDates: true,
              dayCount: 3,
              basePrice: 12345,
              calOpen: true,
              busy: busy,
              onKeep: () {},
              booked: AsyncValue.data([BookedDateRange(start: e, end: e, status: 'reserved')]),
              onOpenCalendar: () {},
              onRangeSelected: (_, __) {},
              onReset: () {},
              onRetryBooked: () {},
            );
        await pumpV2(
          t,
          _host(
            Column(children: [
              card(true),
              card(false),
              BookingWarningsV2(
                missingSizes: const [],
                err: _tr(lang, 'v2CalcRangeBusy'),
                errActions: [
                  (_tr(lang, 'pdPickOtherMoto'), () {}),
                  (_tr(lang, 'completeProfileBtn'), () {}),
                  (_tr(lang, 'v2BkFixTime'), () {}),
                  (_tr(lang, 'psChangeDates'), () {}),
                ],
                profileErr: null,
                bookedFailed: false,
                onCompleteProfile: () {},
                onRetryBooked: () {},
              ),
            ]),
            size.width - 32,
            1.0,
          ),
          lang: lang,
          size: size,
        );
        await t.pump(const Duration(milliseconds: 400));
        expect(t.takeException(), isNull);
        expect(find.text(_tr(lang, 'v2CalcRangeBusy')), findsWidgets);
        expect(find.text(_tr(lang, 'v2BkKeepDates')), findsOneWidget);
        final fails = inspectFrame(t.binding.renderViews.first, lang, size).where((f) => f.fail).toList();
        expect(fails, isEmpty, reason: fails.join('\n'));
      });
    }
  }
}
