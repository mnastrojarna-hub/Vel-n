// ===== ai-moto-agent/gear-context.ts =====
// KONTEXT REZERVACE pro výpůjčku JEN VÝBAVY (bookings.booking_kind='gear', 2026-10-23).
// Dřív agent u rezervace bez motorky psal „detaily motorky se nepodařilo načíst“ a
// pobočka se ztratila (bere se z motorky). Pobočka = bookings.branch_id (embed
// `gear_branch`, viz customer-branch.ts preferBookingBranch). Bez motorky, kóje,
// km, tankování/mytí a SOS. Sdílí appka (index.ts) i agent zpráv ve Velínu.

import { GATE_BRANCH_NOTE_CS } from '../_shared/agent-knowledge/branch-gate.ts'
import { GEAR_RENTAL_TITLE } from '../_shared/agent-knowledge/gear-rental.ts'
import { gearBookingLabel, gearBranchOf, gearItemsCs, isGearBooking } from '../_shared/agent-knowledge/gear-booking.ts'

type Row = Record<string, unknown>

export { isGearBooking }

/** Řádky pobočky výpůjčky výbavy (režim výdeje/vrácení výbavy, ne motorky). */
export function formatGearBranchLines(br: Row | null): string {
  if (!br) return '- Pobočka: nepodařilo se načíst (použij get_branches)'
  const addr = [br.address, br.city].filter(Boolean).join(', ')
  const ss = br.type === 'samoobslužná'
  const lines = [
    `- Pobočka rezervace: ${br.name || addr || '?'}${addr ? ` — ${addr}` : ''}`,
    `- Režim pobočky: ${ss
      ? 'SAMOOBSLUŽNÁ — výdej i vrácení výbavy 24/7 kódem ŠATNY (jiný kód k rezervaci není), velikosti + podpis protokolu na displeji, podpis potvrdí tímtéž kódem'
      : br.type === 'obslužná'
        ? 'OBSLUŽNÁ — NONSTOP: výbavu předá a převezme OBSLUHA osobně v čase z rezervace; doklad totožnosti zkontroluje na místě'
        : 'typ neuveden — režim ověř přes get_branches'}`,
  ]
  if (br.phone) lines.push(`- Telefon pobočky: ${br.phone}`)
  if (br.gps_lat && br.gps_lng) lines.push(`- GPS pobočky: ${br.gps_lat}, ${br.gps_lng}`)
  if (br.notes) lines.push(`- Poznámka k pobočce: ${br.notes}`)
  if (br.has_gate === true) lines.push(`- ${GATE_BRANCH_NOTE_CS} (u výpůjčky výbavy pořadí brána → šatna; kód motorky neexistuje).`)
  lines.push(ss
    ? '- Vrácení: kdykoli 24/7 do konce posledního dne — tentýž kód šatny, výbavu vrátit do šatny, ZAVŘÍT dveře, na displeji „Vracíš všechnu výbavu?“ → Ano = výpůjčka se hned ukončí (kód ještě ~15 min po zavření šatny platí); Ne = nic se neukončí.'
    : '- Vrácení: obsluze na pobočce v čase z rezervace (NONSTOP).')
  return lines.join('\n')
}

/** Kontext jedné výpůjčky výbavy (+ případné další rezervace zákazníka). */
export function formatGearBookingContext(b: Row, others: Row[] | null, otherLabel: (o: Row) => string): string {
  const ref = String(b.id || '').slice(-8).toUpperCase()
  const picked = b.status === 'active' || !!b.handover_protocol_filled_at || !!b.picked_up_at
  const days = Math.round((Date.parse(String(b.end_date).slice(0, 10) + 'T12:00:00Z') - Date.parse(String(b.start_date).slice(0, 10) + 'T12:00:00Z')) / 86400000) + 1
  let ctx = `\n\n## KONTEXT REZERVACE (reálná data z DB — toto je PRAVDA):
- Rezervace #${ref} — VÝPŮJČKA VÝBAVY BEZ MOTORKY (zákazník u nás v této rezervaci NEMÁ motorku)
- Stav: ${b.status} | Stav platby: ${b.payment_status || '?'}
- Výbava (velikosti): ${gearItemsCs(b)}
- Cena výbavy za den: ${b.gear_per_day ?? '?'} Kč | Celkem: ${b.total_price ?? '?'} Kč${Number.isFinite(days) && days > 0 ? ` (${days} ${days === 1 ? 'den' : days < 5 ? 'dny' : 'dní'})` : ''}
- Období: ${b.start_date} – ${b.end_date}
- Čas vyzvednutí: ${b.pickup_time ? String(b.pickup_time).slice(0, 5) : 'neuveden'} | Čas vrácení: ${b.return_time ? String(b.return_time).slice(0, 5) : 'do konce posledního dne'}
${formatGearBranchLines(gearBranchOf(b))}
- Stav převzetí: ${picked ? 'výbava je PŘEVZATÁ (protokol podepsán) — měnit jde jen konec výpůjčky' : 'výbava zatím NENÍ převzatá (posun termínu, velikosti i storno jdou v Upravit rezervaci)'}

DŮLEŽITÉ: Tohle je ${GEAR_RENTAL_TITLE} (viz stejnojmenná pravidla). Neřeš motorku, kóji, km, tankování, mytí ani diagnostiku a suggest_sos nastav VŽDY na false (SOS tlačítko patří k pronajaté motorce) — při úrazu ať volá 155/112, poškozenou či ztracenou výbavu ať nahlásí firmě. Doklady: jen doklad totožnosti (18+), ŘP se nepotřebuje.`
  if (others && others.length > 0) {
    ctx += `\n\nZákazník má také další rezervace:`
    for (const o of others) ctx += `\n- ${otherLabel(o)}`
    ctx += `\nKdyž se ptá na motorku, týká se to jiné rezervace výše — zeptej se, o kterou jde.`
  }
  return ctx
}

/** Popisek rezervace do výpisů („motorka“ nebo „Výpůjčka výbavy (…)“). */
export function bookingTitle(b: Row): string {
  if (isGearBooking(b)) return gearBookingLabel(b)
  const m = b.motorcycles as Row | null
  return m ? `${m.brand || ''} ${m.model || ''}`.trim() || '?' : '?'
}
