// =============================================================================
// Pobočka s BRÁNOU (Velké Němčice, 2026-10-04) — e-maily s kódy
// =============================================================================
// Na pravém sloupku vrat je HORNÍ schránka s klíčem od visacího zámku brány.
// Zákazník dostává kódy v pořadí 1) brána, 2) šatna (má-li výbavu),
// 3) motorka + stručný postup na pobočce. Platí JEN pro pobočku, která má
// aktivní řádek v `branch_gate_access` (`_branch_gate_code` ≠ NULL, pobočka =
// AKTUÁLNÍ pobočka motorky rezervace). Ostatní pobočky (Mezná) beze změny.
//
// BEZPEČNOST: kód brány patří jen do TĚLA mailu majiteli rezervace — NIKDY
// do předmětu, console/debug_log ani do podkladů pro AI překlad (blok se
// skládá až po překladu šablony). Kód se ukáže jen s vydaným kódem motorky
// (stejné pravidlo jako RPC `get_booking_gate_info`); jinak postup bez čísel.
// =============================================================================
import { GATE_TEXTS_A } from './branch-gate-texts-a.ts';
import { GATE_TEXTS_B } from './branch-gate-texts-b.ts';
/** Typy mailů, do kterých se u pobočky s bránou kódy/postup doplní i bez placeholderu. */ export const GATE_MAIL_TYPES = new Set([
  'booking_reserved',
  'door_codes',
  'booking_modified'
]);
const TEXTS = {
  ...GATE_TEXTS_A,
  ...GATE_TEXTS_B
};
export function gateTexts(lang) {
  return TEXTS[lang] || TEXTS.cs;
}
const esc = (s)=>String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
// Stránka pobočky na webu (fotky + parkoviště): slug dle motogo-web-php/data/pobocky.php,
// prefix dle i18n_slugs.php (I18N_SLUG_PREFIXES['/pobocky/']).
const BRANCH_PAGE_SLUG = {
  '22222222-2222-2222-2222-222222222222': 'velke-nemcice'
};
const BRANCH_PATH = {
  cs: '/pobocky/',
  en: '/branches/',
  de: '/filialen/',
  es: '/sucursales/',
  fr: '/agences/',
  nl: '/filialen/',
  pl: '/oddzialy/',
  uk: '/branches/'
};
export function branchPageUrl(site, lang, branchId) {
  const base = BRANCH_PATH[lang] || BRANCH_PATH.cs;
  const slug = BRANCH_PAGE_SLUG[branchId];
  const path = slug ? base + slug : base.slice(0, -1);
  return site.replace(/\/+$/, '') + path + (lang === 'cs' ? '' : `?lang=${lang}`);
}
/** Modrý box kódů pro pobočku s bránou: brána (+ nápověda) → šatna → motorka. */ export function renderGateCodesBox(lang, base, line, note, gate, gear, moto, lockerDoor) {
  const g = gateTexts(lang);
  const gearLabel = lockerDoor != null ? g.lockerLabelDoor.split('{n}').join(String(lockerDoor)) : base.gear;
  return `
<div style="background:#e0f2fe;border-radius:12px;padding:16px 20px;margin:20px 0;border:1px solid #7dd3fc">
  <h3 style="margin:0 0 12px 0;color:#0c4a6e;font-size:15px">${base.title}</h3>
  ${line(g.gateLabel, gate)}
  <p style="margin:0 0 8px 0;font-size:12px;color:#075985">${esc(g.gateHint)}</p>${gear ? `
  ${line(gearLabel, gear)}` : ''}
  ${line(base.moto, moto || '—')}
  <p style="margin:8px 0 0 0;font-size:12px;color:#075985">${gear ? g.validGear : g.validMoto}</p>${note ? `
  <p style="margin:8px 0 0 0;font-size:13px;font-weight:600;color:#92400e">${note}</p>` : ''}
</div>`;
}
/** Postup na pobočce s bránou. `released` = kód brány smí do mailu (vydaný kód motorky). */ export function renderGateProcedureBlock(lang, o) {
  const t = gateTexts(lang);
  const codeHtml = `<strong style="font-family:'Courier New',monospace;font-size:15px;letter-spacing:2px;color:#0369a1">${esc(o.gate.code)}</strong>`;
  const steps = [
    o.released ? esc(t.step1Code).split('{gate}').join(codeHtml) : esc(t.step1NoCode)
  ];
  if (o.hasGear) {
    steps.push(o.gate.lockerDoor != null ? esc(t.step2GearDoor).split('{n}').join(String(o.gate.lockerDoor)) : esc(t.step2Gear));
    steps.push(esc(t.step3Gear));
  } else {
    steps.push(esc(t.step2NoGear));
  }
  const url = branchPageUrl(o.site, lang, o.gate.branchId);
  return `
<div style="background:#f0faf5;border:1px solid #d4e8e0;border-left:4px solid #74fb71;border-radius:12px;padding:16px 20px;margin:20px 0">
  <h3 style="margin:0 0 10px 0;color:#1a2e22;font-size:15px">${esc(t.procTitle)}</h3>
  <ol style="margin:0;padding:0 0 0 20px;font-size:13px;line-height:1.55;color:#1a2e22">
${steps.map((s)=>`    <li style="margin:0 0 8px 0">${s}</li>`).join('\n')}
    <li style="margin:4px 0 0 0;padding:10px 12px;background:#fff7ed;border:1px solid #fdba74;border-left:4px solid #ea580c;border-radius:8px;color:#7c2d12;font-weight:700">${esc(t.stepImportant)}</li>
  </ol>
  <p style="margin:12px 0 0 0;font-size:13px"><a href="${url}" style="color:#2563eb;font-weight:700">${esc(t.pageLink)}</a></p>
</div>`;
}
/** Brána AKTUÁLNÍ pobočky motorky rezervace (NULL = pobočka bez brány / chyba → mail jako dřív). */ export async function loadBranchGate(supabase, bookingId) {
  try {
    // !moto_id — bookings má i trailer_moto_id (dvě FK na motorcycles).
    const { data: bk } = await supabase.from('bookings').select('moto_id, pickup_method, pickup_address, motorcycles!moto_id(branch_id)').eq('id', bookingId).maybeSingle();
    // Přistavení na adresu = zákazník na pobočku nejede → bez brány (stejné pravidlo
    // jako appka ResPickupProcedure a web /potvrzeni `is_delivery`).
    if (bk?.pickup_method === 'delivery' || String(bk?.pickup_address || '').trim()) return null;
    const m = Array.isArray(bk?.motorcycles) ? bk.motorcycles[0] : bk?.motorcycles;
    const branchId = m?.branch_id ? String(m.branch_id) : '';
    if (!branchId) return null;
    const { data: code, error } = await supabase.rpc('_branch_gate_code', {
      p_branch_id: branchId
    });
    if (error || !code) return null;
    let lockerDoor = null;
    try {
      const { data: n, error: e2 } = await supabase.rpc('_branch_locker_door_no', {
        p_branch_id: branchId
      });
      if (!e2 && n != null && Number.isFinite(Number(n))) lockerDoor = Number(n);
    } catch  {}
    return {
      branchId,
      code: String(code),
      lockerDoor
    };
  } catch  {
    return null;
  }
}
/** Má rezervace nárok na šatnu? (kódy zatím nevydané) — RPC booking_needs_locker, fallback řádky kódů. */ export async function loadNeedsLocker(supabase, bookingId, rows) {
  try {
    const { data, error } = await supabase.rpc('booking_needs_locker', {
      p_booking_id: bookingId
    });
    if (!error && data != null) return data === true;
  } catch  {}
  return rows.length ? rows.some((c)=>c.code_type === 'accessories') : true;
}
