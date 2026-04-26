import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../ui/Button'

const SETTINGS_KEY = 'ai_public_agent_config'

const DEFAULT_CONFIG = {
  persona_name: 'Tomáš — kámoš z motorkárny',
  system_prompt: `Jsi Tomáš — zkušený obchodník v půjčovně motorek MotoGo24 (Mezná 9, 393 01 Pelhřimov). Mluvíš jako kámoš v motorkárně, ne jako chatbot. Znáš firmu i flotilu nazpaměť, znáš slang motorkářů (káva, naháč, japonáš, kawec, bavorák…), umíš poradit a hlavně — umíš ZAVŘÍT REZERVACI.

Tvá hlavní role:
- Vést zákazníka kompletním procesem rezervace — od výběru motorky až po Stripe Checkout odkaz.
- Odpovídat STRUČNĚ a POUZE na to, na co se zeptal. Žádné nevyžádané rady, marketingové fráze ani vychvalování.
- Pracovat s reálnými daty (search_motorcycles, get_availability, calculate_price, get_extras_catalog, get_branches, get_faq, validate_promo_or_voucher) a NIKDY si nic nevymýšlet.

Kompletní postup rezervace (chain of thought, ptej se postupně, jedna otázka za jeden tah):
1. Datum OD a DO. "Tento víkend / od pátku do neděle" převeď na konkrétní datumy podle dnešního data v hlavičce.
2. Výběr motorky. Pokud zákazník nemá konkrétní, zeptej se na ŘP a kategorii a pak search_motorcycles.
3. Dostupnost (get_availability) + kalkulace (calculate_price). Hned uveď cenu.
4. Vyzvednutí: na pobočce Mezná, nebo přistavení? (Pokud přistavení, zeptej se na adresu — jde do delivery_address.)
5. Vrácení: stejně jako vyzvednutí, nebo jinak? (return_address jen pokud mimo provozovnu.)
6. Příslušenství navíc — get_extras_catalog. Zeptej se jestli chce výbavu spolujezdce, boty řidič/spolujezdec, atd.
7. Velikosti výbavy řidiče (helmet/jacket/pants/boots/gloves) — výbava je v ceně, vždy vyplnit.
8. Kontakt: jméno, email, telefon. Pokud přistavení nebo zákazník chce, i adresa (street/city/zip).
9. Skupina ŘP (AM/A1/A2/A/B/N — N = bez ŘP, pro dětské motorky).
10. Promo kód / voucher (volitelné, ověř přes validate_promo_or_voucher).
11. SHRNUTÍ: zopakuj motorku, datum od-do, cenu, způsob vyzvednutí/vrácení, extras. Zeptej se: "Mám rezervaci vytvořit a poslat platební odkaz?"
12. Po explicitním ANO zavolej create_booking_request s VŠEMI sebranými parametry. Vrátí Stripe Checkout URL → pošli odkaz a krátké shrnutí (motorka, datum, částka).

Pokud zákazník nechce dokončit přes chat, použij redirect_to_booking → /rezervace?moto=...&start=...&end=... a pozvi ho dokončit na webu.`,
  situations: [
    'Když zákazník napíše "od X do Y" nebo "tento víkend", spočítej si konkrétní datumy z dnešního data v hlavičce systému.',
    'Když chybí jeden údaj, zeptej se POUZE na něj — nikdy nepokládej víc otázek najednou.',
    'Když zákazník schválí souhrn rezervace, zavolej create_booking_request a okamžitě pošli platební odkaz.',
    'Když user jen pozdraví ("ahoj"), pozdrav zpátky stejně neformálně a zeptej se 1 větou, co potřebuje.',
    'Když zákazník chce přistavení, zjisti přesnou adresu (ulice, město, PSČ) a předej ji jako delivery_address.',
    'Když zákazník napíše promo kód nebo voucher, vždy ho nejdřív ověř přes validate_promo_or_voucher.',
    'Když zákazník chce vědět, kolik stojí přistavení, vysvětli model 1000 Kč + 40 Kč/km a nasměruj na rezervační formulář pro přesný výpočet (Mapy.cz routing).',
    'Když se ptá na technický detail motorky (válce, výkon, váha, výška sedla, palivová nádrž obecně) → odpověz z vlastních znalostí o daném modelu. NIKDY neříkej "to nevím, zavolej".',
    'Když search_motorcycles vrátí 0 výsledků, NABÍDNI alternativu: jiná skupina ŘP (A2 ⇄ A pokud má 24+), jiná kategorie, podobný model. Doptej se co je důležitější.',
    'Když user tyká → tykej zpátky. Když vyká → vykej. Zrcadli ton.',
    'Když user řekne "máš kawu / BMW / yamahu na pondělí?", ZAVOLEJ search_motorcycles s `brand` + `available_on` a rovnou ukaž 1-3 dostupné kusy s cenou a CTA "kterou ti rezervuju?". NIKDY neinteroguj "jakou kategorii".',
    'Když user popíše styl jízdy (do hor / na výlety / začínám / dálnice), SÁM doporuč 2-3 konkrétní stroje z naší flotily s krátkým "proč zrovna tenhle" — ne katalog, ale výběr s názorem.',
    'Při rovnocenných možnostech vyber 2 — jednu cenovou a jednu prémiovou — a pojmenuj rozdíl jednou větou.',
    'Mluv lidsky a v slangu motorkářů, když je user neformální (káva, naháč, japonáš, kawec, bavorák, ducka, "tahá jak vlak", "drží se země"). Když je formální, drž profesionální tón.',
  ],
  forbidden: [
    'Nikdy si nevymýšlej NAŠE ceny, dostupnost, naši flotilu ani naše extras — ty VŽDY z toolů.',
    'Nikdy neodbývej zákazníka odkazem na +420 774 256 271 nebo info@motogo24.cz. Telefon dáš JEN když výslovně chce mluvit s člověkem, je to SOS, nebo právní záležitost.',
    'Nikdy nepoužívej AI fráze: "jako AI asistent…", "rád pomohu", "určitě, samozřejmě", "to bohužel nevím — zavolejte". Mluv jako prodavač půjčovny, ne chatbot.',
    'Nikdy neodpovídej na otázky, které ti nikdo nepoložil — žádné "také vám můžu...", "víte že...", marketingové fráze.',
    'Nikdy nepředpokládej rok — vždy si vezmi rok z hlavičky "DNES JE ..." v system promptu.',
    'Nikdy nevytvoř rezervaci, dokud nemáš jméno, email, telefon a explicitní souhlas zákazníka se shrnutím.',
    'Nikdy neodpovídej dlouhými odstavci — drž se 1-3 vět pokud uživatel sám nechce detail.',
    'Nikdy nepřepínej jazyk sám od sebe — odpovídej VŽDY ve stejném jazyce, jakým píše uživatel.',
    'Nikdy NEMÍCHEJ jazyky v jedné odpovědi (žádné "máme plusieurs modelů" nebo "let\\'s check dostupnost"). Drž jeden jazyk celou zprávu.',
    'Nikdy se nevyptávej zbytečně. Když máš dost dat (značka + datum), rovnou volej tool a ukaž výsledek.',
    'Nikdy neříkej "to nemůžu zkontrolovat" — vždy najdi tool, který to umí (search_motorcycles má brand, model_query, available_on, available_from/to).',
  ],
  mustDo: [
    'Vždy odpovídej v jazyce poslední uživatelské zprávy. Když uživatel přepne, přepni s ním.',
    'Vždy ber dnešní datum z hlavičky systémového promptu — to je zdroj pravdy.',
    'Vždy ZRCADLI komunikační styl: tyká → tykej, vyká → vykej, krátká zpráva → krátká odpověď.',
    'Vždy se DOPTEJ když nerozumíš — nikdy nepředpokládej a nikdy neodbývej "to nevím".',
    'Vždy na obecné motorkářské dotazy (technické specifikace modelu, jak se chová motorka, doporučení pro začátečníka, rozdíl naked/sport-tourer atd.) odpověz z vlastních znalostí — jsi AI, máš to v hlavě.',
    'Vždy potvrď zákazníkovi souhrn (motorka, datum, cena, způsob vyzvednutí) PŘED zavoláním create_booking_request.',
    'Vždy končí krátkou další otázkou nebo CTA, ne monologem.',
    'Vždy po vytvoření rezervace pošli platební odkaz jako jasný hyperlink a v 1-2 větách shrň motorku, datum, částku.',
  ],
  tone: 'concise',
  max_tokens: 800,
  enabled: true,
  // Per-language welcome messages
  welcome_cs: 'Čau, tady Tomáš z MotoGo24. Co bys potřeboval — vybrat káru, mrknout na termín, nebo rovnou jedem?',
  welcome_en: 'Hey, this is Tom from MotoGo24. What do you need — pick a bike, check a date, or shall we book it right away?',
  welcome_de: 'Servus, hier Tom von MotoGo24. Was brauchst du — ein Bike aussuchen, Termin prüfen oder gleich buchen?',
  knowledge_extra: '',  // freetext — sezonní akce, novinky, dočasné info; injektuje se do promptu
}

const TONE_OPTIONS = [
  { value: 'concise', label: 'Stručný', desc: 'Max 1-3 věty na odpověď' },
  { value: 'friendly', label: 'Přátelský', desc: 'Vlídný, neformální tón' },
  { value: 'professional', label: 'Profesionální', desc: 'Formální, věcný tón' },
  { value: 'detailed', label: 'Podrobný', desc: 'Detailní vysvětlení' },
]

function TagList({ items, onAdd, onRemove, placeholder, color, bgColor, borderColor, icon }) {
  const [val, setVal] = useState('')
  return (
    <div>
      {items.map((s, i) => (
        <div key={i} style={{ display: 'flex', alignItems: 'start', gap: 4, marginBottom: 3, padding: '4px 8px', borderRadius: 6, background: bgColor, border: `1px solid ${borderColor}`, fontSize: 11 }}>
          <span style={{ marginTop: 1 }}>{icon}</span>
          <span style={{ flex: 1, color }}>{s}</span>
          <button onClick={() => onRemove(i)} style={{ background: 'none', border: 'none', color: '#999', cursor: 'pointer', fontSize: 10, lineHeight: 1 }}>x</button>
        </div>
      ))}
      <div style={{ display: 'flex', gap: 4, marginTop: 4 }}>
        <input value={val} onChange={e => setVal(e.target.value)} placeholder={placeholder}
          onKeyDown={e => { if (e.key === 'Enter' && val.trim()) { onAdd(val.trim()); setVal('') } }}
          style={{ flex: 1, fontSize: 11, padding: '4px 8px', borderRadius: 6, border: '1px solid #d4e8e0' }} />
        <button onClick={() => { if (val.trim()) { onAdd(val.trim()); setVal('') } }}
          style={{ padding: '4px 10px', borderRadius: 6, border: 'none', background: bgColor, color, cursor: 'pointer', fontSize: 11, fontWeight: 700 }}>+</button>
      </div>
    </div>
  )
}

export default function WebAgentSettingsPanel() {
  const [config, setConfig] = useState(DEFAULT_CONFIG)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState(null)
  const [editingPrompt, setEditingPrompt] = useState(false)
  const [previewOpen, setPreviewOpen] = useState(false)

  useEffect(() => {
    async function load() {
      try {
        const { data, error: err } = await supabase
          .from('app_settings')
          .select('value')
          .eq('key', SETTINGS_KEY)
          .single()
        if (err && err.code !== 'PGRST116') {
          console.error('WebAgentSettings load error:', err)
        }
        if (data?.value) {
          setConfig({ ...DEFAULT_CONFIG, ...data.value })
        }
      } catch (e) {
        console.error('WebAgentSettings load error:', e)
      } finally {
        setLoading(false)
      }
    }
    load()
  }, [])

  async function saveConfig(newConfig) {
    const cfg = newConfig || config
    setSaving(true)
    setError(null)
    try {
      const { error: err } = await supabase
        .from('app_settings')
        .upsert({ key: SETTINGS_KEY, value: cfg }, { onConflict: 'key' })
      if (err) throw err
      setSaved(true)
      setTimeout(() => setSaved(false), 2000)
    } catch (e) {
      setError(e.message)
    } finally {
      setSaving(false)
    }
  }

  function updateField(field, value) {
    setConfig({ ...config, [field]: value })
  }

  function resetToDefault() {
    setConfig(DEFAULT_CONFIG)
    saveConfig(DEFAULT_CONFIG)
  }

  function buildPreview() {
    let text = config.system_prompt || ''
    if (config.tone) {
      const t = TONE_OPTIONS.find(o => o.value === config.tone)
      text += `\n\nTÓN KOMUNIKACE: ${t?.desc || config.tone}`
    }
    if (config.situations?.length > 0) {
      text += '\n\nSITUAČNÍ PRAVIDLA:'
      for (const s of config.situations) text += `\n- ${s}`
    }
    if (config.mustDo?.length > 0) {
      text += '\n\nVŽDY MUSÍ UDĚLAT:'
      for (const m of config.mustDo) text += `\n- ${m}`
    }
    if (config.forbidden?.length > 0) {
      text += '\n\nZAKÁZÁNO:'
      for (const f of config.forbidden) text += `\n- ${f}`
    }
    text += '\n\n[edge funkce navíc automaticky vloží: dnešní datum, identitu firmy, jazyk konverzace a fixní bezpečnostní pravidla]'
    return text
  }

  if (loading) {
    return <div style={{ textAlign: 'center', padding: 40, color: '#999', fontSize: 13 }}>Načítám nastavení web agenta...</div>
  }

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
        <div>
          <div style={{ fontSize: 15, fontWeight: 800, color: '#0f1a14' }}>
            Web AI asistent — motogo24.cz (chatovací bublina)
          </div>
          <div style={{ fontSize: 11, color: '#666', marginTop: 2 }}>
            Konfigurace asistenta na veřejném webu — ovlivňuje system prompt edge funkce ai-public-agent. Změny se projeví okamžitě.
          </div>
        </div>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          {saved && <span style={{ fontSize: 11, color: '#22c55e', fontWeight: 700 }}>Uloženo</span>}
          {error && <span style={{ fontSize: 11, color: '#dc2626' }}>{error}</span>}
          <Button small outline onClick={resetToDefault}>Reset</Button>
          <Button small green onClick={() => saveConfig()} disabled={saving}>
            {saving ? 'Ukládám...' : 'Uložit'}
          </Button>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 16, marginBottom: 16, flexWrap: 'wrap' }}>
        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#f8fcfa', flex: '0 0 auto' }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: '#666', marginBottom: 6 }}>Agent aktivní</div>
          <button onClick={() => updateField('enabled', !config.enabled)} style={{
            width: 48, height: 24, borderRadius: 12, border: 'none', cursor: 'pointer',
            background: config.enabled ? '#22c55e' : '#d1d5db', position: 'relative', transition: 'background 0.2s',
          }}>
            <span style={{
              position: 'absolute', top: 2, left: config.enabled ? 26 : 2, width: 20, height: 20,
              borderRadius: '50%', background: '#fff', transition: 'left 0.2s', boxShadow: '0 1px 3px rgba(0,0,0,0.2)',
            }} />
          </button>
        </div>

        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#f8fcfa', flex: 1, minWidth: 200 }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: '#666', marginBottom: 6 }}>Název role / persony</div>
          <input
            value={config.persona_name}
            onChange={e => updateField('persona_name', e.target.value)}
            placeholder="např. Rezervační asistent MotoGo24"
            style={{ width: '100%', fontSize: 13, padding: '6px 10px', borderRadius: 6, border: '1px solid #d4e8e0', fontWeight: 600 }}
          />
        </div>

        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#f8fcfa', flex: '0 0 auto', minWidth: 180 }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: '#666', marginBottom: 6 }}>Tón komunikace</div>
          <select
            value={config.tone}
            onChange={e => updateField('tone', e.target.value)}
            style={{ width: '100%', fontSize: 12, padding: '6px 10px', borderRadius: 6, border: '1px solid #d4e8e0' }}
          >
            {TONE_OPTIONS.map(t => (
              <option key={t.value} value={t.value}>{t.label} — {t.desc}</option>
            ))}
          </select>
        </div>

        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#f8fcfa', flex: '0 0 auto', minWidth: 140 }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: '#666', marginBottom: 6 }}>Max tokenů</div>
          <input
            type="number"
            value={config.max_tokens}
            onChange={e => updateField('max_tokens', parseInt(e.target.value) || 800)}
            min={256}
            max={4096}
            step={128}
            style={{ width: '100%', fontSize: 12, padding: '6px 10px', borderRadius: 6, border: '1px solid #d4e8e0' }}
          />
        </div>
      </div>

      <div style={{ marginBottom: 16, padding: '12px 16px', borderRadius: 10, border: '2px solid #d4e8e0', background: '#fff' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
          <span style={{ fontSize: 13, fontWeight: 700, color: '#0f1a14' }}>Systémový prompt (hlavní zadání pro web agenta)</span>
          <button onClick={() => setEditingPrompt(!editingPrompt)} style={{ fontSize: 11, color: '#2563eb', background: 'none', border: 'none', cursor: 'pointer', fontWeight: 600 }}>
            {editingPrompt ? 'Hotovo' : 'Upravit'}
          </button>
        </div>
        {editingPrompt ? (
          <textarea
            value={config.system_prompt}
            onChange={e => updateField('system_prompt', e.target.value)}
            style={{ width: '100%', minHeight: 200, fontSize: 12, padding: 10, borderRadius: 8, border: '1px solid #d4e8e0', resize: 'vertical', fontFamily: 'inherit', lineHeight: 1.6 }}
            placeholder="Zadej systémový prompt pro web AI agenta..."
          />
        ) : (
          <div style={{ fontSize: 12, color: '#444', padding: '8px 10px', borderRadius: 8, background: '#f8fcfa', border: '1px solid #e5ede9', lineHeight: 1.6, maxHeight: 160, overflow: 'auto', whiteSpace: 'pre-wrap' }}>
            {config.system_prompt || 'Prompt není nastaven'}
          </div>
        )}
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16 }}>
        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14', marginBottom: 8 }}>
            Situační pravidla ({(config.situations || []).length})
          </div>
          <TagList
            items={config.situations || []}
            onAdd={s => updateField('situations', [...(config.situations || []), s])}
            onRemove={i => updateField('situations', (config.situations || []).filter((_, j) => j !== i))}
            placeholder="Když nastane X, udělej Y..."
            color="#1a5c2e" bgColor="#dcfce7" borderColor="#bbf7d0" icon="O"
          />
        </div>

        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: '#2563eb', marginBottom: 8 }}>
            Vždy musí udělat ({(config.mustDo || []).length})
          </div>
          <TagList
            items={config.mustDo || []}
            onAdd={m => updateField('mustDo', [...(config.mustDo || []), m])}
            onRemove={i => updateField('mustDo', (config.mustDo || []).filter((_, j) => j !== i))}
            placeholder="Vždy při X udělej Y..."
            color="#1e40af" bgColor="#eff6ff" borderColor="#bfdbfe" icon="!"
          />
        </div>

        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: '#dc2626', marginBottom: 8 }}>
            Zakázáno ({(config.forbidden || []).length})
          </div>
          <TagList
            items={config.forbidden || []}
            onAdd={f => updateField('forbidden', [...(config.forbidden || []), f])}
            onRemove={i => updateField('forbidden', (config.forbidden || []).filter((_, j) => j !== i))}
            placeholder="Nikdy nedělej X..."
            color="#dc2626" bgColor="#fef2f2" borderColor="#fecaca" icon="X"
          />
        </div>

        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
            <span style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14' }}>Náhled promptu</span>
            <button onClick={() => setPreviewOpen(!previewOpen)} style={{ fontSize: 11, color: '#2563eb', background: 'none', border: 'none', cursor: 'pointer' }}>
              {previewOpen ? 'Skrýt' : 'Zobrazit'}
            </button>
          </div>
          {previewOpen ? (
            <div style={{ fontSize: 10, color: '#444', padding: '8px 10px', borderRadius: 8, background: '#f0f4f2', border: '1px solid #e5ede9', lineHeight: 1.5, maxHeight: 300, overflow: 'auto', whiteSpace: 'pre-wrap', fontFamily: 'monospace' }}>
              {buildPreview()}
            </div>
          ) : (
            <div style={{ fontSize: 11, color: '#999', padding: 8 }}>
              Klikněte na "Zobrazit" pro náhled kompletního promptu, který se odešle agentovi
            </div>
          )}
        </div>
      </div>

      <div style={{ marginBottom: 12, padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
        <div style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14', marginBottom: 8 }}>Uvítací hláška (per jazyk)</div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
          {[
            ['welcome_cs', 'CS'],
            ['welcome_en', 'EN'],
            ['welcome_de', 'DE'],
          ].map(([k, lbl]) => (
            <div key={k}>
              <div style={{ fontSize: 10, color: '#666', marginBottom: 3 }}>{lbl}</div>
              <textarea
                value={config[k] || ''}
                onChange={e => updateField(k, e.target.value)}
                rows={2}
                style={{ width: '100%', fontSize: 11, padding: 6, borderRadius: 6, border: '1px solid #d4e8e0', resize: 'vertical', fontFamily: 'inherit', lineHeight: 1.4 }}
              />
            </div>
          ))}
        </div>
      </div>

      <div style={{ marginBottom: 12, padding: '12px 16px', borderRadius: 10, border: '2px solid #fbbf24', background: '#fffbeb' }}>
        <div style={{ fontSize: 13, fontWeight: 700, color: '#92400e', marginBottom: 6 }}>
          Aktuální znalosti (sezonní akce, novinky, ad-hoc info)
        </div>
        <div style={{ fontSize: 11, color: '#78350f', marginBottom: 8, lineHeight: 1.5 }}>
          Cokoliv napíšeš sem, agent zná OKAMŽITĚ při příští otázce zákazníka — bez deploye edge funkce.
          Použij na: probíhající slevy, dočasně nedostupné motorky, nové modely co ještě nejsou v katalogu, otevírací hodiny pobočky o svátcích, info pro VIP zákazníky atd.
          <br/>Tato znalost má <strong>vyšší prioritu než COMPANY_BRAIN</strong> v edge funkci, pokud se jedna informace s druhou tluče.
        </div>
        <textarea
          value={config.knowledge_extra || ''}
          onChange={e => updateField('knowledge_extra', e.target.value)}
          placeholder="Např.: Akce duben 2026 — naked motorky -20 %.&#10;Yamaha MT-09 #2 (SPZ 1AB 2345) je do 3.5. v servisu, nenabízej.&#10;Pobočka Mezná je 1.5. zavřená, vyzvednutí přes self-service kód funguje normálně."
          rows={6}
          style={{ width: '100%', fontSize: 12, padding: 10, borderRadius: 8, border: '1px solid #fbbf24', resize: 'vertical', fontFamily: 'inherit', lineHeight: 1.5 }}
        />
      </div>

      <div style={{ padding: '10px 14px', borderRadius: 8, background: '#eff6ff', border: '1px solid #bfdbfe', fontSize: 11, color: '#1e40af', lineHeight: 1.5 }}>
        <strong>Jak to funguje:</strong> Konfigurace se ukládá do <code>app_settings.ai_public_agent_config</code>.
        Edge funkce <code>ai-public-agent</code> ji načítá při <strong>každém dotazu</strong> z chatu na motogo24.cz a sestavuje z ní system prompt.
        Změny se projeví okamžitě bez deploye.
        <br/><br/>
        <strong>Co agent ČTE ŽIVĚ z DB při každém dotazu</strong> (web změníš → agent ví hned):
        <ul style={{ margin: '4px 0 0 18px', padding: 0, listStyle: 'disc' }}>
          <li>Motorky, ceny, parametry — tabulka <code>motorcycles</code></li>
          <li>Dostupnost / obsazené termíny — RPC <code>get_moto_booked_dates</code></li>
          <li>Příslušenství a ceny extras — tabulka <code>extras_catalog</code></li>
          <li>Pobočky — tabulka <code>branches</code></li>
          <li>Promo kódy a vouchery — RPC <code>validate_promo_code</code> + <code>validate_voucher_code</code></li>
          <li>FAQ — <code>app_settings.site.faq</code> (CMS → Web texts → FAQ; když uložíš, agent ví hned)</li>
          <li>Aktuální znalosti — <code>app_settings.ai_public_agent_config.knowledge_extra</code> (textarea výše)</li>
        </ul>
        <br/>
        Edge funkce navíc automaticky doplní <strong>aktuální datum</strong>, fixní bezpečnostní pravidla (anti-halucinace, sales mindset, jazyková kázeň) a jazyk konverzace.
      </div>
    </div>
  )
}
