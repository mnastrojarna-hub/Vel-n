// fix:backend 2 (2026-10-16): process-payment `price_outdated` — cena rezervace
// neodpovídá ceníku / slevám. Appka NEnabízí jinou částku (zaplaceno by se lišilo
// od dokladů), řekne přesně co se stalo, že se nic nestrhlo, a vede k nové
// rezervaci. Ve všech 8 jazycích, bez kontaktů (D5).
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/payment/payment_refusals.dart';
import 'package:motogo_app/features/payment/stripe_service.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];
final _contact = RegExp(r'@|\+420|774 ?256|napiš(te)? nám|contact us|write to us', caseSensitive: false);

PaymentResult _refused(String code) => PaymentResult.error('server text $code',
    code: PaymentErrorCode.serverError, serverCode: code, httpStatus: 409);

void main() {
  test('price_outdated: přesný text v 8 jazycích, žádná částka k zaplacení, bez kontaktu', () {
    for (final lang in _langs) {
      final p = PaymentRefusals.resolve(lang, _refused('price_outdated'), PayFlow.booking, amount: 10);
      expect(p.action, PayAction.editBooking, reason: lang);
      expect(p.serverTotal, isNull, reason: '$lang: nenabízet jinou částku');
      expect(p.title, isNot(contains('pdPriceOutdated')), reason: '$lang title untranslated');
      expect(p.message, isNot(contains('pdPriceOutdated')), reason: '$lang body untranslated');
      expect(p.message, isNot(contains('server text')), reason: lang);
      expect(_contact.hasMatch('${p.title} ${p.message}'), isFalse, reason: '$lang contact');
    }
    expect(PaymentRefusals.resolve('cs', _refused('price_outdated'), PayFlow.resume, amount: 10).action,
        PayAction.reservations);
  });
}
