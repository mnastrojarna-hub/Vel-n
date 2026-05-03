import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { autoTranslate, TRANSLATE_TARGET_LANGS, pickTranslatableFields } from '../../lib/autoTranslate'
import Button from '../ui/Button'

// Backfill chybějících překladů pro tabulku s `translations` JSONB sloupcem.
// Najde řádky, kterým chybí překlad alespoň v jednom jazyku z TRANSLATE_TARGET_LANGS,
// a sériově je dopřekládá přes edge fn `translate-content`.
export default function TranslationBackfillButton({
  table,
  selectColumns = '*',
  filterPredicate,
  label = 'Doplnit chybějící překlady',
  onDone,
}) {
  const [running, setRunning] = useState(false)
  const [progress, setProgress] = useState({ done: 0, total: 0, errors: 0, current: '' })

  async function run() {
    if (!confirm(`Spustit doplnění překladů pro tabulku "${table}"? Volá Anthropic API pro každý řádek bez kompletních překladů.`)) return
    setRunning(true)
    setProgress({ done: 0, total: 0, errors: 0, current: '' })

    const { data, error } = await supabase.from(table).select(selectColumns)
    if (error) {
      alert('Chyba při načítání: ' + error.message)
      setRunning(false)
      return
    }

    const candidates = (data || []).filter(row => {
      if (filterPredicate && !filterPredicate(row)) return false
      const fields = pickTranslatableFields(table, row)
      if (Object.keys(fields).length === 0) return false
      const tr = row.translations || {}
      // chybí překlad alespoň v jednom target jazyku → zařadit
      return TRANSLATE_TARGET_LANGS.some(lang => {
        const langTr = tr[lang]
        if (!langTr || typeof langTr !== 'object') return true
        return Object.keys(fields).some(f => !langTr[f] || String(langTr[f]).trim() === '')
      })
    })

    setProgress(p => ({ ...p, total: candidates.length }))
    let errors = 0
    for (let i = 0; i < candidates.length; i++) {
      const row = candidates[i]
      const fields = pickTranslatableFields(table, row)
      const labelStr = row.title || row.question || row.key || row.id
      setProgress({ done: i, total: candidates.length, errors, current: String(labelStr).slice(0, 60) })
      const r = await autoTranslate({ table, id: row.id, fields })
      if (!r.success) errors++
    }
    setProgress(p => ({ ...p, done: candidates.length, errors, current: '' }))
    setRunning(false)
    onDone?.()
  }

  return (
    <div className="flex items-center gap-3">
      <Button onClick={run} disabled={running}>
        {running ? `🌍 Překládám ${progress.done}/${progress.total}…` : `🌍 ${label}`}
      </Button>
      {running && progress.current && (
        <span className="text-xs" style={{ color: '#6b8f7b' }}>{progress.current}</span>
      )}
      {!running && progress.total > 0 && (
        <span className="text-xs font-bold" style={{ color: progress.errors ? '#dc2626' : '#16a34a' }}>
          Hotovo: {progress.done - progress.errors}/{progress.total}
          {progress.errors > 0 && ` (${progress.errors} chyb)`}
        </span>
      )}
    </div>
  )
}
