// ===== ai-moto-agent/public-tools.ts =====
// Informační / technické nástroje převzaté z `ai-public-agent`, aby měl SOS
// servisní agent v appce stejné MOŽNOSTI jako veřejný agent — JEN bez tvorby
// a úprav rezervací (create_booking_request, find/preview/apply_booking_change)
// a bez prodejního redirect_to_booking. Role agenta je technická podpora a
// pomocník, ne prodejce. Logika je 1:1 s veřejným agentem, jen parametrizovaná
// klientem (`sb`) a jazykem (`lang`).

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

function motoDisplayName(brand: string | null | undefined, model: string | null | undefined): string {
  const b = (brand || '').trim()
  const m = (model || '').trim()
  if (!b) return m
  if (!m) return b
  if (m.toLowerCase().startsWith(b.toLowerCase())) return m
  return `${b} ${m}`
}

function stripHtmlFull(html: string): string {
  return String(html || '')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<\/(p|div|li|tr|h[1-6])>/gi, '\n')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#3[49];/g, "'")
    .replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim()
}

// Anthropic tool definice — informační nástroje (read-only).
export const PUBLIC_READ_TOOLS = [
  {
    name: 'search_motorcycles',
    description: 'Vyhledá motorky v MotoGo24 katalogu (kompletní specs jako na webu /katalog/<id>): značka, model, kategorie, objem, výkon kW/hp, moment, hmotnost, výška sedla, max. rychlost, nádrž, spotřeba, palivo, převodovka, pohon, brzdy, ABS/ASC, počet míst, povinný ŘP, barva, min/max dní, min cena. Pro porovnání motorek používej VÝHRADNĚ tyto fieldy (engine_cc, power_kw, weight_kg, seat_height_mm), ne číslo v názvu. Když je field null, v DB chybí — NEIMPROVIZUJ. Filtruj podle značky/modelu/kategorie/ŘP/výkonu/ceny/dostupnosti.',
    input_schema: {
      type: 'object' as const,
      properties: {
        brand: { type: 'string', description: 'Značka, např. Kawasaki, BMW, Yamaha, Honda. Case-insensitive substring.' },
        model_query: { type: 'string', description: 'Volnotextový dotaz na model (např. "Z 900", "MT-09").' },
        category: { type: 'string', enum: ['cestovni', 'naked', 'supermoto', 'detske'] },
        license_group: { type: 'string', enum: ['AM', 'A1', 'A2', 'A', 'B', 'N'] },
        kw_min: { type: 'number' }, kw_max: { type: 'number' },
        price_max: { type: 'number', description: 'Max Kč/den' },
        available_on: { type: 'string', description: 'Datum YYYY-MM-DD — vrátí jen motorky volné v tento den.' },
        available_from: { type: 'string', description: 'Spolu s available_to — rozsah YYYY-MM-DD.' },
        available_to: { type: 'string' },
      },
    },
  },
  {
    name: 'get_availability',
    description: 'Zkontroluje obsazené termíny pro konkrétní motorku. Vrací seznam booked ranges.',
    input_schema: {
      type: 'object' as const,
      properties: { moto_id: { type: 'string' } },
      required: ['moto_id'],
    },
  },
  {
    name: 'calculate_price',
    description: 'Vypočítá přesnou cenu pronájmu pro motorku a termín z reálného denního ceníku. NEVYTVÁŘÍ rezervaci (agent v appce rezervace netvoří ani neupravuje).',
    input_schema: {
      type: 'object' as const,
      properties: {
        moto_id: { type: 'string' },
        start_date: { type: 'string', description: 'YYYY-MM-DD' },
        end_date: { type: 'string', description: 'YYYY-MM-DD' },
        promo_code: { type: 'string' },
      },
      required: ['moto_id', 'start_date', 'end_date'],
    },
  },
  {
    name: 'get_faq',
    description: 'Vyhledá v interní FAQ (CMS) podle klíčového slova (kauce, pojištění, řidičák, zahraničí, storno…). Vrací jen reálná data z administrace — když není v CMS, vrátí prázdno a TY přiznáš, že to nevíš a doporučíš kontakt.',
    input_schema: {
      type: 'object' as const,
      properties: { query: { type: 'string' } },
    },
  },
  {
    name: 'get_policies',
    description: 'Vrátí oficiální podmínky půjčovny z CMS (storno, kauce, co je v ceně, cenu přistavení, foreign travel, dokumenty pro vyzvednutí, tankování, věkové limity skupin ŘP). VŽDY zavolej, než zákazníkovi sdělíš jakékoliv konkrétní procento storno-poplatku, výši kauce, cenu přistavení nebo platnost pojištění mimo EU. Pokud vrátí prázdno, NEUVÁDĚJ konkrétní čísla z hlavy.',
    input_schema: {
      type: 'object' as const,
      properties: { topic: { type: 'string', description: 'Volitelně téma — cancellation, deposit, included, addons, delivery_pricing, foreign_travel, fuel, license_groups, documents.' } },
    },
  },
  {
    name: 'get_legal_document',
    description: 'Vrátí PŘESNÉ aktuální znění oficiálních smluvních/právních dokumentů (VOP, nájemní/zápůjční smlouva, předávací protokol, GDPR, webové dokumenty). POUŽIJ, když se zákazník ptá na smluvní/právní detail mimo get_policies/get_faq — vyčíslení škody, spoluúčast, odpovědnost za poškození, reklamace, zpracování osobních údajů, sankce. Bez `document` vrátí seznam; s `document` plné znění; s `query` relevantní úryvky. Cituj VÝHRADNĚ to, co tool vrátí.',
    input_schema: {
      type: 'object' as const,
      properties: {
        document: { type: 'string', description: 'Klíč dokumentu — `vop`, `rental_contract`, `handover_protocol`, `gdpr`, nebo slug webového dokumentu. Vynech pro seznam.' },
        query: { type: 'string', description: 'Volitelně klíčová slova — vrátí jen relevantní úseky.' },
      },
    },
  },
  {
    name: 'get_extras_catalog',
    description: 'Vrátí seznam příslušenství, které lze přiobjednat (boty, výbava spolujezdce, přistavení, atd.) s cenami.',
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'get_branches',
    description: 'Vrátí seznam poboček MotoGo24 s adresou, GPS a otevíracími hodinami.',
    input_schema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'validate_promo_or_voucher',
    description: 'Ověří promo kód nebo voucher. Vrátí typ a hodnotu slevy. Pokud je kód neplatný, vrátí valid=false.',
    input_schema: {
      type: 'object' as const,
      properties: { code: { type: 'string' } },
      required: ['code'],
    },
  },
]

export const PUBLIC_READ_TOOL_NAMES = new Set(PUBLIC_READ_TOOLS.map((t) => t.name))

/**
 * Vykoná informační nástroj převzatý z veřejného agenta. Vrací výsledek, nebo
 * `undefined` pokud `name` nepatří do této sady (caller pak spadne na app tooly).
 */
export async function execPublicReadTool(
  name: string,
  args: Record<string, unknown>,
  sb: SupabaseClient,
  lang = 'cs',
): Promise<unknown | undefined> {
  switch (name) {
    case 'search_motorcycles': {
      let q = sb.from('motorcycles').select('id, model, brand, year, category, engine_cc, engine_type, power_kw, power_hp, torque_nm, weight_kg, seat_height_mm, top_speed_kmh, fuel_tank_l, fuel_consumption_l100km, fuel_type, transmission, drivetrain, brake_type, has_abs, has_asc, seats_count, license_required, color, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, ideal_usage, description, features, suitable_for, min_rental_days, max_rental_days, image_url, manual_url, manual_external_url')
        .eq('status', 'active').order('model')
      if (args.category) q = q.ilike('category', `%${args.category}%`)
      if (args.license_group) {
        // ŘP je hierarchické (AM < A1 < A2 < A) — kdo má vyšší, smí i nižší.
        // Zákazníkovi s „A" tak vrátíme i A2/A1/AM stroje, ne jen přesně „A".
        const RIDEABLE: Record<string, string[]> = {
          A: ['A', 'A2', 'A1', 'AM'],
          A2: ['A2', 'A1', 'AM'],
          A1: ['A1', 'AM'],
          AM: ['AM'],
        }
        const allowed = RIDEABLE[String(args.license_group)]
        q = allowed ? q.in('license_required', allowed) : q.eq('license_required', String(args.license_group))
      }
      if (args.kw_min) q = q.gte('power_kw', Number(args.kw_min))
      if (args.kw_max) q = q.lte('power_kw', Number(args.kw_max))
      if (args.brand) q = q.ilike('brand', `%${String(args.brand)}%`)
      if (args.model_query) q = q.ilike('model', `%${String(args.model_query)}%`)
      const { data } = await q
      let result = data || []
      if (args.price_max) {
        const maxP = Number(args.price_max)
        result = result.filter((m: Record<string, unknown>) => {
          const ps = ['price_mon','price_tue','price_wed','price_thu','price_fri','price_sat','price_sun']
            .map((k) => Number((m as Record<string, unknown>)[k] || 0)).filter((p) => p > 0)
          return ps.length > 0 && Math.min(...ps) <= maxP
        })
      }

      const availFrom = args.available_on ? String(args.available_on) : (args.available_from ? String(args.available_from) : null)
      const availTo = args.available_on ? String(args.available_on) : (args.available_to ? String(args.available_to) : null)
      if (availFrom && availTo) {
        const checks = await Promise.all(result.map(async (m: Record<string, unknown>) => {
          const { data: booked } = await sb.rpc('get_moto_booked_dates', { p_moto_id: m.id })
          const ranges = (booked || []) as Array<{ start_date: string; end_date: string }>
          const conflict = ranges.some((r) => !(availTo < r.start_date || availFrom > r.end_date))
          return { moto: m, free: !conflict }
        }))
        result = checks.filter((c) => c.free).map((c) => c.moto as Record<string, unknown>)
      }

      const minPriceFor = (m: Record<string, unknown>): number => {
        const ps = ['price_mon','price_tue','price_wed','price_thu','price_fri','price_sat','price_sun']
          .map((k) => Number((m as Record<string, unknown>)[k] || 0)).filter((p) => p > 0)
        return ps.length > 0 ? Math.min(...ps) : 0
      }

      const dayKeys = ['sun','mon','tue','wed','thu','fri','sat']
      const dayLabels = ['neděle','pondělí','úterý','středa','čtvrtek','pátek','sobota']
      const priceForRange = (m: Record<string, unknown>, fromIso: string, toIso: string): { total: number; days: Array<{ date: string; weekday: string; price_kc: number }>; missing_days: string[] } => {
        const start = new Date(fromIso), end = new Date(toIso)
        const days: Array<{ date: string; weekday: string; price_kc: number }> = []
        const missing: string[] = []
        let total = 0
        if (isNaN(start.getTime()) || isNaN(end.getTime()) || end < start) return { total: 0, days, missing_days: [fromIso] }
        const d = new Date(start)
        while (d <= end) {
          const dn = dayKeys[d.getDay()]
          const raw = (m as Record<string, unknown>)['price_' + dn]
          const price = raw == null ? null : Number(raw)
          const iso = d.toISOString().slice(0, 10)
          if (price == null || !isFinite(price) || price <= 0) {
            missing.push(iso)
          } else {
            total += price
            days.push({ date: iso, weekday: dayLabels[d.getDay()], price_kc: price })
          }
          d.setDate(d.getDate() + 1)
        }
        return { total, days, missing_days: missing }
      }

      return {
        count: result.length,
        availability_window: availFrom ? { from: availFrom, to: availTo } : null,
        motorcycles: result.slice(0, 8).map((m: Record<string, unknown>) => {
          const base: Record<string, unknown> = {
            id: m.id,
            name: motoDisplayName(m.brand as string, m.model as string),
            brand: m.brand, model: m.model, year: m.year, category: m.category,
            engine_cc: m.engine_cc, engine_type: m.engine_type,
            power_kw: m.power_kw, power_hp: m.power_hp, torque_nm: m.torque_nm,
            weight_kg: m.weight_kg, seat_height_mm: m.seat_height_mm,
            top_speed_kmh: m.top_speed_kmh, fuel_tank_l: m.fuel_tank_l,
            fuel_consumption_l100km: m.fuel_consumption_l100km, fuel_type: m.fuel_type,
            transmission: m.transmission, drivetrain: m.drivetrain, brake_type: m.brake_type,
            has_abs: m.has_abs, has_asc: m.has_asc, seats_count: m.seats_count,
            license: m.license_required, color: m.color,
            min_rental_days: m.min_rental_days, max_rental_days: m.max_rental_days,
            min_price_kc: minPriceFor(m),
            has_manual: !!(String(m.manual_url || '').trim() || String(m.manual_external_url || '').trim()),
            ideal_usage: m.ideal_usage,
            description: typeof m.description === 'string' ? String(m.description).slice(0, 500) : null,
            features: m.features,
            suitable_for: typeof m.suitable_for === 'string' ? String(m.suitable_for).slice(0, 500) : null,
            image_url: m.image_url,
            url: `https://www.motogo24.cz/katalog/${m.id}`,
          }
          if (availFrom && availTo) {
            const pr = priceForRange(m, availFrom, availTo)
            if (pr.missing_days.length === 0 && pr.days.length > 0) {
              base.requested_window = { from: availFrom, to: availTo, days: pr.days.length }
              base.requested_price_total_kc = pr.total
              base.requested_per_day = pr.days
              if (pr.days.length === 1) {
                base.requested_price_kc_for_day = pr.days[0].price_kc
                base.requested_weekday = pr.days[0].weekday
              }
            } else if (pr.missing_days.length > 0) {
              base.requested_price_unknown = true
              base.requested_missing_days = pr.missing_days
            }
          }
          return base
        }),
      }
    }
    case 'get_availability': {
      const { data } = await sb.rpc('get_moto_booked_dates', { p_moto_id: args.moto_id })
      return { booked: data || [] }
    }
    case 'calculate_price': {
      const { moto_id, start_date, end_date, promo_code } = args
      const { data: moto } = await sb.from('motorcycles')
        .select('model, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun')
        .eq('id', moto_id).maybeSingle()
      if (!moto) return { error: 'Motorka nenalezena' }
      const days = ['sun','mon','tue','wed','thu','fri','sat']
      const start = new Date(String(start_date)), end = new Date(String(end_date))
      if (isNaN(start.getTime()) || isNaN(end.getTime())) return { error: 'Neplatné datum' }
      if (end < start) return { error: 'Konec musí být po začátku' }

      const motoRow = moto as Record<string, unknown>
      const dayLabelsCs = ['neděle', 'pondělí', 'úterý', 'středa', 'čtvrtek', 'pátek', 'sobota']
      let total = 0, count = 0
      const missingDays: string[] = []
      const breakdown: Array<{ date: string; weekday: string; price_kc: number }> = []
      const d = new Date(start)
      while (d <= end) {
        const dn = days[d.getDay()]
        const raw = motoRow['price_' + dn]
        const price = raw == null ? null : Number(raw)
        const iso = d.toISOString().slice(0, 10)
        const weekday = dayLabelsCs[d.getDay()]
        if (price == null || !isFinite(price) || price <= 0) {
          missingDays.push(iso)
        } else {
          total += price
          breakdown.push({ date: iso, weekday, price_kc: price })
        }
        count++
        d.setDate(d.getDate() + 1)
      }
      if (missingDays.length > 0) {
        return {
          error: 'Ceník této motorky pro některé dny chybí v DB — nemůžu zaručit přesnou cenu. Doporuč zákazníkovi rezervaci dokončit ve formuláři, kde se cena spočítá konzervativně.',
          missing_price_days: missingDays,
        }
      }
      let discount = 0
      let promoApplied: { type: string; value: number } | null = null
      if (promo_code) {
        const { data: pr } = await sb.rpc('validate_promo_code', { code: promo_code })
        if (pr && (pr as Record<string, unknown>).valid) {
          const p = pr as Record<string, unknown>
          const v = Number(p.value)
          if (p.type === 'percent') discount = Math.round(total * v / 100)
          else discount = v
          promoApplied = { type: String(p.type), value: v }
        }
      }
      return {
        days: count, per_day_breakdown: breakdown, rental_total: total,
        promo_discount: discount, promo_applied: promoApplied,
        grand_total: total - discount, currency: 'CZK',
        note_excludes: 'Cena nezahrnuje příplatky za přistavení mimo Mezná, výbavu spolujezdce, boty pro řidiče, GPS, top case ani jiné extras — ty se připočítají v rezervačním formuláři dle výběru.',
      }
    }
    case 'get_faq': {
      const stripHtml = (s: string) => String(s || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim()
      const L = (lang || 'cs').slice(0, 2)
      const faqs: Array<{ q: string; a: string; cat?: string }> = []
      try {
        const { data: rows } = await sb.from('faq_items')
          .select('category_key, category_label, question, answer, translations, sort_order')
          .eq('published', true)
          .order('category_key', { ascending: true })
          .order('sort_order', { ascending: true })
        for (const r of (rows || []) as Record<string, unknown>[]) {
          const tr = (r.translations as Record<string, { question?: string; answer?: string; category_label?: string }> | null)?.[L] || {}
          const qq = (L !== 'cs' && tr.question) ? tr.question : String(r.question || '')
          const a = (L !== 'cs' && tr.answer) ? tr.answer : String(r.answer || '')
          const cat = (L !== 'cs' && tr.category_label) ? tr.category_label : String(r.category_label || r.category_key || '')
          if (qq && a) faqs.push({ q: stripHtml(qq), a: stripHtml(a), cat: cat || undefined })
        }
      } catch { /* DB nedostupná — vrátíme prázdno a agent to korektně přizná */ }

      if (faqs.length === 0) {
        return {
          source: 'empty', count: 0, faqs: [],
          notice: 'FAQ v CMS není naplněna. NESDÍLEJ konkrétní policies z hlavy. Doporuč zákazníkovi kontakt info@motogo24.cz / +420 774 256 271, nebo zavolej tool get_policies. NIKDY si neimprovizuj cenu kauce, % storno-poplatku ani podmínky pojištění.',
        }
      }

      const stripDia = (s: string) => s.normalize('NFD').replace(/\p{Diacritic}/gu, '')
      const norm = (s: string) => stripDia(String(s || '').toLowerCase())
      const rawQuery = String(args.query || '').trim()
      let matched = faqs
      if (rawQuery) {
        const qNorm = norm(rawQuery)
        const tokens = qNorm.split(/[^a-z0-9]+/).filter((t) => t.length >= 3)
        const scored = faqs
          .map((f) => {
            const hay = norm(f.q + ' ' + f.a + ' ' + (f.cat || ''))
            let score = 0
            if (qNorm && hay.includes(qNorm)) score += 5
            for (const t of tokens) if (hay.includes(t)) score += 1
            return { f, score }
          })
          .filter((x) => x.score > 0)
          .sort((a, b) => b.score - a.score)
        matched = scored.length > 0 ? scored.map((x) => x.f) : faqs
      }
      return { source: 'cms', count: matched.length, faqs: matched.slice(0, 8) }
    }
    case 'get_policies': {
      try {
        const { data: cms } = await sb.from('app_settings').select('value').eq('key', 'site.policies').maybeSingle()
        const policies = (cms?.value as Record<string, unknown>) || {}
        if (!policies || Object.keys(policies).length === 0) {
          return {
            source: 'empty', policies: {},
            notice: 'Policies v CMS nejsou nastavené. NESDÍLEJ z hlavy konkrétní procenta storna, výši kauce, cenu přistavení, pojištění mimo EU ani věkové limity skupin ŘP. Přiznej, že přesná čísla najde zákazník ve smlouvě / VOP, nebo doporuč info@motogo24.cz / +420 774 256 271.',
          }
        }
        const topic = String((args as Record<string, unknown>).topic || '').toLowerCase().trim()
        if (topic && policies[topic] !== undefined) {
          return { source: 'cms', topic, value: policies[topic] }
        }
        return { source: 'cms', policies }
      } catch (e) {
        return { error: `Nepodařilo se načíst policies: ${(e as Error).message}` }
      }
    }
    case 'get_legal_document': {
      try {
        const want = typeof args.document === 'string' ? String(args.document).trim().toLowerCase() : ''
        const query = typeof args.query === 'string' ? String(args.query).trim() : ''
        const L = (lang || 'cs').slice(0, 2)
        const MAX = 12000

        const { data: tpls } = await sb.from('document_templates')
          .select('type, name, content_html, content_translations, name_translations')
          .eq('active', true).order('version', { ascending: false })
        const { data: customs } = await sb.from('custom_documents')
          .select('slug, title, content_html, kind, pdf_path, translations')
          .eq('active', true).eq('show_on_web', true).order('sort_order', { ascending: true })

        type Doc = { key: string; title: string; text: string; kind: string; url?: string }
        const docs: Doc[] = []
        const seen = new Set<string>()
        for (const t of (tpls || []) as Record<string, unknown>[]) {
          const key = String(t.type || '')
          if (!key || seen.has(key)) continue
          seen.add(key)
          const ct = (t.content_translations as Record<string, string> | null)?.[L]
          const nt = (t.name_translations as Record<string, string> | null)?.[L]
          const html = (L !== 'cs' && ct) ? ct : String(t.content_html || '')
          docs.push({ key, title: String((L !== 'cs' && nt) || t.name || key), text: stripHtmlFull(html), kind: 'html' })
        }
        for (const c of (customs || []) as Record<string, unknown>[]) {
          const key = String(c.slug || '')
          if (!key || seen.has(key)) continue
          seen.add(key)
          const tr = (c.translations as Record<string, { title?: string; content_html?: string }> | null)?.[L] || {}
          const html = (L !== 'cs' && tr.content_html) ? tr.content_html : String(c.content_html || '')
          docs.push({
            key, title: String((L !== 'cs' && tr.title) || c.title || key),
            text: stripHtmlFull(html), kind: String(c.kind || 'html'),
            url: (c.pdf_path as string) || `https://www.motogo24.cz/dokumenty/${key}`,
          })
        }

        if (docs.length === 0) {
          return {
            source: 'empty', documents: [],
            notice: 'V systému nejsou publikované žádné smluvní dokumenty. NEPŘEBÍREJ smluvní detaily z hlavy — řekni, že přesné znění zákazník dostane ve smlouvě/VOP, nebo odkaž na info@motogo24.cz / +420 774 256 271.',
          }
        }

        if (!want) {
          return {
            source: 'documents',
            available: docs.map((d) => ({ key: d.key, title: d.title, kind: d.kind, has_text: d.text.length > 0, url: d.url })),
            hint: 'Zavolej znovu s parametrem `document` = jeden z těchto `key` (a volitelně `query`). Cituj jen to, co tool vrátí.',
          }
        }

        const match = docs.find((d) => d.key.toLowerCase() === want)
          || docs.find((d) => d.key.toLowerCase().includes(want) || d.title.toLowerCase().includes(want))
        if (!match) {
          return { source: 'documents', error: `Dokument "${want}" nenalezen.`, available: docs.map((d) => ({ key: d.key, title: d.title })) }
        }
        if (!match.text) {
          return {
            source: 'documents', key: match.key, title: match.title, kind: match.kind, url: match.url,
            notice: 'Tento dokument je na webu jen jako PDF — strojový text k citaci nemám. Odkaž zákazníka na uvedenou URL nebo na kontakt.',
          }
        }

        if (query) {
          const text = match.text
          const lc = text.toLowerCase()
          const terms = query.toLowerCase().split(/\s+/).filter((w) => w.length >= 3)
          const hits: number[] = []
          for (const term of terms) {
            let from = 0
            for (;;) {
              const i = lc.indexOf(term, from)
              if (i < 0 || hits.length > 40) break
              hits.push(i); from = i + term.length
            }
          }
          if (hits.length > 0) {
            hits.sort((a, b) => a - b)
            const win: Array<[number, number]> = []
            for (const i of hits) {
              const s = Math.max(0, i - 400), e = Math.min(text.length, i + 400)
              const last = win[win.length - 1]
              if (last && s <= last[1]) last[1] = Math.max(last[1], e)
              else win.push([s, e])
            }
            let excerpt = win.map(([s, e]) => (s > 0 ? '…' : '') + text.slice(s, e).trim() + (e < text.length ? '…' : '')).join('\n\n———\n\n')
            if (excerpt.length > MAX) excerpt = excerpt.slice(0, MAX) + '…'
            return {
              source: 'documents', key: match.key, title: match.title, mode: 'excerpts', query, text: excerpt,
              instruction: 'Odpověz výhradně z tohoto znění. Pokud konkrétní odpověď v úryvcích NENÍ, přiznej to a odkaž zákazníka na plný text dokumentu / kontakt — nedomýšlej.',
            }
          }
        }
        const full = match.text.length > MAX ? match.text.slice(0, MAX) + '\n…[zkráceno — plné znění na webu]' : match.text
        return {
          source: 'documents', key: match.key, title: match.title, kind: match.kind, url: match.url, mode: 'full', text: full,
          instruction: 'Cituj a parafrázuj VÝHRADNĚ z tohoto znění. Co tu výslovně není, si nedomýšlej — přiznej, že to dokument neuvádí, a odkaž na kontakt.',
        }
      } catch (e) {
        return { error: `Nepodařilo se načíst dokumenty: ${(e as Error).message}` }
      }
    }
    case 'get_extras_catalog': {
      const { data } = await sb.from('extras_catalog')
        .select('id, name, description, price, unit, category, is_active')
        .eq('is_active', true).order('sort_order', { ascending: true }).order('name')
      return { extras: (data || []).map((e: Record<string, unknown>) => ({
        id: e.id, name: e.name, price_kc: e.price, unit: e.unit || 'ks', category: e.category, description: e.description,
      })) }
    }
    case 'get_branches': {
      const { data } = await sb.from('branches')
        .select('id, name, address, city, zip, lat, lng, phone, is_open, type, notes')
        .order('name')
      return { branches: (data || []).map((b: Record<string, unknown>) => ({
        id: b.id, name: b.name, address: `${b.address || ''}, ${b.zip || ''} ${b.city || ''}`.trim(),
        lat: b.lat, lng: b.lng, phone: b.phone, is_open_nonstop: !!b.is_open, type: b.type, notes: b.notes,
      })) }
    }
    case 'validate_promo_or_voucher': {
      const code = String(args.code || '').trim()
      if (!code) return { valid: false, error: 'Prázdný kód' }
      const { data: promo } = await sb.rpc('validate_promo_code', { code })
      if (promo && (promo as Record<string, unknown>).valid) {
        return { valid: true, kind: 'promo', ...(promo as Record<string, unknown>) }
      }
      const { data: vch } = await sb.rpc('validate_voucher_code', { p_code: code })
      if (vch && (vch as Record<string, unknown>).valid) {
        return { valid: true, kind: 'voucher', ...(vch as Record<string, unknown>) }
      }
      return { valid: false, error: 'Kód není platný nebo už byl použit.' }
    }
    default:
      return undefined
  }
}
