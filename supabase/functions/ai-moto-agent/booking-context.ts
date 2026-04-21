// ===== ai-moto-agent/booking-context.ts =====
// Booking context formatting + agent config + system prompt building

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

export const FALLBACK_SYSTEM_PROMPT = `Jsi AI servisní technik MotoGo24 — půjčovny motorek.

## KRITICKÁ PRAVIDLA (NIKDY neporušuj):
1. NIKDY si nevymýšlej informace. NIKDY nehalucinuj názvy motorek, parametry ani postupy.
2. Pracuj VÝHRADNĚ s daty, která máš v kontextu nebo získáš přes nástroje.
3. Pokud nemáš dostatek dat, řekni to přímo: "Nemám k dispozici přesné informace o..."
4. NIKDY neuváděj jinou motorku než tu, kterou má zákazník v rezervaci (viz KONTEXT REZERVACE níže).

## DIAGNOSTICKÝ POSTUP (VŽDY dodržuj):
Než dáš radu, MUSÍŠ mít 100% jasno o čem zákazník mluví. Postupuj takto:
1. **Upřesni problém** — ptej se na detaily dokud nemáš jasný obraz:
   - Které konkrétní světlo/díl/funkce nefunguje?
   - Kdy to začalo? (za jízdy, po startu, náhle, postupně?)
   - Svítí nějaké kontrolky na palubní desce? Které?
   - Slyší nějaký zvuk? Cítí nějaký zápach?
2. **Požádej o fotku** — pokud zákazník neposlal fotku, VŽDY požádej: "Můžete mi poslat fotku problému / palubní desky / kontrolek?"
3. **Teprve potom raď** — až máš dostatek informací, dej konkrétní radu pro daný model.

NIKDY nedávej dlouhý seznam možných příčin na vágní popis. Místo toho se PTEJ.

Příklad ŠPATNĚ: "Nefunguje mi světlo" -> dlouhý výpis všech možných příčin
Příklad SPRÁVNĚ: "Nefunguje mi světlo" -> "Rozumím. Abych vám mohl pomoci, potřebuji vědět:
1) Které světlo přesně? (přední, zadní, blinkr, brzdové, kontrolky?)
2) Nefunguje úplně, nebo bliká/svítí slabě?
3) Můžete mi poslat fotku palubní desky?"

## Co umíš:
- Diagnostika závad na základě popisu nebo fotek
- Rady k obsluze a funkcím konkrétní motorky zákazníka
- Informace o rezervaci zákazníka
- Obecné rady pro jízdu a bezpečnost

## Formát odpovědi:
Na konci každé odpovědi přidej JSON blok:
---JSON---
{"suggest_sos": true/false}
---END---
suggest_sos: true pokud je závada vážná a zákazník by měl kontaktovat SOS.

Odpovídej v češtině, stručně a konkrétně pro daný model motorky.`

const TONE_MAP: Record<string, string> = {
  friendly: 'Komunikuj přátelsky a neformálně, buď vlídný a vstřícný.',
  professional: 'Komunikuj profesionálně a formálně, buď věcný a stručný.',
  concise: 'Odpovídej maximálně stručně — krátké, jasné věty bez zbytečností.',
  detailed: 'Poskytuj podrobná vysvětlení s kontextem a pozadím problému.',
}

export interface AgentConfig {
  persona_name?: string
  system_prompt?: string
  situations?: string[]
  forbidden?: string[]
  mustDo?: string[]
  tone?: string
  max_tokens?: number
  enabled?: boolean
}

export async function loadAgentConfig(supabaseAdmin: SupabaseClient): Promise<AgentConfig | null> {
  try {
    const { data, error } = await supabaseAdmin
      .from('app_settings')
      .select('value')
      .eq('key', 'ai_moto_agent_config')
      .single()

    if (error || !data?.value) return null
    return data.value as AgentConfig
  } catch {
    return null
  }
}

export function buildSystemPrompt(config: AgentConfig | null): string {
  if (!config || !config.enabled) return FALLBACK_SYSTEM_PROMPT

  let prompt = ''

  if (config.persona_name) {
    prompt += `Jsi ${config.persona_name} pro MotoGo24 — půjčovnu motorek.\n\n`
  }

  if (config.system_prompt) {
    prompt += config.system_prompt
  } else {
    prompt += FALLBACK_SYSTEM_PROMPT
  }

  if (config.tone && TONE_MAP[config.tone]) {
    prompt += `\n\n## TÓN KOMUNIKACE:\n${TONE_MAP[config.tone]}`
  }

  if (config.situations && config.situations.length > 0) {
    prompt += '\n\n## SITUAČNÍ PRAVIDLA:'
    for (const s of config.situations) prompt += `\n- ${s}`
  }

  if (config.mustDo && config.mustDo.length > 0) {
    prompt += '\n\n## VŽDY MUSÍ UDĚLAT:'
    for (const m of config.mustDo) prompt += `\n- ✅ ${m}`
  }

  if (config.forbidden && config.forbidden.length > 0) {
    prompt += '\n\n## ZAKÁZÁNO:'
    for (const f of config.forbidden) prompt += `\n- ❌ ${f}`
  }

  prompt += `

## KRITICKÁ BEZPEČNOSTNÍ PRAVIDLA (platí vždy):
1. NIKDY si nevymýšlej informace — pracuj výhradně s reálnými daty.
2. NIKDY neuváděj jinou motorku než tu z rezervace zákazníka.
3. Pokud nemáš dostatek dat, řekni to přímo.

## Formát odpovědi:
Na konci každé odpovědi přidej JSON blok:
---JSON---
{"suggest_sos": true/false}
---END---
suggest_sos: true pokud je závada vážná a zákazník by měl kontaktovat SOS.

Odpovídej v češtině.`

  return prompt
}

export function formatBookingContext(b: Record<string, unknown>, otherBookings: Array<Record<string, unknown>> | null): string {
  const m = b.motorcycles as Record<string, unknown> | null
  if (!m) {
    return `\n\n## KONTEXT REZERVACE:
Zákazník má rezervaci #${(b.id as string).slice(-8).toUpperCase()} (stav: ${b.status}), ale detaily motorky se nepodařilo načíst. Použij nástroj get_active_booking pro zjištění detailů.`
  }

  let ctx = `\n\n## KONTEXT REZERVACE (reálná data z DB — toto je PRAVDA):
- Rezervace #${(b.id as string).slice(-8).toUpperCase()}
- Stav: ${b.status}
- Motorka: ${m.brand || '?'} ${m.model || '?'}
- SPZ: ${m.spz || '?'}
- Kategorie: ${m.category || '?'}
- Motor: ${m.engine_type || '?'} ${m.engine_cc || '?'}cc, ${m.power_kw || '?'}kW / ${m.power_hp || '?'}hp
- Hmotnost: ${m.weight_kg || '?'}kg
- ABS: ${m.has_abs ? 'ANO' : 'NE'}, ASC: ${m.has_asc ? 'ANO' : 'NE'}
- Nádrž: ${m.fuel_tank_l || '?'}L, Výška sedla: ${m.seat_height_mm || '?'}mm
- Barva: ${m.color || '?'}, Rok: ${m.year || '?'}
- Popis: ${m.description || 'N/A'}
- Ideální použití: ${m.ideal_usage || 'N/A'}
- Funkce: ${m.features || 'N/A'}
- Návod: ${m.manual_url || 'N/A'}
- Nájezd: ${m.mileage || '?'}km
- Období: ${b.start_date} – ${b.end_date}
- Vyzvednutí: ${b.pickup_method || '?'} ${b.pickup_address ? '(' + b.pickup_address + ')' : ''}
- Vrácení: ${b.return_method || '?'} ${b.return_address ? '(' + b.return_address + ')' : ''}
- Pojištění: ${b.insurance_type || 'N/A'}

DŮLEŽITÉ: Zákazník má AKTIVNÍ motorku "${m.brand} ${m.model}". Veškeré odpovědi MUSÍ být pro tento konkrétní model. NIKDY nezmiňuj jinou motorku.`

  if (otherBookings && otherBookings.length > 0) {
    ctx += `\n\nZákazník má také nadcházející rezervace:`
    for (const ob of otherBookings) {
      const om = ob.motorcycles as Record<string, unknown> | null
      ctx += `\n- #${(ob.id as string).slice(-8).toUpperCase()}: ${om ? (om.brand + ' ' + om.model) : '?'} (${ob.status}, ${ob.start_date} – ${ob.end_date})`
    }
    ctx += `\nAle tyto rezervace NEJSOU aktivní — odpovídej pouze o aktuálně aktivní motorce.`
  }

  return ctx
}

export function formatMultipleBookingsContext(bookings: Array<Record<string, unknown>>): string {
  let ctx = `\n\n## KONTEXT REZERVACE — VÍCE REZERVACÍ:
Zákazník má více rezervací, žádná zatím nemá stav "active". MUSÍŠ se nejdříve ZEPTAT, o kterou motorku/rezervaci jde:\n`
  for (const b of bookings) {
    const m = b.motorcycles as Record<string, unknown> | null
    ctx += `- #${(b.id as string).slice(-8).toUpperCase()}: ${m ? (m.brand + ' ' + m.model) : '?'} (${b.status}, ${b.start_date} – ${b.end_date})\n`
  }
  ctx += `\nDŮLEŽITÉ: NIKDY nepředpokládej, o kterou motorku jde. Vždy se ZEPTEJ: "Vidím, že máte více rezervací: [seznam]. O kterou motorku se jedná?"`
  return ctx
}
