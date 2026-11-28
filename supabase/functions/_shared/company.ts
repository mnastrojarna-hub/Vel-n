// ===== _shared/company.ts =====
// Provozovatel (vystavitel dokladů) — JEDINÝ zdroj pro všechny edge funkce.
// Zdroj pravdy = app_settings.company_info; COMPANY_DEFAULT (aktuální provozovatel) platí jen když
// nastavení chybí / nejde načíst, a doplňuje chybějící klíče TÉHOŽ subjektu (stejné IČO).
// Nastavení / snapshot JINÉHO subjektu se z výchozích hodnot nedoplňuje — jeho doklad nikdy nenese
// cizí rejstřík, IBAN ani název banky (IBAN se dopočítá z čísla účtu).
// Už vystavené doklady: invoices.issuer_snapshot (kopie company_info v okamžiku vystavení, plní DB
// trigger; dobropis dědí vystavitele opravovaného dokladu) → issuerOf(). Chybí-li snapshot (sloupec
// ještě neexistuje / NULL), platí aktuální company_info.
// deno-lint-ignore-file no-explicit-any
export const COMPANY_DEFAULT = Object.freeze({
  name: 'MotoGo24 s.r.o.',
  address: 'Mezná 9, 393 01 Mezná',
  ico: '29909864',
  dic: null,
  vatPayer: false,
  register: 'zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876',
  registerShort: 'C 36876 vedená u Krajského soudu v Českých Budějovicích',
  registerCourt: 'Krajský soud v Českých Budějovicích',
  registerFile: 'C 36876',
  account: '2303580494/2010',
  iban: 'CZ8320100000002303580494',
  bank: 'Fio banka',
  bic: 'FIOBCZPPXXX',
  phone: '+420 774 256 271',
  email: 'info@motogo24.cz',
  web: 'www.motogo24.cz',
  dataBox: '2xfihrd',
  validFrom: null
});
const str = (v)=>typeof v === 'string' ? v.trim() : typeof v === 'number' ? String(v) : '';
const esc = (s)=>String(s ?? '').replace(/[&<>]/g, (c)=>({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;'
    })[c]);
const bankCode = (account)=>(account.match(/\/(\d{4})\s*$/) || [])[1] || '';
/** „…vedeném Krajským soudem v X, oddíl C, vložka N“ → soud v 1. pádě + spisová značka „C N“
 *  (stejné pravidlo jako Velín lib/company.js — v nastavení se udržuje jen jedna věta `register`). */ export function parseRegister(register) {
  const m = String(register || '').match(/(Krajsk|Městsk)\S*\s+soud\S*\s+(.+?),\s*oddíl\s+(\S+?),\s*vložka\s+(\d+)/i);
  if (!m) return {
    court: '',
    file: ''
  };
  return {
    court: `${/^k/i.test(m[1]) ? 'Krajský' : 'Městský'} soud ${m[2].trim()}`,
    file: `${m[3]} ${m[4]}`
  };
}
/** Český IBAN z čísla účtu „[předčíslí-]číslo/kód banky“; nečitelný vstup = ''. */ export function czIban(account) {
  const m = String(account || '').replace(/\s+/g, '').match(/^(?:(\d{1,6})-)?(\d{2,10})\/(\d{4})$/);
  if (!m) return '';
  const bban = m[3] + (m[1] || '').padStart(6, '0') + m[2].padStart(10, '0');
  return 'CZ' + String(98n - BigInt(bban + '123500') % 97n).padStart(2, '0') + bban;
}
export const fmtIban = (iban)=>String(iban || '').replace(/\s+/g, '').replace(/(.{4})/g, '$1 ').trim();
/** company_info / issuer_snapshot (jsonb, i jako text) → Company; bez názvu = null. */ export function companyFromInfo(info) {
  let v = info;
  if (typeof v === 'string') {
    try {
      v = JSON.parse(v);
    } catch  {
      return null;
    }
  }
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null;
  const name = str(v.name);
  if (!name) return null;
  const ico = str(v.ico);
  const D = COMPANY_DEFAULT;
  const same = !!ico && ico === D.ico // týž subjekt → chybějící klíče z výchozích
  ;
  const pick = (key, d)=>str(v[key]) || (same ? d : '');
  const account = pick('bank_account', D.account);
  const sameBank = !!bankCode(account) && bankCode(account) === bankCode(D.account);
  const register = pick('register', D.register);
  const reg = parseRegister(register);
  return {
    name,
    ico,
    address: pick('address', D.address),
    dic: str(v.dic) || null,
    vatPayer: v.vat_payer === true,
    register,
    registerShort: pick('register_short', register === D.register ? D.registerShort : ''),
    registerCourt: reg.court,
    registerFile: reg.file,
    account,
    iban: str(v.bank_iban).replace(/\s+/g, '').toUpperCase() || czIban(account) || (account === D.account ? D.iban : ''),
    bank: str(v.bank_name) || (sameBank ? D.bank : ''),
    bic: str(v.bank_bic) || (sameBank ? D.bic : ''),
    phone: str(v.phone) || D.phone,
    email: str(v.email) || D.email,
    web: str(v.web) || D.web,
    dataBox: pick('data_box', D.dataBox),
    validFrom: str(v.valid_from) || null
  };
}
let current = COMPANY_DEFAULT;
/** Provozovatel z posledního loadCompany() (bez dotazu) — pro synchronní skládání patiček. */ export const companyNow = ()=>current;
/** Aktuální provozovatel z app_settings.company_info. Nikdy nevyhodí. Chybějící řádek, řádek bez
 *  názvu nebo chyba dotazu = COMPANY_DEFAULT — NIKDY dříve načtená hodnota (běžící instance si
 *  nesmí po chybě dotazu podržet provozovatele / účet, který mezitím přestal platit). */ export async function loadCompany(supabase) {
  let c = null;
  try {
    const { data, error } = await supabase.from('app_settings').select('value').eq('key', 'company_info').limit(1);
    if (error) console.warn('[company] company_info:', error.message);
    else c = companyFromInfo(Array.isArray(data) ? data[0]?.value : data?.value);
  } catch (e) {
    console.warn('[company] company_info nedostupné:', e.message);
  }
  current = c || COMPANY_DEFAULT;
  return current;
}
/** Vystavitel KONKRÉTNÍHO dokladu: snapshot řádku invoices, jinak aktuální provozovatel. */ export function issuerOf(row, fallback = current) {
  const snap = row && typeof row === 'object' ? row.issuer_snapshot : null;
  return companyFromInfo(snap) || fallback;
}
/** Vystavitel uložený u dokladu `invoiceId` (null = doklad / snapshot není).
 *  select('*') → nespadne, dokud sloupec issuer_snapshot neexistuje. */ export async function invoiceIssuer(supabase, invoiceId) {
  if (!invoiceId) return null;
  try {
    const { data, error } = await supabase.from('invoices').select('*').eq('id', invoiceId).limit(1);
    const row = !error && Array.isArray(data) ? data[0] : null;
    return row ? companyFromInfo(row.issuer_snapshot) : null;
  } catch  {
    return null;
  }
}
/** „C 36876, Krajský soud v Českých Budějovicích“ (patička e-mailu, patička faktury). */ export function registerLine(c) {
  return c.registerFile && c.registerCourt ? `${c.registerFile}, ${c.registerCourt}` : c.registerShort || '';
}
/** „obchodní rejstřík, Krajský soud v …, oddíl C, vložka 36876“ (blok DODAVATEL na faktuře). */ export function registerInvoiceLine(c) {
  const m = String(c.registerFile || '').match(/^(\S+)\s+(\S+)$/);
  if (m && c.registerCourt) return `obchodní rejstřík, ${c.registerCourt}, oddíl ${m[1]}, vložka ${m[2]}`;
  return c.register || c.registerShort || '';
}
/** Název banky pro platební údaje; neznámý název = kód banky (nikdy cizí název). */ export function bankLabel(c) {
  const code = bankCode(String(c.account || ''));
  return c.bank || (code ? `kód banky ${code}` : '');
}
/** Identifikační řádky patičky e-mailu (název / sídlo / IČO / zápis) — vzhled 1:1 se všemi šablonami. */ export function emailFooterCompanyHtml(c = current) {
  const reg = registerLine(c);
  return `<div style="font-size:14px;font-weight:800;color:#ffffff;margin-bottom:6px">${esc(c.name)}</div>
          <div style="color:#9ca3af">${esc(c.address)}</div>
          <div style="color:#9ca3af">IČO: ${esc(c.ico)}</div>${reg ? `
          <div style="color:#9ca3af">${esc(reg)}</div>` : ''}`;
}
/** „Název · IČO: … · sídlo · C … vedená u …“ — krátká patička dokumentů (bez kontaktů). */ export function companyFooterLine(c = current) {
  return [
    c.name,
    c.ico ? `IČO: ${c.ico}` : '',
    c.address,
    c.registerShort
  ].filter(Boolean).map(esc).join(' · ');
}
/** „Název, IČO: …“ (+ sídlo) — strojové / interní texty (datová schránka, AI). */ export function companyIdLine(c = current, withAddress = false) {
  return [
    c.name,
    c.ico ? `IČO: ${c.ico}` : '',
    withAddress ? c.address : ''
  ].filter(Boolean).join(', ');
}
/** Proměnné {{company_*}} pro dokumenty ze šablon (generate-document). */ export function companyDocVars(c) {
  return {
    company_name: c.name,
    company_address: c.address,
    company_ico: c.ico,
    company_dic: c.dic || '',
    company_register: c.register,
    company_register_short: c.registerShort,
    company_phone: c.phone,
    company_email: c.email,
    company_bank: bankLabel(c),
    company_account: c.account,
    company_iban: fmtIban(c.iban),
    company_bic: c.bic
  };
}
