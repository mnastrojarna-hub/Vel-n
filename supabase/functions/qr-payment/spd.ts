// QR Platba (SPD) + platební údaje provozovatele pro qr-payment.
// Účet, IBAN i název banky jdou z app_settings.company_info (_shared/company.ts); bez nastavení
// platí výchozí provozovatel. IBAN se nikdy nebere z jiného účtu, než jaký se zákazníkovi vypíše
// (chybí-li bank_iban, dopočítá se z čísla účtu).
import { bankLabel, type Company, COMPANY_DEFAULT } from '../_shared/company.ts'
import { fmtAmount } from './fallback-html.ts'

/** SPD (Short Payment Descriptor) — česká QR Platba. ACC = IBAN, X-VS = jen číslice (max 10). */
export function buildSpd(iban: string, amount: number, vs: string, msg: string): string {
  const parts = ['SPD*1.0', 'ACC:' + iban.replace(/\s+/g, ''), 'AM:' + fmtAmount(amount), 'CC:CZK']
  const num = String(vs || '').replace(/\D/g, '').slice(0, 10)
  if (num) parts.push('X-VS:' + num)
  if (msg) parts.push('MSG:' + msg.slice(0, 60))
  return parts.join('*')
}

/** Platební údaje pro zákazníka: číslo účtu (text), IBAN (QR) a název banky téhož účtu.
 *  Nastavení bez použitelného účtu / IBAN (rozbitý záznam) → celé trio výchozího provozovatele. */
export function qrBankDetails(c: Company): { iban: string; account: string; bank: string } {
  const src = c.account && c.iban ? c : COMPANY_DEFAULT
  return { iban: src.iban.replace(/\s+/g, ''), account: src.account, bank: bankLabel(src) }
}
