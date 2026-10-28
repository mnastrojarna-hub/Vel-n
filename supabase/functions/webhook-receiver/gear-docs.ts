// ===== webhook-receiver/gear-docs.ts =====
// Stav dokladů po zaplacení webové rezervace → volba potvrzovacího mailu (webhook Stripe,
// fio-sync, fallback ověření 0 Kč session v process-payment). Výpůjčka JEN výbavy
// (booking_kind = 'gear', DESIGN-GEAR §3.4, 2026-10-23) potřebuje jen doklad totožnosti
// (OP obě strany nebo pas) + věk 18+, žádný řidičák → stav se počítá PER REZERVACE
// (`check_booking_docs_status_for`). Dřívější `check_booking_docs_status(user, konec, moto)`
// by u gear vzal libovolnou rezervaci téhož dne a motorkovou bránu s ŘP → gear zákazník
// by vždy dostal „nahraj doklady“ (ŘP). Motorka beze změny.
// Stejný kontrakt obou RPC: NULL = doklady v pořádku, text = co chybí.
// deno-lint-ignore no-explicit-any
/** booking_kind z DB tolerantně: chyba / chybějící sloupec (SQL ještě nenasazené) = motorka. */ export async function bookingKindOf(sb, bookingId) {
  if (!bookingId) return 'moto';
  try {
    const { data, error } = await sb.from('bookings').select('booking_kind').eq('id', bookingId).maybeSingle();
    return !error && data?.booking_kind === 'gear' ? 'gear' : 'moto';
  } catch  {
    return 'moto';
  }
}
/**
 * Doklady k rezervaci v pořádku? Gear = `check_booking_docs_status_for(p_booking_id)`
 * (jen totožnost + 18+), motorka = `check_booking_docs_status` jako dřív. `kind` může volající
 * předat (řádek už booking_kind má); jinak se dohledá. Výjimka = NE (jako dřív). Gear: chyba
 * RPC / chybějící funkce = NE (bezpečně: potvrzení platby s výzvou k dokladu, kompletní mail
 * pošle cron send_missing_booking_reserved_emails). Motorka beze změny proti dřívějšku:
 * chyba RPC vrací data null = „v pořádku“.
 */ export async function bookingDocsOk(sb, b, kind) {
  try {
    const k = kind ?? (b.booking_kind === 'gear' ? 'gear' : b.booking_kind ? 'moto' : await bookingKindOf(sb, b.id));
    if (k === 'gear') {
      const { data, error } = await sb.rpc('check_booking_docs_status_for', {
        p_booking_id: b.id
      });
      return !error && (data === null || data === undefined);
    }
    const { data: ds } = await sb.rpc('check_booking_docs_status', {
      p_user_id: b.user_id,
      p_end_date: String(b.end_date || '').slice(0, 10),
      p_moto_id: b.moto_id
    });
    return ds === null || ds === undefined;
  } catch  {
    return false;
  }
}
/** Potvrzovací mail po zaplacení: web + chybějící doklady → `invoice_payment_receipt`, jinak `booking_reserved`
 *  (send-booking-email u gear rezervace sám vybere šablonu `gear_*`). `docsCompleted` = docs_completed_at (fio-sync). */ export async function paidMailType(sb, b, source, kind) {
  if (source !== 'web') return 'booking_reserved';
  if (b.docs_completed_at) return 'booking_reserved';
  return await bookingDocsOk(sb, b, kind) ? 'booking_reserved' : 'invoice_payment_receipt';
}
