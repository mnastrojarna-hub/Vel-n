-- =============================================================================
-- MIGRACE 2026-07-14: zrušit trg_qr_payment_receipt (dubloval by potvrzení platby)
-- =============================================================================
-- Fix (report z testu): u QR/převodu dorazil `web_booking_reserved` (komplet) DŘÍV,
-- než zákazník vyplnil čísla dokladů. Příčina: ruční potvrzení platby ve Velíně
-- (`BookingDetail.confirmManualPayment`) posílalo `booking_reserved` NEPODMÍNĚNĚ a
-- navíc se dublovalo s triggerem `trg_qr_payment_receipt` (20260710).
--
-- Oprava (frontend Velín): `confirmManualPayment` nově větví jako webhook — WEB rezervace
-- s nedokončenými doklady dostane jen `invoice_payment_receipt` (web_ šablona, ZF+DP);
-- kompletní `web_booking_reserved` (smlouva+VOP+kódy) dorazí až po dokladech (reserved cron).
-- Ruční potvrzení QR/převodu jde VŽDY přes tuto UI cestu → DB trigger je nadbytečný a
-- způsoboval dvojí mail. Rušíme ho. (Reserved/missing_docs cron dál jistí doručení.)
-- =============================================================================

DROP TRIGGER IF EXISTS trg_qr_payment_receipt ON public.bookings;
DROP FUNCTION IF EXISTS public.trg_send_qr_payment_receipt();

NOTIFY pgrst, 'reload schema';
