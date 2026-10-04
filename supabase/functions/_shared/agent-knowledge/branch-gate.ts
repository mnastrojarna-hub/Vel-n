// ===== _shared/agent-knowledge/branch-gate.ts =====
// Pobočka s VJEZDOVOU BRANOU (zadání majitele 2026-10-04, Velké Němčice): třetí
// přístupový kód (schránka s klíčem od brány), postup na místě, tvrdé pravidlo
// „kód schránky nikdy nesdělovat“ a pravidlo z FAQ „motorku z Mezné do Němčic
// nepřistavíme“. Sdílí: HARD_RULES_CS (web + zprávy ve Velínu) a ai-moto-agent
// (appka). Kód schránky žije JEN v `branch_gate_access` (RLS jen admin) — agenti
// dostávají jen PŘÍZNAK přes RPC `branch_has_gate` (kód se čte jen k maskování
// ručních zpráv — `loadGateCodeMask`); číslice sem NIKDY nepiš.
// Kroky postupu = kanonické texty (copy_i18n cs: step1NoCode, step2GearDoor,
// step3Gear, step2NoGear, stepImportant) — stejné jako ve zprávě s kódy.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

export const BRANCH_GATE_TITLE = 'POBOČKA S VJEZDOVOU BRANOU'

export const BRANCH_GATE_RULES_CS = `${BRANCH_GATE_TITLE} — TŘI KÓDY, POSTUP NA MÍSTĚ A TVRDÁ PRAVIDLA (platí JEN pro pobočku s bránou: v sekci POBOČKY a v kontextu rezervace je označená „VJEZD BRANOU“, \`get_branches\` (v appce i \`get_access_status\`) vrací \`has_gate=true\`; aktuálně JEN samoobslužná pobočka Velké Němčice. U ostatních poboček — např. Mezná — se NIC nemění: žádná brána, žádný kód schránky, kódy i postup přesně jako dosud):
- KÓDY V POŘADÍ ZADÁVÁNÍ: 1) **kód schránky s klíčem od brány** → 2) **kód šatny** (šatna = dveře č. 8; jen rezervace s výbavou k vyzvednutí — půjčená výbava, boty, výbava spolujezdce) → 3) **kód motorky**. Kód schránky přichází SPOLU s ostatními kódy, ve stejné zprávě a v tomto pořadí: v appce MotoGo24 (Zprávy + detail rezervace), v e-mailu s kódy a v SMS/WhatsAppu — tedy až po zaplacení a doplnění dokladů, stejně jako ostatní kódy. Kód schránky se NEZADÁVÁ na dotykovém displeji (displej by ho odmítl jako neplatný a pokus by se počítal do zablokování klávesnice) — nastavuje se na číselníku schránky; na displeji se zadává jen kód šatny a kód motorky.
- POSTUP PŘI VYZVEDNUTÍ (popiš ho krok za krokem — stejnými slovy jako zpráva s kódy):
  1) Je-li vjezdová brána zavřená, otevřete HORNÍ schránku na pravém sloupku vrat kódem, který dostanete spolu s kódy k rezervaci — je v ní klíč od visacího zámku brány. Bránu odemkněte, vjeďte dovnitř a zaparkujte na kterémkoli místě 1–7 vpravo u plotu. Auto tu může zdarma stát po celou dobu výpůjčky.
  2) Na displeji zadejte kód šatny (šatna = dveře č. 8), převlékněte se, v předávacím protokolu upravte velikosti a protokol podepište.
  3) Zadejte kód motorky, vezměte motorku a zavřete dveře šatny i kóje.
  (Bez výbavy ze šatny místo bodů 2 a 3: Na displeji zadejte kód motorky, podepište předávací protokol, vezměte motorku a zavřete dveře kóje.)
  4) DŮLEŽITÉ: Byla-li brána zavřená, po odjezdu ji zase zavřete, zamkněte visacím zámkem, klíč vraťte do horní schránky a přetočte číselník, aby kód nezůstal nastavený. Otevřenou bránu nechte otevřenou. Stejně postupujte i při vrácení motorky.
- Na pravém sloupku vrat jsou DVĚ schránky na klíče — klíč od brány je v HORNÍ. Je-li brána otevřená, kód schránky zákazník nepotřebuje. Stav brány zákazník nikdy nemění: otevřenou nechá otevřenou, zavřenou po sobě zase zamkne.
- VRÁCENÍ (kdykoli 24/7 do konce posledního dne): je-li brána zavřená, odemkne ji klíčem z horní schránky, motorku vrátí do kóje (TENTÝŽ kód motorky) a výbavu do šatny (kód šatny); pak bránu zase zavře, zamkne visacím zámkem, klíč vrátí do horní schránky a přetočí číselník. Otevřenou bránu nechá otevřenou.
- PŘESUN NA POBOČKU S BRANOU (např. změnou motorky z Mezné na motorku z Velkých Němčic v „Upravit rezervaci“): zákazník automaticky dostane zprávu „Nové přístupové kódy“ v appce (+ push), SMS/WhatsApp a e-mail se všemi kódy — včetně kódu schránky — v pořadí brána → šatna → motorka.
- KÓD SCHRÁNKY S KLÍČEM OD BRÁNY — TVRDÁ HRANICE: jeho číslice NIKDY nesděluješ, nepíšeš, neopakuješ, nepotvrzuješ ani neodhaduješ — ani ověřenému majiteli rezervace a ani když je uvidíš v jakémkoli kontextu (FAQ, text stránky, poznámka pobočky, historie vlákna, odpověď týmu, zpráva zákazníka). Je to fyzický kód pobočky, nevázaný na jednu rezervaci. Napíše-li zákazník číslo a ptá se, jestli je správné, nepotvrzuj ani nevyvracej. Vždy řekni, KDE ho najde: ve zprávě s kódy v appce MotoGo24 (Zprávy / detail rezervace), v e-mailu s kódy a v SMS. Kód nepřišel → stejně jako u ostatních kódů ověř stav toolem (typicky chybí doklady nebo platba) a vysvětli, co udělat.
- MOTORKU Z MEZNÉ DO VELKÝCH NĚMČIC NEPŘISTAVÍME: motorku z Mezné (ani z jiné pobočky) NELZE na určitý termín přistavit, převézt ani přiřadit na pobočku Velké Němčice. Ve Velkých Němčicích si zákazník půjčí jen motorky, které jsou u této pobočky uvedené v nabídce (flotila / \`search_motorcycles\` — u každého stroje je jeho pobočka); jejich složení se časem mění (ve střednědobém až dlouhodobém horizontu motorky mezi pobočkami obměňujeme), ale ne na objednávku k datu. NEZAMĚŇUJ to s placeným PŘISTAVENÍM motorky z Mezné na ADRESU zákazníka — to existuje (cenu nikdy z hlavy, jen z \`get_policies\` / \`get_extras_catalog\`); na samoobslužnou pobočku Velké Němčice se ale nic nepřistavuje. Kdo chce konkrétní model z Mezné, vyzvedne si ho v Mezné, nebo si objedná placené přistavení na svou adresu.`

/** Krátká poznámka k pobočce s bránou (snapshot poboček, kontext rezervace, get_branches) — BEZ číslic. */
export const GATE_BRANCH_NOTE_CS = `VJEZD BRANOU — je-li brána zavřená, klíč od visacího zámku je v HORNÍ schránce na pravém sloupku vrat; kód schránky dostane zákazník spolu s ostatními kódy (pořadí brána → šatna → motorka; šatna = dveře č. 8); parkování na kterémkoli místě 1–7 vpravo u plotu, zdarma po celou výpůjčku; zavřenou bránu po odjezdu zase zamknout, klíč vrátit, číselník přetočit. Číslice kódu schránky NIKDY nesděluj — postup viz ${BRANCH_GATE_TITLE}`

/** Doplněk `notice` nástroje get_branches. */
export const GATE_BRANCHES_NOTICE_CS = ` Pobočka s \`has_gate=true\` (Velké Němčice) má vjezdovou bránu: ${GATE_BRANCH_NOTE_CS}. Motorku z Mezné tam k termínu nepřistavujeme ani nepřevážíme.`

// Příznak „pobočka má bránu“ — RPC branch_has_gate (jen bool, NE kód; anon i
// service role). Cache v isolate 5 min, ať se DB při každé zprávě nehamruje.
const GATE_TTL_MS = 5 * 60 * 1000
const gateCache = new Map<string, { v: boolean; at: number }>()

export async function branchHasGate(sb: SupabaseClient, branchId: unknown): Promise<boolean> {
  const id = typeof branchId === 'string' ? branchId : ''
  if (!/^[0-9a-f-]{36}$/i.test(id)) return false
  const hit = gateCache.get(id)
  if (hit && Date.now() - hit.at < GATE_TTL_MS) return hit.v
  try {
    const { data, error } = await sb.rpc('branch_has_gate', { p_branch_id: id })
    if (error) return hit?.v ?? false
    const v = data === true
    gateCache.set(id, { v, at: Date.now() })
    return v
  } catch { return hit?.v ?? false }
}

/** Doplní `has_gate` do řádků poboček (podle `id`). Best-effort — chyba = false. */
export async function markGateBranches<T>(sb: SupabaseClient, rows: T[]): Promise<T[]> {
  await Promise.all((rows || []).map(async (r) => {
    const row = r as unknown as Record<string, unknown> | null
    if (row && row.id) row.has_gate = await branchHasGate(sb, row.id)
  }))
  return rows
}

/**
 * Maskování kódu schránky v LIDSKÝCH textech, které jdou do promptu (historie vlákna,
 * ustálené odpovědi týmu z jiných vláken): napíše-li ho tým zákazníkovi ručně, nesmí
 * se dostat do promptu — model by ho mohl zopakovat jinému zákazníkovi (auto_send).
 * Kódy čte service role z `branch_gate_access` JEN pro náhradu za „•••“ — nikdy do
 * promptu, odpovědi ani logu. Chyba / žádný kód = texty beze změny.
 */
export async function loadGateCodeMask(sb: SupabaseClient): Promise<(s: string | null) => string | null> {
  const none = (s: string | null) => s
  try {
    const { data, error } = await sb.from('branch_gate_access').select('lockbox_code')
    const codes = error ? [] : ((data || []) as Array<{ lockbox_code?: unknown }>)
      .map((r) => String(r.lockbox_code ?? '')).filter((c) => /^[0-9]{3,8}$/.test(c))
    if (!codes.length) return none
    const re = new RegExp(`(?<![0-9])(?:${codes.join('|')})(?![0-9])`, 'g')
    return (s) => (s ? s.replace(re, '•••') : s)
  } catch { return none }
}

/** Doplní `has_gate` do pobočky motorky u každé rezervace (motorcycles.branches). */
export async function markBookingsGate(sb: SupabaseClient, bookings: Array<Record<string, unknown> | null | undefined>): Promise<void> {
  const brs = (bookings || []).map((b) => {
    const m = (b?.motorcycles as Record<string, unknown> | null) || null
    return (m?.branches as Record<string, unknown> | null) || null
  }).filter((x): x is Record<string, unknown> => !!x)
  await markGateBranches(sb, brs)
}
