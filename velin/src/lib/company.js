/**
 * Provozovatel (firma) — JEDINÝ zdroj firemních údajů ve Velínu.
 *
 * Zdroj pravdy je `app_settings.company_info` (edituje se ve Státní správa → IČO / DIČ;
 * čtou ho i edge funkce, web a appka). `OPERATOR` jsou jen záložní hodnoty pro případ,
 * že se nastavení nepodaří načíst — nikde jinde ve Velínu firemní údaje natvrdo nepiš.
 *
 * Už VYSTAVENÉ doklady se nepřepisují: každý řádek `invoices` nese vlastního vystavitele
 * v `issuer_snapshot` (plní DB trigger při vystavení) a doklad se VŽDY renderuje z něj
 * (`resolveIssuer`). Smlouvy / VOP / protokoly vystavené před `company_info.valid_from`
 * se otevírají z uloženého souboru (lib/storedDocument.js), ne z dnešní šablony.
 *
 * Importy s příponou `.js` — modul (i lib/invoiceTemplate.js) jde načíst i v čistém Node.
 */
import { supabase } from './supabase.js'

// Tvar = app_settings.company_info (snake_case). Kontakty se změnou provozovatele nemění.
export const OPERATOR = Object.freeze({
  name: 'MotoGo24 s.r.o.',
  ico: '29909864',
  dic: null,
  vat_payer: false,
  address: 'Mezná 9, 393 01 Mezná',
  register: 'zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876',
  register_short: 'C 36876 vedená u Krajského soudu v Českých Budějovicích',
  bank_account: '2303580494/2010',
  bank_iban: 'CZ8320100000002303580494',
  bank_name: 'Fio banka',
  bank_bic: 'FIOBCZPPXXX',
  data_box: '2xfihrd',
  phone: '+420 774 256 271',
  email: 'info@motogo24.cz',
  web: 'https://www.motogo24.cz',
})

export const VAT_NOTE = 'Nejsme plátci DPH.'

// ── Načtení + cache (platí po dobu session; po uložení v CompanyTab se přepíše) ──
let _cache = null
let _pending = null

function asObject(v) {
  if (!v) return null
  if (typeof v === 'string') { try { v = JSON.parse(v) } catch { return null } }
  return v && typeof v === 'object' && !Array.isArray(v) ? v : null
}

/** Aktuální `company_info` z DB. Při chybě vrací kopii OPERATOR (necachuje se — příště se zkusí znovu). */
export async function loadCompanyInfo({ force = false } = {}) {
  if (_cache && !force) return _cache
  if (!_pending) {
    _pending = (async () => {
      try {
        const { data, error } = await supabase.from('app_settings').select('value').eq('key', 'company_info').maybeSingle()
        if (error) throw error
        const v = asObject(data?.value)
        if (v && (v.name || v.ico)) { _cache = v; return v }
      } catch (e) {
        console.warn('[company] company_info se nepodařilo načíst — použity záložní údaje:', e?.message)
      }
      return _cache || { ...OPERATOR }
    })().finally(() => { _pending = null })
  }
  return _pending
}

export function setCompanyInfoCache(value) { _cache = asObject(value) }

/** Synchronní pohled: naposledy načtené `company_info`, jinak OPERATOR. */
export function currentCompany() { return _cache || OPERATOR }

// ── Vystavitel dokladu ──
/**
 * `invoices.issuer_snapshot` / `company_info` → tvar, který tiskne šablona faktury.
 * Tolerantní k chybějícím klíčům (starší snapshoty nemají zápis v OR ani název banky).
 * Vrací null, když snapshot není použitelný (prázdný / bez názvu i IČO).
 */
export function issuerFromSnapshot(snapshot) {
  const s = asObject(snapshot)
  if (!s || !(s.name || s.ico)) return null
  return {
    name: s.name || '',
    address: s.address || '',
    ico: s.ico || '',
    dic: s.dic || null,
    vatPayer: s.vat_payer === true || s.vatPayer === true,
    register: s.register || '',
    registerShort: s.register_short || s.registerShort || '',
    account: s.bank_account || s.account || '',
    iban: s.bank_iban || s.iban || '',
    bank: s.bank_name || s.bank || '',
    phone: s.phone || OPERATOR.phone,
    email: s.email || OPERATOR.email,
    web: s.web || OPERATOR.web,
    dataBox: s.data_box || s.dataBox || '',
    validFrom: s.valid_from || s.validFrom || null,
  }
}

/** Vystavitel podle dnešního nastavení (cache `company_info`), jinak OPERATOR. */
export function currentIssuer() {
  return issuerFromSnapshot(_cache) || issuerFromSnapshot(OPERATOR)
}

/**
 * Kdo je na dokladu dodavatel — pořadí je závazné:
 *   1) `data.supplier` (výslovně předaný), 2) `issuer_snapshot` řádku (doklad vystavený dřív
 *   nese původního provozovatele), 3) aktuální `company_info`, 4) OPERATOR.
 */
export function resolveIssuer(data) {
  const explicit = data && data.supplier
  if (explicit && typeof explicit === 'object' && (explicit.name || explicit.ico)) return explicit
  return issuerFromSnapshot(data && data.issuer_snapshot) || currentIssuer()
}

// ── Zápis v obchodním rejstříku: jedna věta → tvary pro fakturu a patičku e-mailu ──
function parseRegister(register) {
  const m = String(register || '').match(/(Krajsk|Městsk)\S*\s+soud\S*\s+(.+?),\s*oddíl\s+(\S+?),\s*vložka\s+(\d+)/i)
  if (!m) return null
  return { court: `${/^k/i.test(m[1]) ? 'Krajský' : 'Městský'} soud ${m[2].trim()}`, section: m[3], file: m[4] }
}

/** Řádek „Zápis" v bloku DODAVATEL: „obchodní rejstřík, Krajský soud v …, oddíl C, vložka N". */
export function registerInvoiceLine(register) {
  const r = parseRegister(register)
  return r ? `obchodní rejstřík, ${r.court}, oddíl ${r.section}, vložka ${r.file}` : String(register || '').trim()
}

/** Řádek v patičce e-mailu: „C 36876, Krajský soud v …". */
export function registerFooterLine(company = currentCompany()) {
  const r = parseRegister(company?.register)
  return r ? `${r.section} ${r.file}, ${r.court}` : (company?.register_short || '')
}

/** „https://www.motogo24.cz/" → „www.motogo24.cz" */
export function webLabel(web) { return String(web || '').replace(/^https?:\/\//i, '').replace(/\/+$/, '') }

/** IBAN po čtveřicích (CZ83 2010 …). */
export function formatIban(iban) { return String(iban || '').replace(/\s+/g, '').replace(/(.{4})(?=.)/g, '$1 ') }

/** Firemní proměnné pro šablony smluv / VOP / protokolů (stejné názvy jako edge `generate-document`). */
export function companyDocVars(company = currentCompany()) {
  const c = company || OPERATOR
  return {
    company_name: c.name || '', company_address: c.address || '',
    company_ico: c.ico || '', company_dic: c.dic || '',
    company_register: c.register || '',
    company_phone: c.phone || OPERATOR.phone, company_email: c.email || OPERATOR.email,
    company_bank: c.bank_name || '', company_account: c.bank_account || '',
    company_iban: formatIban(c.bank_iban),
  }
}

/**
 * Vznikl dokument PŘED dnešním provozovatelem (`company_info.valid_from`)?
 * Bez `valid_from` (migrace ještě neproběhla / nastavení nejde načíst) vrací false.
 */
export function issuedBeforeSwitch(createdAt, company = currentCompany()) {
  const from = Date.parse(company?.valid_from || '')
  const at = Date.parse(createdAt || '')
  return Number.isFinite(from) && Number.isFinite(at) && at < from
}

// ── Validace (formulář Firemní údaje) ──
/** IČO: 8 číslic, poslední je kontrolní (váhy 8…2, modulo 11). */
export function isValidIco(ico) {
  const s = String(ico || '').trim()
  if (!/^\d{8}$/.test(s)) return false
  let sum = 0
  for (let i = 0; i < 7; i++) sum += Number(s[i]) * (8 - i)
  return (11 - (sum % 11)) % 10 === Number(s[7])
}

/** IBAN: tvar + kontrola mod 97 (ISO 13616). Mezery se ignorují. */
export function isValidIban(iban) {
  const s = String(iban || '').replace(/\s+/g, '').toUpperCase()
  if (!/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/.test(s)) return false
  if (s.startsWith('CZ') && s.length !== 24) return false
  const digits = (s.slice(4) + s.slice(0, 4)).replace(/[A-Z]/g, ch => String(ch.charCodeAt(0) - 55))
  let rem = 0
  for (const d of digits) rem = (rem * 10 + Number(d)) % 97
  return rem === 1
}

/** České číslo účtu „[předčíslí-]číslo/kód banky" → části, jinak null. */
export function parseCzAccount(account) {
  const m = String(account || '').replace(/\s+/g, '').match(/^(?:(\d{1,6})-)?(\d{2,10})\/(\d{4})$/)
  return m ? { prefix: m[1] || '', number: m[2], bankCode: m[3] } : null
}

/** Patří český IBAN k číslu účtu? (QR platba jde na IBAN, na dokladech je číslo účtu — musí být tentýž účet.) */
export function ibanMatchesAccount(iban, account) {
  const s = String(iban || '').replace(/\s+/g, '').toUpperCase()
  const a = parseCzAccount(account)
  if (!a || !s.startsWith('CZ')) return true // zahraniční IBAN / jiný tvar účtu neumíme porovnat
  return s.slice(4) === a.bankCode + a.prefix.padStart(6, '0') + a.number.padStart(10, '0')
}

/**
 * Kontrola formuláře Firemní údaje. Vrací pole českých chybových hlášek (prázdné = v pořádku).
 * Účet, IBAN a název banky se ukládají VŽDY společně — jinak by doklady, QR platba a smlouvy
 * ukazovaly každý jiný účet.
 */
export function validateCompanyInfo(v) {
  const errs = []
  const t = (x) => String(x ?? '').trim()
  if (!t(v.name)) errs.push('Vyplňte název firmy.')
  if (!isValidIco(v.ico)) errs.push('IČO musí mít 8 číslic a platnou kontrolní číslici.')
  if (!t(v.address)) errs.push('Vyplňte sídlo.')
  if (v.vat_payer && !t(v.dic)) errs.push('Plátce DPH musí mít vyplněné DIČ.')
  if (t(v.dic) && !/^[A-Z]{2}[0-9A-Z]{8,12}$/.test(t(v.dic).toUpperCase())) errs.push('DIČ má mít tvar např. CZ12345678.')
  const bank = [t(v.bank_account), t(v.bank_iban), t(v.bank_name)]
  if (bank.some(Boolean) && !bank.every(Boolean)) {
    errs.push('Číslo účtu, IBAN a název banky se ukládají společně — vyplňte všechny tři.')
  } else if (bank.every(Boolean)) {
    if (!parseCzAccount(v.bank_account)) errs.push('Číslo účtu má mít tvar 123456789/2010 (případně s předčíslím 19-123456789/0100).')
    if (!isValidIban(v.bank_iban)) errs.push('IBAN není platný (kontrolní součet nesedí).')
    else if (!ibanMatchesAccount(v.bank_iban, v.bank_account)) errs.push('IBAN neodpovídá číslu účtu — oba údaje musí být tentýž účet.')
  }
  if (t(v.bank_bic) && !/^[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?$/.test(t(v.bank_bic).toUpperCase())) errs.push('BIC (SWIFT) má 8 nebo 11 znaků, např. FIOBCZPPXXX.')
  if (t(v.email) && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(t(v.email))) errs.push('E-mail nemá platný tvar.')
  return errs
}
