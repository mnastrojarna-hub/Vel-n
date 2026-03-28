import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../ui/Button'

const SETTINGS_KEY = 'ai_moto_agent_config'

const DEFAULT_CONFIG = {
  persona_name: 'AI Servisni technik',
  system_prompt: `Jsi AI servisni technik MotoGo24 — pujcovny motorek. Zakaznici te kontaktuji pres SOS sekci v aplikaci kdyz maji problem s motorkou na ceste.

Tve hlavni ukoly:
- Diagnostika zavad na zaklade popisu nebo fotek (kontrolky, zvuky, chovani motorky)
- Navod na obsluhu konkretni motorky zakaznika (tu kterou ma v rezervaci)
- Posouzeni zda je motorka pojizdna nebo ne
- Doporuceni SOS (odtah, nahradni motorka) pokud je zavada vazna

Diagnosticky postup:
1. Upresni problem — ptej se na detaily (ktere svetlo, kdy to zacalo, jaky zvuk)
2. Pozadej o fotku palubni desky / problemu pokud zakaznik neposlal
3. Az mas dost informaci, dej konkretni radu pro dany model motorky
4. Pokud je zavada vazna (motor nejede, unik oleje, prehrati) — doporuc SOS

Nikdy nedavej dlouhy seznam moznych pricin na vagni popis. Misto toho se PTEJ.

Kontakt na SOS: +420 774 256 271 (24/7)`,
  situations: [
    'Kdyz zakaznik posle fotku kontrolky, analyzuj ji a dej konkretni radu pro jeho model',
    'Kdyz zakaznik popisuje vaznou zavadu (unik oleje, prehrati, motor nejede), doporuc SOS a nastav suggest_sos=true',
    'Kdyz zakaznik nevi jak ovladat motorku (svetla, startovani, rezim jizdy), najdi info pres get_motorcycle_manual',
    'Kdyz zakaznik rika ze motorka nejede, proved diagnostiku: neutral, spojka, kill switch, stojan, palivo',
  ],
  forbidden: [
    'Nikdy si nevymyslej nazvy motorek, parametry ani postupy',
    'Nikdy neuvarej jinou motorku nez tu, kterou ma zakaznik v rezervaci',
    'Nikdy nerad zakaznikovi aby sam opravoval motorku (neni jeho majetek)',
    'Nikdy nedoporucuj pokracovat v jizde pokud je motorka nepojizdna',
  ],
  mustDo: [
    'Vzdy se zeptej na detaily problemu nez das radu',
    'Vzdy pozadej o fotku pokud zakaznik neposlal',
    'Pri vazne zavade vzdy doporuc SOS a nastav suggest_sos=true',
    'Vzdy odpovidej pro konkretni model motorky zakaznika (z rezervace)',
  ],
  tone: 'friendly',
  max_tokens: 2048,
  enabled: true,
}

const TONE_OPTIONS = [
  { value: 'friendly', label: 'Pratelsky', desc: 'Vlidny, neformalni ton' },
  { value: 'professional', label: 'Profesionalni', desc: 'Formalni, vecny ton' },
  { value: 'concise', label: 'Strucny', desc: 'Maximalne kratke odpovedi' },
  { value: 'detailed', label: 'Podrobny', desc: 'Detailni vysvetleni' },
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

export default function AppAgentSettingsPanel() {
  const [config, setConfig] = useState(DEFAULT_CONFIG)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState(null)
  const [editingPrompt, setEditingPrompt] = useState(false)
  const [previewOpen, setPreviewOpen] = useState(false)

  // Load settings from app_settings table
  useEffect(() => {
    async function load() {
      try {
        const { data, error: err } = await supabase
          .from('app_settings')
          .select('value')
          .eq('key', SETTINGS_KEY)
          .single()

        if (err && err.code !== 'PGRST116') {
          console.error('AppAgentSettings load error:', err)
        }
        if (data?.value) {
          setConfig({ ...DEFAULT_CONFIG, ...data.value })
        }
      } catch (e) {
        console.error('AppAgentSettings load error:', e)
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
    const next = { ...config, [field]: value }
    setConfig(next)
  }

  function resetToDefault() {
    setConfig(DEFAULT_CONFIG)
    saveConfig(DEFAULT_CONFIG)
  }

  // Build preview of how the prompt will look
  function buildPreview() {
    let text = config.system_prompt || ''
    if (config.tone) {
      const t = TONE_OPTIONS.find(o => o.value === config.tone)
      text += `\n\nTON KOMUNIKACE: ${t?.desc || config.tone}`
    }
    if (config.situations?.length > 0) {
      text += '\n\nSITUACNI PRAVIDLA:'
      for (const s of config.situations) text += `\n- ${s}`
    }
    if (config.mustDo?.length > 0) {
      text += '\n\nVZDY MUSI UDELAT:'
      for (const m of config.mustDo) text += `\n- ${m}`
    }
    if (config.forbidden?.length > 0) {
      text += '\n\nZAKAZANO:'
      for (const f of config.forbidden) text += `\n- ${f}`
    }
    return text
  }

  if (loading) {
    return <div style={{ textAlign: 'center', padding: 40, color: '#999', fontSize: 13 }}>Nacitam nastaveni agenta...</div>
  }

  return (
    <div>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
        <div>
          <div style={{ fontSize: 15, fontWeight: 800, color: '#0f1a14' }}>
            AI Servisni technik — SOS v aplikaci
          </div>
          <div style={{ fontSize: 11, color: '#666', marginTop: 2 }}>
            Konfigurace AI agenta v SOS sekci mobilni appky — diagnostika zavad, pomoc na ceste, doporuceni SOS
          </div>
        </div>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          {saved && <span style={{ fontSize: 11, color: '#22c55e', fontWeight: 700 }}>Ulozeno</span>}
          {error && <span style={{ fontSize: 11, color: '#dc2626' }}>{error}</span>}
          <Button small outline onClick={resetToDefault}>Reset</Button>
          <Button small green onClick={() => saveConfig()} disabled={saving}>
            {saving ? 'Ukladam...' : 'Ulozit'}
          </Button>
        </div>
      </div>

      {/* Enable/disable + persona name */}
      <div style={{ display: 'flex', gap: 16, marginBottom: 16, flexWrap: 'wrap' }}>
        {/* Enabled toggle */}
        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#f8fcfa', flex: '0 0 auto' }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: '#666', marginBottom: 6 }}>Agent aktivni</div>
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

        {/* Persona name */}
        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#f8fcfa', flex: 1, minWidth: 200 }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: '#666', marginBottom: 6 }}>Nazev role / persony</div>
          <input
            value={config.persona_name}
            onChange={e => updateField('persona_name', e.target.value)}
            placeholder="napr. Spravce zakazniku, Servisni technik..."
            style={{ width: '100%', fontSize: 13, padding: '6px 10px', borderRadius: 6, border: '1px solid #d4e8e0', fontWeight: 600 }}
          />
        </div>

        {/* Tone */}
        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#f8fcfa', flex: '0 0 auto', minWidth: 180 }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: '#666', marginBottom: 6 }}>Ton komunikace</div>
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

        {/* Max tokens */}
        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#f8fcfa', flex: '0 0 auto', minWidth: 140 }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: '#666', marginBottom: 6 }}>Max tokeny</div>
          <input
            type="number"
            value={config.max_tokens}
            onChange={e => updateField('max_tokens', parseInt(e.target.value) || 2048)}
            min={512}
            max={4096}
            step={256}
            style={{ width: '100%', fontSize: 12, padding: '6px 10px', borderRadius: 6, border: '1px solid #d4e8e0' }}
          />
        </div>
      </div>

      {/* System prompt */}
      <div style={{ marginBottom: 16, padding: '12px 16px', borderRadius: 10, border: '2px solid #d4e8e0', background: '#fff' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
          <span style={{ fontSize: 13, fontWeight: 700, color: '#0f1a14' }}>Systemovy prompt (hlavni zadani pro agenta)</span>
          <button onClick={() => setEditingPrompt(!editingPrompt)} style={{ fontSize: 11, color: '#2563eb', background: 'none', border: 'none', cursor: 'pointer', fontWeight: 600 }}>
            {editingPrompt ? 'Hotovo' : 'Upravit'}
          </button>
        </div>
        {editingPrompt ? (
          <textarea
            value={config.system_prompt}
            onChange={e => updateField('system_prompt', e.target.value)}
            style={{ width: '100%', minHeight: 160, fontSize: 12, padding: 10, borderRadius: 8, border: '1px solid #d4e8e0', resize: 'vertical', fontFamily: 'inherit', lineHeight: 1.6 }}
            placeholder="Zadej systemovy prompt pro AI agenta..."
          />
        ) : (
          <div style={{ fontSize: 12, color: '#444', padding: '8px 10px', borderRadius: 8, background: '#f8fcfa', border: '1px solid #e5ede9', lineHeight: 1.6, maxHeight: 120, overflow: 'auto', whiteSpace: 'pre-wrap' }}>
            {config.system_prompt || 'Prompt neni nastaven'}
          </div>
        )}
      </div>

      {/* Rules grid */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16 }}>
        {/* Situations */}
        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14', marginBottom: 8 }}>
            Situacni pravidla ({(config.situations || []).length})
          </div>
          <TagList
            items={config.situations || []}
            onAdd={s => updateField('situations', [...(config.situations || []), s])}
            onRemove={i => updateField('situations', (config.situations || []).filter((_, j) => j !== i))}
            placeholder="Kdyz nastane X, udelej Y..."
            color="#1a5c2e" bgColor="#dcfce7" borderColor="#bbf7d0" icon="O"
          />
        </div>

        {/* Must do */}
        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: '#2563eb', marginBottom: 8 }}>
            Vzdy musi udelat ({(config.mustDo || []).length})
          </div>
          <TagList
            items={config.mustDo || []}
            onAdd={m => updateField('mustDo', [...(config.mustDo || []), m])}
            onRemove={i => updateField('mustDo', (config.mustDo || []).filter((_, j) => j !== i))}
            placeholder="Vzdy pri X udelej Y..."
            color="#1e40af" bgColor="#eff6ff" borderColor="#bfdbfe" icon="!"
          />
        </div>

        {/* Forbidden */}
        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: '#dc2626', marginBottom: 8 }}>
            Zakazano ({(config.forbidden || []).length})
          </div>
          <TagList
            items={config.forbidden || []}
            onAdd={f => updateField('forbidden', [...(config.forbidden || []), f])}
            onRemove={i => updateField('forbidden', (config.forbidden || []).filter((_, j) => j !== i))}
            placeholder="Nikdy nedelej X..."
            color="#dc2626" bgColor="#fef2f2" borderColor="#fecaca" icon="X"
          />
        </div>

        {/* Preview */}
        <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
            <span style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14' }}>Nahled promptu</span>
            <button onClick={() => setPreviewOpen(!previewOpen)} style={{ fontSize: 11, color: '#2563eb', background: 'none', border: 'none', cursor: 'pointer' }}>
              {previewOpen ? 'Skryt' : 'Zobrazit'}
            </button>
          </div>
          {previewOpen ? (
            <div style={{ fontSize: 10, color: '#444', padding: '8px 10px', borderRadius: 8, background: '#f0f4f2', border: '1px solid #e5ede9', lineHeight: 1.5, maxHeight: 300, overflow: 'auto', whiteSpace: 'pre-wrap', fontFamily: 'monospace' }}>
              {buildPreview()}
            </div>
          ) : (
            <div style={{ fontSize: 11, color: '#999', padding: 8 }}>
              Kliknete na "Zobrazit" pro nahled kompletniho promptu, ktery se odesle AI agentovi
            </div>
          )}
        </div>
      </div>

      {/* SOS flow info */}
      <div style={{ padding: '10px 14px', borderRadius: 8, background: '#fef2f2', border: '1px solid #fecaca', fontSize: 11, color: '#991b1b', lineHeight: 1.5, marginBottom: 12 }}>
        <strong>SOS flow v appce:</strong> Zakaznik otevre SOS sekci &rarr; klikne na "AI Asistent" kartu &rarr;
        popisuje problem / posila fotky &rarr; agent diagnostikuje a radi &rarr;
        pri vazne zavade doporuci SOS (cervene tlacitko pro volani +420 774 256 271).
      </div>

      {/* Info box */}
      <div style={{ padding: '10px 14px', borderRadius: 8, background: '#eff6ff', border: '1px solid #bfdbfe', fontSize: 11, color: '#1e40af', lineHeight: 1.5 }}>
        <strong>Jak to funguje:</strong> Nastaveni se uklada do <code>app_settings</code> v Supabase.
        Edge funkce <code>ai-moto-agent</code> si pri kazdem dotazu zakaznika nacte tuto konfiguraci a pouzije ji jako systemovy prompt.
        Zmeny se projevi okamzite. Bezpecnostni pravidla (nevymyslet data, format odpovedi, SOS JSON blok) jsou vzdy pridana automaticky.
      </div>
    </div>
  )
}
