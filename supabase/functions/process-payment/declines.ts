// ===== process-payment/declines.ts =====
// D5 (2026-10-16): zamítnutí karty (off-session / uložená karta) → český text bez
// kontaktů pro appku ≤ 4.1.3 (zobrazuje `message`). Ztracená / odcizená / zadržená
// karta = obecné bezpečné znění. Každý text říká, že se nic nestrhlo, a co dělat.
// ── Zamítnutí uložené karty (off-session) — český `message` pro appku ≤ 4.1.3 ──
const DECLINE_GROUPS: Array<[string[], string]> = [
  [['insufficient_funds'], 'Banka platbu zamítla, protože na kartě není dost peněz. Dobij si účet, nebo zaplať jinou kartou. Nic jsme nestrhli.'],
  [['expired_card'], 'Platnost karty vypršela. Zaplať prosím jinou kartou. Nic jsme nestrhli.'],
  [['incorrect_cvc', 'invalid_cvc'], 'Bezpečnostní kód (CVC) karty nesouhlasí. Zkontroluj ho na zadní straně karty a zkus to znovu. Nic jsme nestrhli.'],
  [['incorrect_number', 'invalid_number'], 'Číslo karty nesouhlasí. Zkontroluj ho a zkus to znovu. Nic jsme nestrhli.'],
  [['invalid_expiry_month', 'invalid_expiry_year'], 'Datum platnosti karty nesouhlasí. Zkontroluj ho a zkus to znovu. Nic jsme nestrhli.'],
  [['card_not_supported'], 'Tahle karta tenhle typ platby nepodporuje. Zaplať prosím jinou kartou. Nic jsme nestrhli.'],
  [['currency_not_supported'], 'Tvoje karta neumí platit v českých korunách (CZK). Zaplať prosím jinou kartou – většina karet Visa a Mastercard to umí. Nic jsme nestrhli.'],
  [['card_velocity_exceeded', 'withdrawal_count_limit_exceeded'], 'Na kartě je vyčerpaný limit plateb. Zvyš si limit v aplikaci své banky, nebo zaplať jinou kartou. Nic jsme nestrhli.'],
  [['card_decline_rate_limit_exceeded'], 'Tahle karta byla zamítnutá příliš mnohokrát za sebou. Zaplať prosím jinou kartou, nebo to zkus zítra. Nic jsme nestrhli.'],
  [['incorrect_pin', 'invalid_pin', 'pin_try_exceeded', 'offline_pin_required', 'online_or_offline_pin_required'],
    'Banka u téhle platby vyžaduje PIN, který online zadat nejde. Zaplať prosím jinou kartou. Nic jsme nestrhli.'],
  [['issuer_not_available', 'try_again_later', 'reenter_transaction', 'processing_error'],
    'Banka teď platbu nezpracovala. Nic jsme nestrhli – zkus to prosím za chvíli znovu.'],
  [['authentication_required', 'payment_intent_authentication_failure', 'setup_intent_authentication_failure'],
    'Platbu je potřeba potvrdit v aplikaci banky (3D Secure) a to se nepodařilo. Nic jsme nestrhli – zkus to znovu a platbu v bance potvrď.'],
  [['duplicate_transaction'], 'Banka platbu odmítla jako duplicitní – stejnou částku jsi zřejmě právě zaplatil(a). Ověřujeme, jestli předchozí platba prošla – neplať prosím znovu.'],
  [['resource_missing', 'payment_method_unactivated', 'payment_method_not_available', 'payment_method_customer_decline'],
    'Uloženou kartu teď nejde použít. Zaplať prosím jinou kartou. Nic jsme nestrhli.'],
  [['payment_intent_payment_attempt_expired'], 'Banka platbu nepotvrdila včas, takže vypršela. Nic jsme nestrhli – zkus to prosím znovu.'],
  [['amount_too_small'], 'Kartou jde zaplatit nejméně 15 Kč. Aktualizuj prosím aplikaci MotoGo24 a zkus to znovu. Nic jsme nestrhli.'],
]
// Ztracená / odcizená / zadržená karta a všechna ostatní zamítnutí = obecné bezpečné znění.
const DECLINE_GENERIC = 'Tvoje banka tuhle platbu neschválila. Kartu obvykle odblokuješ v aplikaci své banky – pak to zkus znovu, nebo zaplať jinou kartou. Nic jsme nestrhli.'

/** Český text zamítnutí podle decline_code (přednost) nebo Stripe code. */
export function declineMessageCs(code: string | null | undefined, decline: string | null | undefined): string {
  for (const key of [decline, code]) {
    if (!key) continue
    for (const [codes, text] of DECLINE_GROUPS) if (codes.includes(key)) return text
  }
  return DECLINE_GENERIC
}
