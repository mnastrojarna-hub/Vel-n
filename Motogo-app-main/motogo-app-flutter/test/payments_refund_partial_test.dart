// Oprava 2026-10-22 (f2): vratka za zkrácení / levnější motorku z appky se
// může vrátit jen ČÁSTEČNĚ (automaticky jen ověřený přeplatek, zbytek dokončí
// obsluha). process-refund pak vrací `partial: true` (a `amount_refunded`
// menší než požadovaná částka) — appka nesmí slibovat celou částku a ukáže
// pdRefundManual. Odpovědi starého serveru (bez `partial`) se chovají jako dřív.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/reservations/widgets/reservation_edit_states.dart';

void main() {
  group('refundFellShort', () {
    test('partial flag from server → short', () {
      expect(refundFellShort({'success': true, 'partial': true, 'amount_refunded': 500}, 500), isTrue);
    });
    test('amount_refunded below requested → short (also without partial flag)', () {
      expect(refundFellShort({'success': true, 'amount_refunded': 115}, 500), isTrue);
      expect(refundFellShort({'success': true, 'amount_refunded': 315.0, 'partial': false}, 500), isTrue);
      expect(refundFellShort({'success': true, 'amount_refunded': 498.9}, 500), isTrue);
    });
    test('full refund / rounding up to 1 Kč / old server without amount → not short', () {
      expect(refundFellShort({'success': true, 'amount_refunded': 500, 'partial': false}, 500), isFalse);
      expect(refundFellShort({'success': true, 'amount_refunded': 123.45}, 123.454), isFalse);
      expect(refundFellShort({'success': true, 'amount_refunded': 333.33}, 333.335), isFalse);
      expect(refundFellShort({'success': true, 'amount_refunded': 499}, 500), isFalse);
      expect(refundFellShort({'success': true, 'already_refunded': true}, 500), isFalse);
      expect(refundFellShort({'success': true, 'manual': true, 'amount': 500}, 500), isFalse);
      expect(refundFellShort(null, 500), isFalse);
      expect(refundFellShort('x', 500), isFalse);
    });
    test('manual refund capped by verified overpayment → partial flag → short', () {
      expect(refundFellShort({'success': true, 'manual': true, 'amount': 300, 'partial': true}, 500), isTrue);
    });
  });
}
