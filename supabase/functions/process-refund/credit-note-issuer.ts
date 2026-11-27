// Vystavitel dobropisu = vystavitel dokladu, který dobropis opravuje (ne dnešní provozovatel).
// Pořadí: issuer_snapshot řádku dobropisu (DB trigger ho při vložení zdědí z původního dokladu) →
// issuer_snapshot původního dokladu → aktuální app_settings.company_info. Dotazy jsou select('*'),
// takže fungují i dokud sloupec issuer_snapshot neexistuje (pak = aktuální provozovatel).
// deno-lint-ignore-file no-explicit-any
import { type Company, companyNow, invoiceIssuer, loadCompany, registerLine } from '../_shared/company.ts'

export async function creditNoteIssuer(
  supabase: any,
  a: { creditNoteId?: string | null; originalInvoiceId?: string | null },
): Promise<Company> {
  return (await invoiceIssuer(supabase, a.creditNoteId))
    || (await invoiceIssuer(supabase, a.originalInvoiceId))
    || (await loadCompany(supabase))
}

const esc = (s: unknown) => String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c] as string))

/** Pravý blok hlavičky dobropisu (značka + název, sídlo, IČO, zápis v rejstříku vystavitele). */
export function creditNoteIssuerHtml(issuer?: Company | null): string {
  const c = issuer || companyNow()
  const reg = registerLine(c)
  return `<div style="text-align:right">
    <div style="font-size:18px;font-weight:800">MotoGo24</div>
    <div style="color:#4a5a52">${esc(c.name)}</div>
    <div style="color:#4a5a52">${esc(c.address)}</div>
    <div style="color:#4a5a52">IČO: ${esc(c.ico)}</div>${reg ? `
    <div style="color:#4a5a52">${esc(reg)}</div>` : ''}
  </div>`
}
