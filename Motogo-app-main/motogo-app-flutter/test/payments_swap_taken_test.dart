// Odpověď majitele 2026-10-16 (otázka 3): zaplacenou výměnu nejde zapsat, protože
// motorku mezitím obsadila jiná rezervace → nová rezervace má přednost. Zákazník
// vidí „Motorka je mezitím obsazená", že se doplatek vrací (bez slibu e-mailu —
// vratka nezapsané změny jde přímo ze Stripe bez dokladu) a volby „Vybrat jinou
// motorku" / „Ponechat současnou motorku". Bez kontaktů, 8 jazyků.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/paid_change_entry.dart';
import 'package:motogo_app/features/payment/paid_change_outcomes.dart';
import 'package:motogo_app/features/payment/payment_provider.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];
final _contact = RegExp(r'@|\+420|774 ?256|napiš(te)? nám|ozveme|zavolej|contact us|call us|kontakt', caseSensitive: false);
final _mail = RegExp(r'e-?mail|correo|mailом|poczt', caseSensitive: false);

void main() {
  group('swap taken (new booking has priority)', () {
    test('result screen: title, refund text, pick another / keep current', () {
      final tr = AppTranslations('cs');
      final o = changeFailedOutcome(tr,
          swap: true,
          bookingId: 'b1',
          r: const PaidChangeResult(PaidChangeStatus.failed, reason: 'new_moto_unavailable', refund: 'auto', amount: 15),
          charge: 15);
      expect(o.kind, PaymentOutcomeKind.failed);
      expect(o.title, 'Motorka je mezitím obsazená');
      expect(o.subtitle, contains('původní rezervace platí beze změny'));
      expect(o.subtitle, contains('automaticky vracíme'));
      expect(o.ctaLabel, 'Vybrat jinou motorku');
      expect(o.ctaRoute, '/reservations/b1/edit?tab=swap');
      expect(o.secondaryLabel, 'Ponechat současnou motorku');
      expect(o.secondaryRoute, '/reservations/b1');
    });

    test('edit refused because the bike is taken: same title, no swap offer', () {
      final tr = AppTranslations('cs');
      final o = changeFailedOutcome(tr,
          swap: false,
          bookingId: 'b1',
          r: const PaidChangeResult(PaidChangeStatus.failed, reason: 'moto_unavailable', refund: 'staff', amount: 120),
          charge: 120);
      expect(o.title, 'Motorka je mezitím obsazená');
      expect(o.ctaRoute, '/reservations/b1');
      expect(o.secondaryRoute, isNull);
      expect(o.subtitle, contains('obsluha'));
    });

    test('other failure keeps the old titles and the single CTA', () {
      final tr = AppTranslations('cs');
      final o = changeFailedOutcome(tr,
          swap: true,
          bookingId: 'b1',
          r: const PaidChangeResult(PaidChangeStatus.failed, reason: 'booking_cancelled', refund: 'auto', amount: 15),
          charge: 15);
      expect(o.title, tr.tr('pdSwapFailedTitle'));
      expect(o.ctaRoute, '/reservations/b1');
      expect(o.secondaryLabel, isNull);
      expect(isTakenReason('new_moto_unavailable') && isTakenReason('moto_unavailable') && !isTakenReason('db_refused'), isTrue);
    });

    test('8 languages: new keys present, refund texts promise no e-mail, no contact', () {
      for (final lang in _langs) {
        final tr = AppTranslations(lang);
        for (final k in ['pdTakenTitle', 'pdPickOtherMoto', 'pdKeepCurrentMoto', 'pdRefundAuto', 'pdRefundStaff']) {
          final s = tr.tr(k);
          expect(s, isNot(k), reason: '$lang/$k missing');
          expect(_contact.hasMatch(s), isFalse, reason: '$lang/$k');
        }
        for (final k in ['pdRefundAuto', 'pdRefundStaff']) {
          expect(_mail.hasMatch(tr.tr(k)), isFalse, reason: '$lang/$k promises an e-mail');
          expect(tr.tr(k), contains('{amount}'), reason: '$lang/$k');
        }
        final o = changeFailedOutcome(tr,
            swap: true,
            bookingId: 'b1',
            r: const PaidChangeResult(PaidChangeStatus.failed, reason: 'new_moto_unavailable', amount: 15),
            charge: 15);
        expect(o.title, tr.tr('pdTakenTitle'), reason: lang);
        expect(o.subtitle, isNot(contains('{')), reason: lang);
      }
    });
  });
}
