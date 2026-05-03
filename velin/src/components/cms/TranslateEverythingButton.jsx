import { useState } from 'react'
import { supabase, supabaseUrl, supabaseAnonKey } from '../../lib/supabase'
import { autoTranslate, TRANSLATE_TARGET_LANGS, pickTranslatableFields } from '../../lib/autoTranslate'
import Button from '../ui/Button'

// Jediný „přeložit všechno" workflow ve Velíně.
// Sekvenčně:
//  1) Pages master  — translate-pages-master edge fn (statika z pages_cs.php / data/)
//  2) cms_variables — backfill řádků s prázdným translations (kategorie 'web')
//  3) faq_items     — backfill question/answer
//  4) cms_pages     — backfill title/excerpt/content (blog)
// Každá fáze má vlastní progress, edge fn pro pages master se volá per-pair
// (action:'translate-one'), takže žádný edge fn timeout.

class TranslateAbort extends Error {
  constructor(message, code) {
    super(message)
    this.code = code
    this.abort = true
  }
}

async function callEdge(body) {
  const { data: { session } } = await supabase.auth.getSession()
  const accessToken = session?.access_token || supabaseAnonKey
  const response = await fetch(`${supabaseUrl}/functions/v1/translate-pages-master`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'apikey': supabaseAnonKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) {
    if (data?.abort) throw new TranslateAbort(data.error || `HTTP ${response.status}`, data.code)
    throw new Error(data?.error || `HTTP ${response.status}`)
  }
  return data
}

const PHASES = [
  { key: 'pages',         label: 'Pages master (statika)' },
  { key: 'cms_variables', label: 'CMS proměnné (web.*)' },
  { key: 'faq_items',     label: 'FAQ položky' },
  { key: 'cms_pages',     label: 'Blog články' },
]

function rowsNeedingTranslation(table, rows) {
  return (rows || []).filter(row => {
    const fields = pickTranslatableFields(table, row)
    if (Object.keys(fields).length === 0) return false
    const tr = row.translations || {}
    return TRANSLATE_TARGET_LANGS.some(lang => {
      const langTr = tr[lang]
      if (!langTr || typeof langTr !== 'object') return true
      return Object.keys(fields).some(f => !langTr[f] || String(langTr[f]).trim() === '')
    })
  })
}

export default function TranslateEverythingButton() {
  const [running, setRunning] = useState(false)
  const [phase, setPhase] = useState(null)         // 'pages' | 'cms_variables' | …
  const [progress, setProgress] = useState({ done: 0, total: 0, current: '' })
  const [errors, setErrors] = useState([])         // [{phase, label, error}]
  const [doneSummary, setDoneSummary] = useState(null)

  async function run() {
    if (!confirm('Spustit překlad VŠEHO do EN/DE/ES/FR/NL/PL? Trvá 5–15 minut, projde pages master + cms_variables + FAQ + blog. Můžeš zavřít kartu — překlady už uložené v DB zůstanou.')) return
    setRunning(true); setPhase(null); setErrors([]); setDoneSummary(null)
    const newErrors = []

    let abortAll = null  // pokud je nastavený → přeskoč zbytek workflow (insufficient_credits / invalid_api_key)

    // ===== Fáze 1 — Pages master přes edge fn =====
    try {
      setPhase('pages')
      const list = await callEdge({ action: 'list' })
      const queue = list.queue || []
      setProgress({ done: 0, total: queue.length, current: '' })
      for (let i = 0; i < queue.length; i++) {
        const { page, lang } = queue[i]
        setProgress({ done: i, total: queue.length, current: `${page} → ${lang}` })
        try {
          await callEdge({ action: 'translate-one', page, lang })
        } catch (e) {
          newErrors.push({ phase: 'pages', label: `${page}/${lang}`, error: e.message })
          if (e.abort) { abortAll = e; break }
        }
      }
      setProgress(p => ({ ...p, done: queue.length, current: '' }))
    } catch (e) {
      newErrors.push({ phase: 'pages', label: 'list', error: e.message })
      if (e.abort) abortAll = e
    }

    // ===== Fáze 2-4 — DB backfill =====
    if (abortAll) {
      // Anthropic kredit/klíč — fáze 2-4 by jen spamovaly stejný error 100×
      setPhase(null); setErrors(newErrors)
      setDoneSummary({ errors: newErrors.length, abort: abortAll.code || 'aborted', abortMsg: abortAll.message })
      setRunning(false)
      return
    }
    const dbPhases = [
      { key: 'cms_variables', selectColumns: 'id, key, value, translations, category', filter: r => r.category === 'web', labelOf: r => r.key },
      { key: 'faq_items',     selectColumns: 'id, question, answer, translations',     filter: null,                       labelOf: r => r.question },
      { key: 'cms_pages',     selectColumns: 'id, title, excerpt, content, translations', filter: null,                    labelOf: r => r.title },
    ]
    for (const ph of dbPhases) {
      setPhase(ph.key)
      try {
        const { data, error } = await supabase.from(ph.key).select(ph.selectColumns)
        if (error) throw error
        const rows = ph.filter ? (data || []).filter(ph.filter) : (data || [])
        const candidates = rowsNeedingTranslation(ph.key, rows)
        setProgress({ done: 0, total: candidates.length, current: '' })
        for (let i = 0; i < candidates.length; i++) {
          const row = candidates[i]
          setProgress({ done: i, total: candidates.length, current: String(ph.labelOf(row) || row.id).slice(0, 60) })
          const fields = pickTranslatableFields(ph.key, row)
          const r = await autoTranslate({ table: ph.key, id: row.id, fields })
          if (!r.success) newErrors.push({ phase: ph.key, label: String(ph.labelOf(row) || row.id).slice(0, 80), error: r.error })
          if (r.abort) { abortAll = { code: r.code, message: r.error }; break }
        }
        setProgress(p => ({ ...p, done: candidates.length, current: '' }))
      } catch (e) {
        newErrors.push({ phase: ph.key, label: 'load', error: e.message })
      }
      if (abortAll) break
    }

    setPhase(null); setErrors(newErrors)
    setDoneSummary({ errors: newErrors.length, abort: abortAll?.code, abortMsg: abortAll?.message })
    setRunning(false)
  }

  const phaseLabel = PHASES.find(p => p.key === phase)?.label || ''
  const pct = progress.total > 0 ? Math.round((progress.done / progress.total) * 100) : 0
  const phaseIdx = PHASES.findIndex(p => p.key === phase)

  return (
    <div>
      <div className="flex items-center gap-3 flex-wrap">
        <Button green onClick={run} disabled={running}>
          {running
            ? `🌍 Fáze ${phaseIdx + 1}/4 · ${progress.done}/${progress.total} (${pct}%)`
            : '🌍 Přeložit vše do EN/DE/ES/FR/NL/PL'}
        </Button>
        {running && (
          <span className="text-xs font-bold" style={{ color: '#1d4ed8' }}>
            {phaseLabel} {progress.current && <span style={{ color: '#6b8f7b' }}>· {progress.current}</span>}
          </span>
        )}
        {!running && doneSummary && (
          <span className="text-xs font-bold" style={{ color: doneSummary.errors ? '#dc2626' : '#16a34a' }}>
            {doneSummary.errors ? `Hotovo s ${doneSummary.errors} chybami` : 'Hotovo bez chyb'}
          </span>
        )}
      </div>
      {!running && doneSummary?.abort === 'insufficient_credits' && (
        <div className="mt-3 rounded-btn text-sm" style={{ padding: '10px 14px', background: '#fff7ed', border: '1px solid #fdba74', color: '#7c2d12' }}>
          <strong>Anthropic API kredit vyčerpán.</strong> Workflow zastaveno hned po prvním selhání (jinak by se 60+ requestů snažilo o totéž).
          Doplň kredit na <a href="https://console.anthropic.com/settings/billing" target="_blank" rel="noreferrer" style={{ textDecoration: 'underline' }}>console.anthropic.com → Plans &amp; Billing</a> nebo přepni na jiný klíč v Supabase secrets (<code>ANTHROPIC_API_KEY</code>).
        </div>
      )}
      {!running && doneSummary?.abort === 'invalid_api_key' && (
        <div className="mt-3 rounded-btn text-sm" style={{ padding: '10px 14px', background: '#fef2f2', border: '1px solid #fca5a5', color: '#7f1d1d' }}>
          <strong>Neplatný Anthropic API klíč.</strong> Aktualizuj sekret <code>ANTHROPIC_API_KEY</code> v Supabase Edge Functions (Project Settings → Edge Functions → Secrets).
        </div>
      )}
      {!running && errors.length > 0 && (
        <details className="mt-2">
          <summary className="text-xs cursor-pointer" style={{ color: '#dc2626' }}>
            Zobrazit {errors.length} chyb
          </summary>
          <ul className="text-xs mt-2 space-y-1" style={{ color: '#6b8f7b' }}>
            {errors.slice(0, 50).map((e, i) => (
              <li key={i}><code>[{e.phase}]</code> {e.label}: {e.error}</li>
            ))}
            {errors.length > 50 && <li>… a dalších {errors.length - 50}</li>}
          </ul>
        </details>
      )}
    </div>
  )
}
