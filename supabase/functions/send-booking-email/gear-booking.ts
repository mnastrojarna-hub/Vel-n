// ===== Výpůjčka JEN výbavy jako rezervace (bookings.booking_kind='gear', 2026-10-23) =====
// index.ts volá prepareGearMail() pro každý mail s booking_id. Gear rezervace:
//  - renderType = gear_<typ> (Velín šablona; web_ varianta má přednost), logovaný slug dle `type`;
//  - proměnné výbavy v jazyce zákazníka (_shared/email-gear.ts) + {{door_codes_block}} JEN
//    šatna (+ brána a postup na displeji samoobsluhy) — nikdy „Kód motorky“, žádná výzva k ŘP;
//  - přílohy z VLASTNÍ gear šablony (i když renderType ≠ type), „Smlouva“ = smlouva o nájmu výbavy;
//  - chybí-li gear šablona → minimální CZ/EN gear fallback + debug_log email_template_fallback.
// Motorkové rezervace: prepareGearMail vrátí null a index.ts běží beze změny.
import { substitute } from './i18n.ts';
import { branchPageUrl, loadGateForBranch } from './branch-gate.ts';
import { buildGearVars, gearRenderType, gearSubjectVars, loadGearBooking } from '../_shared/email-gear.ts';
import { renderGearDoorCodesBlock } from '../_shared/email-gear-blocks.ts';
import { gearFallbackLang, gearFallbackTemplate, gearFallbackVars } from '../_shared/email-gear-fallback.ts';
/** Vydaný kód šatny (accessories, odeslaný zákazníkovi, nezadržený); '' = kódy zatím nejsou. */ export function releasedLockerCode(rows) {
  return rows.find((c)=>c.code_type === 'accessories' && c.sent_to_customer === true && !c.withheld_reason)?.door_code || '';
}
export async function prepareGearMail(supabase, o) {
  const g = await loadGearBooking(supabase, o.bookingId, o.payload?.booking_kind);
  if (!g) return null;
  const code = releasedLockerCode(o.doorCodeRows);
  const self = g.branch?.type === 'samoobslužná';
  // Brána + č. dveří šatny jen s vydaným kódem šatny (jako get_booking_gate_info pro gear).
  let gateCode = '', lockerDoor = null, gateBranch = '';
  if (code && g.branch?.id) {
    const gate = await loadGateForBranch(supabase, g.branch.id);
    if (gate) {
      gateCode = gate.code;
      lockerDoor = gate.lockerDoor;
      gateBranch = gate.branchId;
    } else if (self) {
      try {
        const { data: n, error } = await supabase.rpc('_branch_locker_door_no', {
          p_branch_id: g.branch.id
        });
        if (!error && n != null && Number.isFinite(Number(n))) lockerDoor = Number(n);
      } catch  {}
    }
  }
  const varsFor = (l)=>({
      ...buildGearVars(g, l, {
        site: o.site,
        customerName: o.customerName,
        payload: o.payload
      }),
      door_codes_block: renderGearDoorCodesBlock(l, {
        code,
        gate: gateCode,
        lockerDoor,
        selfService: self,
        branchName: g.branch?.name || '',
        pageUrl: gateBranch ? branchPageUrl(o.site, l, gateBranch) : ''
      }),
      // Kódy výpůjčky výbavy nejsou kódy motorky — motorkové proměnné prázdné.
      door_code_moto: '',
      door_code_gear: code,
      motorcycle: '',
      original_motorcycle: ''
    });
  return {
    booking: g,
    renderType: gearRenderType(o.renderType),
    varsFor,
    subjectVars: (v)=>gearSubjectVars(v, g, o.customerName)
  };
}
/** Gear šablona ve Velínu chybí → minimální CZ/EN gear text (nikdy motorkový). Ostatní jazyky dostanou
 *  anglický text i s proměnnými výbavy v angličtině (odkazy dál v jazyce zákazníka); `lang` = jazyk
 *  textu, `vars` = proměnné, se kterými se text vyplnil (volající je převezme, ať se blok kódů nepřidá 2×). */ export function gearFallbackRender(gm, lang, vars) {
  const L = gearFallbackLang(lang);
  const v = gearFallbackVars(lang, vars, gm.varsFor);
  const tpl = gearFallbackTemplate(gm.renderType, L, v);
  return {
    subject: substitute(tpl.subject, gm.subjectVars(v)),
    body: substitute(tpl.body, v),
    lang: L,
    vars: v
  };
}
