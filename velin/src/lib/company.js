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

// ── Načtení + cache ──
// Cache v paměti po dobu session, z DB se obnovuje nejvýš jednou za minutu: změna provozovatele
// (migrace / uložení v CompanyTab jiným uživatelem) se do otevřeného Velína propíše bez reloadu.
const CACHE_TTL_MS = 60_000
let _cache = null
let _cacheAt = 0
let _pending = null

function asObject(v) {
  if (!v) return null
  if (typeof v === 'string') { try { v = JSON.parse(v) } catch { return null } }
  return v && typeof v === 'object' && !Array.isArray(v) ? v : null
}

/**
 * Aktuální `company_info` z DB (surová hodnota, snake_case). Nikdy nevyhodí: při chybě vrací
 * naposledy načtenou hodnotu, jinak kopii OPERATOR (ta se necachuje — příště se zkusí znovu).
 */
export async function loadCompanyInfo({ force = false } = {}) {
  if (_cache && !force && Date.now() - _cacheAt < CACHE_TTL_MS) return _cache
  if (!_pending) {
    _pending = (async () => {
      try {
        const { data, error } = await supabase.from('app_settings').select('value').eq('key', 'company_info').maybeSingle()
        if (error) throw error
        const v = asObject(data?.value)
        if (v && v.name) { _cache = v; _cacheAt = Date.now(); return v }
      } catch (e) {
        console.warn('[company] company_info se nepodařilo načíst — použity záložní údaje:', e?.message)
      }
      return _cache || { ...OPERATOR }
    })().finally(() => { _pending = null })
  }
  return _pending
}

export function setCompanyInfoCache(value) { _cache = asObject(value); _cacheAt = _cache ? Date.now() : 0 }

// ── Vystavitel dokladu ──
const str = (v) => (typeof v === 'string' ? v.trim() : typeof v === 'number' ? String(v) : '')
const bankCode = (account) => (String(account || '').match(/\/(\d{4})\s*$/) || [])[1] || ''

/** České číslo účtu „[předčíslí-]číslo/kód banky" → části, jinak null. */
export function parseCzAccount(account) {
  const m = String(account || '').replace(/\s+/g, '').match(/^(?:(\d{1,6})-)?(\d{2,10})\/(\d{4})$/)
  return m ? { prefix: m[1] || '', number: m[2], bankCode: m[3] } : null
}

/** Český IBAN z čísla účtu; nečitelný vstup = ''. */
export function czIban(account) {
  const a = parseCzAccount(account)
  if (!a) return ''
  const bban = a.bankCode + a.prefix.padStart(6, '0') + a.number.padStart(10, '0')
  let rem = 0
  for (const d of bban + '123500') rem = (rem * 10 + Number(d)) % 97 // „CZ00" = 123500
  return 'CZ' + String(98 - rem).padStart(2, '0') + bban
}

// „zapsaná v obchodním rejstříku vedeném Krajským soudem v X, oddíl C, vložka N" → soud v 1. pádě + spisová značka
function parseRegister(register) {
  const m = String(register || '').match(/(Krajsk|Městsk)\S*\s+soud\S*\s+(.+?),\s*oddíl\s+(\S+?),\s*vložka\s+(\d+)/i)
  if (!m) return null
  return { court: `${/^k/i.test(m[1]) ? 'Krajský' : 'Městský'} soud ${m[2].trim()}`, file: `${m[3]} ${m[4]}` }
}

/**
 * `invoices.issuer_snapshot` / `company_info` → vystavitel ve tvaru, který tisknou šablony
 * (1:1 s edge `_shared/company.ts` → companyFromInfo). Bez názvu = null.
 * Chybějící klíče se z OPERATOR doplňují JEN témuž subjektu (stejné IČO) — doklad dřívějšího
 * provozovatele nikdy nedostane cizí rejstřík, IBAN ani název banky.
 */
export function issuerFromSnapshot(snapshot) {
  const s = asObject(snapshot)
  const name = str(s?.name)
  if (!name) return null
  const ico = str(s.ico)
  const same = !!ico && ico === OPERATOR.ico
  const pick = (key) => str(s[key]) || (same ? OPERATOR[key] || '' : '')
  const account = pick('bank_account')
  const sameBank = !!bankCode(account) && bankCode(account) === bankCode(OPERATOR.bank_account)
  const register = pick('register')
  const reg = parseRegister(register)
  return {
    name, ico, address: pick('address'),
    dic: str(s.dic) || null, vatPayer: s.vat_payer === true,
    register, registerShort: pick('register_short'),
    registerCourt: str(s.register_court) || reg?.court || '', registerFile: str(s.register_file) || reg?.file || '',
    account,
    iban: str(s.bank_iban).replace(/\s+/g, '').toUpperCase() || czIban(account),
    bank: str(s.bank_name) || (sameBank ? OPERATOR.bank_name : ''),
    bic: str(s.bank_bic) || (sameBank ? OPERATOR.bank_bic : ''),
    phone: str(s.phone) || OPERATOR.phone, email: str(s.email) || OPERATOR.email, web: str(s.web) || OPERATOR.web,
    dataBox: pick('data_box'),
    validFrom: str(s.valid_from) || null,
  }
}

/** Vystavitel podle dnešního nastavení (naposledy načtené `company_info`), jinak OPERATOR. Synchronní. */
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

/** Má vystavitel zápis v obchodním rejstříku? (ne = doklad dřívějšího provozovatele → původní podoba) */
export function hasRegister(issuer) { return !!(issuer && (issuer.registerFile || issuer.register)) }

/** Řádek „Zápis" v bloku DODAVATEL: „obchodní rejstřík, Krajský soud v …, oddíl C, vložka N". */
export function registerInvoiceLine(issuer) {
  const m = String(issuer?.registerFile || '').match(/^(\S+)\s+(\S+)$/)
  if (m && issuer.registerCourt) return `obchodní rejstřík, ${issuer.registerCourt}, oddíl ${m[1]}, vložka ${m[2]}`
  return issuer?.register || issuer?.registerShort || ''
}

/** Patička e-mailu / faktury: „C 36876, Krajský soud v …". */
export function registerFooterLine(issuer) {
  return issuer?.registerFile && issuer?.registerCourt ? `${issuer.registerFile}, ${issuer.registerCourt}` : (issuer?.registerShort || '')
}

/** IBAN po čtveřicích (CZ83 2010 …). */
export function formatIban(iban) { return String(iban || '').replace(/\s+/g, '').replace(/(.{4})(?=.)/g, '$1 ') }

/** Název banky pro platební údaje; neznámý název = kód banky (nikdy cizí název). */
export function bankLabel(issuer) {
  const code = bankCode(issuer?.account)
  return issuer?.bank || (code ? `kód banky ${code}` : '')
}

/** Proměnné {{company_*}} pro šablony smluv / VOP / protokolů (stejné názvy jako edge `generate-document`). */
export function companyDocVars(issuer = currentIssuer()) {
  const c = issuer || currentIssuer()
  return {
    company_name: c.name, company_address: c.address, company_ico: c.ico, company_dic: c.dic || '',
    company_register: c.register, company_register_short: c.registerShort,
    company_phone: c.phone, company_email: c.email,
    company_bank: bankLabel(c), company_account: c.account, company_iban: formatIban(c.iban), company_bic: c.bic,
  }
}

/**
 * Vznikl dokument PŘED dnešním provozovatelem (`company_info.valid_from`)?
 * `company` = hodnota z loadCompanyInfo() nebo vystavitel z currentIssuer(). Bez `valid_from`
 * (migrace ještě neproběhla / nastavení nejde načíst) vrací false.
 */
export function issuedBeforeSwitch(createdAt, company = currentIssuer()) {
  const from = Date.parse(company?.valid_from || company?.validFrom || '')
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

/** Patří český IBAN k číslu účtu? (QR platba jde na IBAN, na dokladech je číslo účtu — musí být tentýž účet.) */
export function ibanMatchesAccount(iban, account) {
  const s = String(iban || '').replace(/\s+/g, '').toUpperCase()
  const expected = czIban(account)
  if (!expected || !s.startsWith('CZ')) return true // zahraniční IBAN / jiný tvar účtu neumíme porovnat
  return s === expected
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
