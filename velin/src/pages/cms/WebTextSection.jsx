import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { autoTranslate } from '../../lib/autoTranslate'

export default function WebTextSection({ section, values, onSaved }) {
  const [open, setOpen] = useState(false)
  const filled = section.fields.filter(f => values[f.key]).length

  return (
    <div className="mb-3 rounded-card" style={{ background: '#fff', border: '1px solid #e2ece7' }}>
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center gap-3 cursor-pointer"
        style={{ padding: '14px 16px', background: 'none', border: 'none', textAlign: 'left' }}
      >
        <span style={{ fontSize: 18, transform: open ? 'rotate(90deg)' : 'none', transition: 'transform .15s' }}>&#9654;</span>
        <div className="flex-1">
          <div className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{section.label}</div>
          <div className="text-xs mt-0.5" style={{ color: '#6b8f7b' }}>{section.location}</div>
        </div>
        <span
          className="text-xs font-bold rounded-btn"
          style={{
            padding: '2px 8px',
            background: filled === section.fields.length ? '#dcfce7' : '#fef3c7',
            color: filled === section.fields.length ? '#16a34a' : '#b45309',
          }}
        >
          {filled}/{section.fields.length}
        </span>
      </button>

      {open && (
        <div style={{ padding: '0 16px 16px', borderTop: '1px solid #e2ece7' }}>
          {section.fields.map(field => (
            <FieldRow key={field.key} field={field} value={values[field.key]} onSaved={onSaved} />
          ))}
        </div>
      )}
    </div>
  )
}

function FieldRow({ field, value, onSaved }) {
  const currentVal = value ?? field.default ?? ''
  const [val, setVal] = useState(currentVal)
  const [saving, setSaving] = useState(false)
  const [translating, setTranslating] = useState(false)
  const [saved, setSaved] = useState(false)
  const changed = val !== currentVal

  async function save() {
    setSaving(true)
    // Check if key exists, then insert or update
    const { data: existing } = await supabase
      .from('cms_variables')
      .select('id')
      .eq('key', field.key)
      .maybeSingle()

    let error
    let rowId = existing?.id
    if (existing) {
      const res = await supabase.from('cms_variables').update({ value: val }).eq('key', field.key)
      error = res.error
    } else {
      const res = await supabase.from('cms_variables').insert({ key: field.key, value: val, group: 'web' }).select().single()
      error = res.error
      rowId = res?.data?.id
    }
    setSaving(false)
    if (!error) {
      setSaved(true)
      setTimeout(() => setSaved(false), 2000)
      onSaved?.(field.key, val)
      // Auto-překlad pro web (na pozadí, jen pro non-empty)
      if (rowId && typeof val === 'string' && val.trim().length > 0) {
        setTranslating(true)
        autoTranslate({ table: 'cms_variables', id: rowId, fields: { value: val } })
          .finally(() => setTranslating(false))
      }
    }
  }

  const isTextarea = field.type === 'textarea' || (val && val.length > 80)
  const hasValue = !!value

  return (
    <div className="mt-3">
      <div className="flex items-center gap-2 mb-1">
        <span
          className="inline-block w-2 h-2 rounded-full shrink-0"
          style={{ background: hasValue ? '#22c55e' : '#d4d4d8' }}
          title={hasValue ? 'Uloženo v DB' : 'Výchozí hodnota (neuloženo)'}
        />
        <span className="text-xs font-extrabold uppercase" style={{ color: '#1a2e22' }}>{field.label}</span>
        {field.hint && (
          <span className="text-xs" style={{ color: '#9ab3a5', fontStyle: 'italic' }}>{field.hint}</span>
        )}
        {!hasValue && (
          <span className="text-xs" style={{ color: '#d97706' }}>výchozí</span>
        )}
      </div>
      <div className="flex gap-2 items-start">
        {isTextarea ? (
          <textarea
            value={val}
            onChange={e => setVal(e.target.value)}
            className="flex-1 rounded-btn text-sm outline-none"
            style={{
              padding: '8px 12px', minHeight: 70, resize: 'vertical',
              background: changed ? '#fef3c7' : '#f1faf7',
              border: '1px solid ' + (changed ? '#f59e0b' : '#d4e8e0'),
            }}
          />
        ) : (
          <input
            value={val}
            onChange={e => setVal(e.target.value)}
            className="flex-1 rounded-btn text-sm outline-none"
            style={{
              padding: '8px 12px',
              background: changed ? '#fef3c7' : '#f1faf7',
              border: '1px solid ' + (changed ? '#f59e0b' : '#d4e8e0'),
            }}
          />
        )}
        {changed && (
          <button
            onClick={save}
            disabled={saving}
            className="rounded-btn text-xs font-extrabold uppercase cursor-pointer shrink-0"
            style={{ padding: '8px 14px', background: '#74FB71', color: '#1a2e22', border: 'none' }}
          >
            {saving ? '...' : 'Uložit'}
          </button>
        )}
        {!changed && saved && (
          <span className="text-xs font-bold" style={{ color: '#22c55e', padding: '8px 0' }}>
            {translating ? '🌍 Překládám…' : 'Uloženo'}
          </span>
        )}
        {!changed && !saved && translating && (
          <span className="text-xs font-bold" style={{ color: '#1d4ed8', padding: '8px 0' }}>🌍 Překládám…</span>
        )}
      </div>
    </div>
  )
}
