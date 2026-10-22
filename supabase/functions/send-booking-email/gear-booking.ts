// ===== Výpůjčka JEN výbavy jako rezervace (bookings.booking_kind='gear', 2026-10-23) =====
// index.ts volá prepareGearMail() pro každý mail s booking_id. Gear rezervace:
//  - renderType = gear_<typ> (Velín šablona; web_ varianta má přednost), logovaný slug dle `type`;
//  - proměnné výbavy v jazyce zákazníka (_shared/email-gear.ts) + {{door_codes_block}} JEN
//    šatna (+ brána a postup na displeji samoobsluhy) — nikdy „Kód motorky“, žádná výzva k ŘP;
//  - přílohy z VLASTNÍ gear šablony (i když renderType ≠ type), „Smlouva“ = smlouva o nájmu výbavy;
//  - chybí-li gear šablona → minimální CZ/EN gear fallback + debug_log email_template_fallback.
// Motorkové rezervace: prepareGearMail vrátí null a index.ts běží beze změny.
import { substitute, type Lang } from './i18n.ts'
import { branchPageUrl, loadGateForBranch } from './branch-gate.ts'
import { buildGearVars, gearRenderType, gearSubjectVars, loadGearBooking, type GearBooking } from '../_shared/email-gear.ts'
import { renderGearDoorCodesBlock } from '../_shared/email-gear-blocks.ts'
import { gearFallbackTemplate } from '../_shared/email-gear-fallback.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
type CodeRow = { code_type: string; door_code: string; sent_to_customer: boolean; withheld_reason: string | null }

export interface GearMail {
  booking: GearBooking
  renderType: string
  /** Všechny gear proměnné v jazyce `l` (odkazy vždy na doménu zákazníka). */
  varsFor: (l: Lang) => Record<string, string>
  subjectVars: (v: Record<string, string>) => Record<string, string>
}

export interface GearMailOpts {
  bookingId: string; renderType: string; site: string; customerName?: string
  payload: Record<string, unknown>; doorCodeRows: CodeRow[]
}

/** Vydaný kód šatny (accessories, odeslaný zákazníkovi, nezadržený); '' = kódy zatím nejsou. */
export function releasedLockerCode(rows: CodeRow[]): string {
  return rows.find((c) => c.code_type === 'accessories' && c.sent_to_customer === true && !c.withheld_reason)?.door_code || ''
}

export async function prepareGearMail(supabase: Sb, o: GearMailOpts): Promise<GearMail | null> {
  const g = await loadGearBooking(supabase, o.bookingId)
  if (!g) return null
  const code = releasedLockerCode(o.doorCodeRows)
  const self = g.branch?.type === 'samoobslužná'
  // Brána + č. dveří šatny jen s vydaným kódem šatny (jako get_booking_gate_info pro gear).
  let gateCode = '', lockerDoor: number | null = null, gateBranch = ''
  if (code && g.branch?.id) {
    const gate = await loadGateForBranch(supabase, g.branch.id)
    if (gate) { gateCode = gate.code; lockerDoor = gate.lockerDoor; gateBranch = gate.branchId }
    else if (self) {
      try {
        const { data: n, error } = await supabase.rpc('_branch_locker_door_no', { p_branch_id: g.branch.id })
        if (!error && n != null && Number.isFinite(Number(n))) lockerDoor = Number(n)
      } catch { /* bez čísla dveří */ }
    }
  }
  const varsFor = (l: Lang) => ({
    ...buildGearVars(g, l, { site: o.site, customerName: o.customerName, payload: o.payload }),
    door_codes_block: renderGearDoorCodesBlock(l, {
      code, gate: gateCode, lockerDoor, selfService: self, branchName: g.branch?.name || '',
      pageUrl: gateBranch ? branchPageUrl(o.site, l, gateBranch) : '',
    }),
    // Kódy výpůjčky výbavy nejsou kódy motorky — motorkové proměnné prázdné.
    door_code_moto: '', door_code_gear: code, motorcycle: '', original_motorcycle: '',
  })
  return {
    booking: g,
    renderType: gearRenderType(o.renderType),
    varsFor,
    subjectVars: (v) => gearSubjectVars(v, g, o.customerName),
  }
}

/** Gear šablona ve Velínu chybí → minimální CZ/EN gear text (nikdy motorkový). */
export function gearFallbackRender(gm: GearMail, lang: Lang, vars: Record<string, string>): { subject: string; body: string } {
  const tpl = gearFallbackTemplate(gm.renderType, lang, vars)
  return { subject: substitute(tpl.subject, gm.subjectVars(vars)), body: substitute(tpl.body, vars) }
}
