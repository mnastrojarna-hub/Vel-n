// Společné stavební bloky pro nastavení AI agentů ve Velíně.
// Sdílí: WebAgentSettingsPanel (web bublina), AppAgentSettingsPanel (SOS v appce),
//        CustomerMessagesAgentSettingsPanel (správce zákaznických zpráv).
//
// Cíl: jednotný UX/UI a jeden zdroj pravdy pro layout, ukládání do app_settings,
// preview promptu a per-jazyk welcome hlášky. Funkční chování každého agenta
// se liší jen v DEFAULT_CONFIG, dodatečných sekcích (kanály, schvalování apod.)
// a v napojené edge funkci.

import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../ui/Button'

// ─────────────────────────────────────────────────────────────────────────────
// Konstanty
// ─────────────────────────────────────────────────────────────────────────────

export const DEFAULT_TONE_OPTIONS = [
  { value: 'concise', label: 'Stručný', desc: 'Max 1-3 věty na odpověď' },
  { value: 'friendly', label: 'Přátelský', desc: 'Vlídný, neformální tón' },
  { value: 'professional', label: 'Profesionální', desc: 'Formální, věcný tón' },
  { value: 'detailed', label: 'Podrobný', desc: 'Detailní vysvětlení' },
]

// ─────────────────────────────────────────────────────────────────────────────
// useAgentConfig — load/save z app_settings.<key>
// ─────────────────────────────────────────────────────────────────────────────

export function useAgentConfig(settingsKey, defaultConfig) {
  const [config, setConfig] = useState(defaultConfig)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState(null)

  useEffect(() => {
    let cancelled = false
    async function load() {
      try {
        const { data, error: err } = await supabase
          .from('app_settings')
          .select('value')
          .eq('key', settingsKey)
          .maybeSingle()
        if (err && err.code !== 'PGRST116') {
          console.error(`[${settingsKey}] load error:`, err)
        }
        if (!cancelled && data?.value) {
          setConfig({ ...defaultConfig, ...data.value })
        }
      } catch (e) {
        if (!cancelled) console.error(`[${settingsKey}] load error:`, e)
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    load()
    return () => { cancelled = true }
  }, [settingsKey])

  const saveConfig = useCallback(async (next) => {
    const cfg = next || config
    setSaving(true)
    setError(null)
    try {
      const { error: err } = await supabase
        .from('app_settings')
        .upsert({ key: settingsKey, value: cfg }, { onConflict: 'key' })
      if (err) throw err
      setSaved(true)
      setTimeout(() => setSaved(false), 2000)
    } catch (e) {
      setError(e.message)
    } finally {
      setSaving(false)
    }
  }, [config, settingsKey])

  const updateField = useCallback((field, value) => {
    setConfig(prev => ({ ...prev, [field]: value }))
  }, [])

  const resetToDefault = useCallback(() => {
    setConfig(defaultConfig)
    saveConfig(defaultConfig)
  }, [defaultConfig, saveConfig])

  return { config, setConfig, loading, saving, saved, error, saveConfig, updateField, resetToDefault }
}

// ─────────────────────────────────────────────────────────────────────────────
// PanelHeader — titulek + popis + Save/Reset
// ─────────────────────────────────────────────────────────────────────────────

export function PanelHeader({ title, subtitle, saved, error, saving, onSave, onReset }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
      <div>
        <div style={{ fontSize: 15, fontWeight: 800, color: '#0f1a14' }}>{title}</div>
        {subtitle && <div style={{ fontSize: 11, color: '#666', marginTop: 2 }}>{subtitle}</div>}
      </div>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
        {saved && <span style={{ fontSize: 11, color: '#22c55e', fontWeight: 700 }}>Uloženo</span>}
        {error && <span style={{ fontSize: 11, color: '#dc2626' }}>{error}</span>}
        {onReset && <Button small outline onClick={onReset}>Reset</Button>}
        <Button small green onClick={onSave} disabled={saving}>
          {saving ? 'Ukládám...' : 'Uložit'}
        </Button>
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// CommonControls — řádek: enabled + persona + tone + max_tokens
// ─────────────────────────────────────────────────────────────────────────────

export function CommonControls({
  config,
  onChange,
  toneOptions = DEFAULT_TONE_OPTIONS,
  maxTokensDefault = 800,
  maxTokensMin = 256,
  maxTokensMax = 4096,
  maxTokensStep = 128,
  personaPlaceholder = 'např. Rezervační asistent',
  extras,
}) {
  return (
    <div style={{ display: 'flex', gap: 16, marginBottom: 16, flexWrap: 'wrap' }}>
      <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#f8fcfa', flex: '0 0 auto' }}>
        <div style={{ fontSize: 11, fontWeight: 700, color: '#666', marginBottom: 6 }}>Agent aktivní</div>
        <button onClick={() => onChange('enabled', !config.enabled)} style={{
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
          value={config.persona_name || ''}
          onChange={e => onChange('persona_name', e.target.value)}
          placeholder={personaPlaceholder}
          style={{ width: '100%', fontSize: 13, padding: '6px 10px', borderRadius: 6, border: '1px solid #d4e8e0', fontWeight: 600 }}
        />
      </div>

      <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#f8fcfa', flex: '0 0 auto', minWidth: 180 }}>
        <div style={{ fontSize: 11, fontWeight: 700, color: '#666', marginBottom: 6 }}>Tón komunikace</div>
        <select
          value={config.tone}
          onChange={e => onChange('tone', e.target.value)}
          style={{ width: '100%', fontSize: 12, padding: '6px 10px', borderRadius: 6, border: '1px solid #d4e8e0' }}
        >
          {toneOptions.map(t => (
            <option key={t.value} value={t.value}>{t.label} — {t.desc}</option>
          ))}
        </select>
      </div>

      <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#f8fcfa', flex: '0 0 auto', minWidth: 140 }}>
        <div style={{ fontSize: 11, fontWeight: 700, color: '#666', marginBottom: 6 }}>Max tokenů</div>
        <input
          type="number"
          value={config.max_tokens}
          onChange={e => onChange('max_tokens', parseInt(e.target.value) || maxTokensDefault)}
          min={maxTokensMin}
          max={maxTokensMax}
          step={maxTokensStep}
          style={{ width: '100%', fontSize: 12, padding: '6px 10px', borderRadius: 6, border: '1px solid #d4e8e0' }}
        />
      </div>

      {extras}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// PromptEditor — textarea s toggle "Upravit/Hotovo"
// ─────────────────────────────────────────────────────────────────────────────

export function PromptEditor({ value, onChange, label = 'Systémový prompt (hlavní zadání pro agenta)', minHeight = 160 }) {
  const [editing, setEditing] = useState(false)
  return (
    <div style={{ marginBottom: 16, padding: '12px 16px', borderRadius: 10, border: '2px solid #d4e8e0', background: '#fff' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
        <span style={{ fontSize: 13, fontWeight: 700, color: '#0f1a14' }}>{label}</span>
        <button onClick={() => setEditing(!editing)} style={{ fontSize: 11, color: '#2563eb', background: 'none', border: 'none', cursor: 'pointer', fontWeight: 600 }}>
          {editing ? 'Hotovo' : 'Upravit'}
        </button>
      </div>
      {editing ? (
        <textarea
          value={value || ''}
          onChange={e => onChange(e.target.value)}
          style={{ width: '100%', minHeight, fontSize: 12, padding: 10, borderRadius: 8, border: '1px solid #d4e8e0', resize: 'vertical', fontFamily: 'inherit', lineHeight: 1.6 }}
          placeholder="Zadej systémový prompt..."
        />
      ) : (
        <div style={{ fontSize: 12, color: '#444', padding: '8px 10px', borderRadius: 8, background: '#f8fcfa', border: '1px solid #e5ede9', lineHeight: 1.6, maxHeight: 160, overflow: 'auto', whiteSpace: 'pre-wrap' }}>
          {value || 'Prompt není nastaven'}
        </div>
      )}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// TagList — vstup pro situations / mustDo / forbidden
// ─────────────────────────────────────────────────────────────────────────────

export function TagList({ items, onAdd, onRemove, placeholder, color, bgColor, borderColor, icon }) {
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

// ─────────────────────────────────────────────────────────────────────────────
// RulesGrid — situations + mustDo + forbidden + preview promptu
// ─────────────────────────────────────────────────────────────────────────────

export function RulesGrid({ config, onChange, buildPreview }) {
  const [previewOpen, setPreviewOpen] = useState(false)
  const situations = config.situations || []
  const mustDo = config.mustDo || []
  const forbidden = config.forbidden || []
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16 }}>
      <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
        <div style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14', marginBottom: 8 }}>
          Situační pravidla ({situations.length})
        </div>
        <TagList
          items={situations}
          onAdd={s => onChange('situations', [...situations, s])}
          onRemove={i => onChange('situations', situations.filter((_, j) => j !== i))}
          placeholder="Když nastane X, udělej Y..."
          color="#1a5c2e" bgColor="#dcfce7" borderColor="#bbf7d0" icon="O"
        />
      </div>

      <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
        <div style={{ fontSize: 12, fontWeight: 700, color: '#2563eb', marginBottom: 8 }}>
          Vždy musí udělat ({mustDo.length})
        </div>
        <TagList
          items={mustDo}
          onAdd={m => onChange('mustDo', [...mustDo, m])}
          onRemove={i => onChange('mustDo', mustDo.filter((_, j) => j !== i))}
          placeholder="Vždy při X udělej Y..."
          color="#1e40af" bgColor="#eff6ff" borderColor="#bfdbfe" icon="!"
        />
      </div>

      <div style={{ padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
        <div style={{ fontSize: 12, fontWeight: 700, color: '#dc2626', marginBottom: 8 }}>
          Zakázáno ({forbidden.length})
        </div>
        <TagList
          items={forbidden}
          onAdd={f => onChange('forbidden', [...forbidden, f])}
          onRemove={i => onChange('forbidden', forbidden.filter((_, j) => j !== i))}
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
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// WelcomeLangBlock — uvítací hláška per jazyk (CS/EN/DE)
// ─────────────────────────────────────────────────────────────────────────────

export function WelcomeLangBlock({
  config,
  onChange,
  languages = [['welcome_cs', 'CS'], ['welcome_en', 'EN'], ['welcome_de', 'DE']],
  label = 'Uvítací hláška (per jazyk)',
  hint,
}) {
  return (
    <div style={{ marginBottom: 12, padding: '12px 16px', borderRadius: 10, border: '1px solid #d4e8e0', background: '#fff' }}>
      <div style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14', marginBottom: hint ? 4 : 8 }}>{label}</div>
      {hint && <div style={{ fontSize: 10, color: '#777', marginBottom: 8, lineHeight: 1.4 }}>{hint}</div>}
      <div style={{ display: 'grid', gridTemplateColumns: `repeat(${languages.length}, 1fr)`, gap: 8 }}>
        {languages.map(([k, lbl]) => (
          <div key={k}>
            <div style={{ fontSize: 10, color: '#666', marginBottom: 3 }}>{lbl}</div>
            <textarea
              value={config[k] || ''}
              onChange={e => onChange(k, e.target.value)}
              rows={4}
              style={{ width: '100%', fontSize: 11, padding: 6, borderRadius: 6, border: '1px solid #d4e8e0', resize: 'vertical', fontFamily: 'inherit', lineHeight: 1.4 }}
            />
          </div>
        ))}
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// KnowledgeExtraBlock — žlutý box pro sezonní info
// ─────────────────────────────────────────────────────────────────────────────

export function KnowledgeExtraBlock({
  value,
  onChange,
  label = 'Aktuální znalosti (sezonní akce, novinky, ad-hoc info)',
  helpText,
  placeholder,
  rows = 6,
}) {
  return (
    <div style={{ marginBottom: 12, padding: '12px 16px', borderRadius: 10, border: '2px solid #fbbf24', background: '#fffbeb' }}>
      <div style={{ fontSize: 13, fontWeight: 700, color: '#92400e', marginBottom: 6 }}>{label}</div>
      {helpText && (
        <div style={{ fontSize: 11, color: '#78350f', marginBottom: 8, lineHeight: 1.5 }}>{helpText}</div>
      )}
      <textarea
        value={value || ''}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        rows={rows}
        style={{ width: '100%', fontSize: 12, padding: 10, borderRadius: 8, border: '1px solid #fbbf24', resize: 'vertical', fontFamily: 'inherit', lineHeight: 1.5 }}
      />
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// InfoBox — barevný informační box dole pod panelem
// ─────────────────────────────────────────────────────────────────────────────

export function InfoBox({ children, color = 'blue' }) {
  const palette = {
    blue:  { bg: '#eff6ff', border: '#bfdbfe', text: '#1e40af' },
    red:   { bg: '#fef2f2', border: '#fecaca', text: '#991b1b' },
    green: { bg: '#f0fdf4', border: '#bbf7d0', text: '#166534' },
    amber: { bg: '#fffbeb', border: '#fcd34d', text: '#92400e' },
  }
  const c = palette[color] || palette.blue
  return (
    <div style={{ padding: '10px 14px', borderRadius: 8, background: c.bg, border: `1px solid ${c.border}`, fontSize: 11, color: c.text, lineHeight: 1.5, marginBottom: 12 }}>
      {children}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// buildSystemPromptPreview — společná logika náhledu
// ─────────────────────────────────────────────────────────────────────────────

export function buildSystemPromptPreview(config, toneOptions = DEFAULT_TONE_OPTIONS, opts = {}) {
  let text = config.system_prompt || ''
  if (config.tone) {
    const t = toneOptions.find(o => o.value === config.tone)
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
  if (config.knowledge_extra?.trim()) {
    text += '\n\nAKTUÁLNÍ ZNALOSTI Z VELÍNU:\n' + config.knowledge_extra.trim()
  }
  if (opts.footer) text += `\n\n${opts.footer}`
  return text
}
