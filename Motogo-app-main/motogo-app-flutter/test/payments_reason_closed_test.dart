// f1 (2026-10-22): zaplacenou změnu nešlo zapsat, protože rezervace byla mezitím
// zrušená / ukončená (server: booking_cancelled / booking_completed) — appka nesmí
// tvrdit, že rezervace „platí v původní podobě" (pdFailOther). Chybějící řidičské
// oprávnění (license_insufficient) má vlastní text (pdFailLicense) jako web.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/paid_change_entry.dart';
import 'package:motogo_app/features/payment/paid_change_outcomes.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];
final _contact = RegExp(r'@|\+420|774 ?256|napiš(te)? nám|ozveme|zavolej|contact us|call us|kontakt', caseSensitive: false);

void main() {
  test('booking_cancelled / booking_completed → pdFailStatus, ne „platí v původní podobě"', () {
    for (final lang in _langs) {
      final tr = AppTranslations(lang);
      for (final r in ['booking_cancelled', 'booking_completed']) {
        expect(paidChangeReasonText(tr, r), tr.tr('pdFailStatus'), reason: '$lang $r');
        final s = paidChangeFailureText(tr, reason: r, refund: 'auto', amount: 15);
        expect(s, isNot(contains(tr.tr('pdFailOther'))), reason: '$lang $r');
        expect(_contact.hasMatch(s), isFalse, reason: '$lang $r');
      }
    }
    final cs = AppTranslations('cs');
    final s = paidChangeFailureText(cs, reason: 'booking_cancelled', refund: 'auto', amount: 7.5);
    expect(s, isNot(contains('platí v původní podobě')));
    expect(s, contains('zrušená'));
    expect(s, contains('7,50 Kč'));
  });

  test('license_insufficient → pdFailLicense ve všech jazycích, bez kontaktů', () {
    for (final lang in _langs) {
      final tr = AppTranslations(lang);
      final t = paidChangeReasonText(tr, 'license_insufficient');
      expect(t, tr.tr('pdFailLicense'), reason: lang);
      expect(t, isNot('pdFailLicense'), reason: '$lang: chybí překlad');
      expect(t, isNot(tr.tr('pdFailOther')), reason: lang);
      expect(_contact.hasMatch(t), isFalse, reason: lang);
    }
    expect(paidChangeReasonText(AppTranslations('cs'), 'license_insufficient'), contains('řidičské oprávnění'));
  });

  test('výsledková obrazovka: zrušená rezervace — bez nabídky „Vybrat jinou motorku"', () {
    final tr = AppTranslations('cs');
    final o = changeFailedOutcome(tr,
        swap: true,
        bookingId: 'b1',
        r: const PaidChangeResult(PaidChangeStatus.failed, reason: 'booking_cancelled', refund: 'auto', amount: 15),
        charge: 15);
    expect(o.subtitle, isNot(contains('platí v původní podobě')));
    expect(o.subtitle, contains('automaticky'));
    expect(o.secondaryLabel, isNull);
  });
}
