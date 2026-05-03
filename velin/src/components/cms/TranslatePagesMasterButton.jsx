import { useState } from 'react'
import { supabase, supabaseUrl, supabaseAnonKey } from '../../lib/supabase'
import Button from '../ui/Button'

// Spustí překlad CS masteru pages do EN/DE/ES/FR/NL/PL přes edge fn
// `translate-pages-master`. Aby se vyhnulo timeoutu Supabase fn:
// 1) `action:'list'` → vrátí frontu {page, lang} dvojic
// 2) per dvojice volá `action:'translate-one'` (3-8 s každá)
// Výsledky jdou do app_settings.pages_overlay.<page>.<lang>; PHP siteContent
// je čte živě → web na všech doménách aktualizován bez FTP.
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
  if (!response.ok) throw new Error(data?.error || `HTTP ${response.status}`)
  return data
}

export default function TranslatePagesMasterButton() {
  const [running, setRunning] = useState(false)
  const [progress, setProgress] = useState({ done: 0, total: 0, errors: 0, current: '' })
  const [error, setError] = useState(null)

  async function run() {
    if (!confirm('Spustit překlad pages masteru? Volá Anthropic API pro každou stránku × jazyk (~80 volání). Trvá 5–10 minut. Můžeš zavřít kartu — běží na pozadí v Supabase, ale ztratíš progress UI.')) return
    setRunning(true); setError(null); setProgress({ done: 0, total: 0, errors: 0, current: '' })

    try {
      const list = await callEdge({ action: 'list' })
      const queue = list.queue || []
      setProgress(p => ({ ...p, total: queue.length }))
      let errors = 0
      for (let i = 0; i < queue.length; i++) {
        const { page, lang } = queue[i]
        setProgress({ done: i, total: queue.length, errors, current: `${page} → ${lang}` })
        try {
          await callEdge({ action: 'translate-one', page, lang })
        } catch (e) {
          errors++
          console.warn(`[translate-pages-master] ${page}/${lang}:`, e.message)
        }
      }
      setProgress({ done: queue.length, total: queue.length, errors, current: '' })
    } catch (e) {
      setError(e?.message || String(e))
    } finally {
      setRunning(false)
    }
  }

  const pct = progress.total > 0 ? Math.round((progress.done / progress.total) * 100) : 0

  return (
    <div className="flex items-center gap-3 flex-wrap">
      <Button green onClick={run} disabled={running}>
        {running
          ? `🌍 ${progress.done}/${progress.total} (${pct}%)…`
          : '🌍 Přeložit pages master (vše)'}
      </Button>
      {running && progress.current && (
        <span className="text-xs font-mono" style={{ color: '#6b8f7b' }}>{progress.current}</span>
      )}
      {!running && progress.total > 0 && (
        <span className="text-xs font-bold" style={{ color: progress.errors ? '#dc2626' : '#16a34a' }}>
          Hotovo: {progress.done - progress.errors}/{progress.total}
          {progress.errors > 0 && ` (${progress.errors} chyb)`}
        </span>
      )}
      {error && <span className="text-xs" style={{ color: '#dc2626' }}>Chyba: {error}</span>}
    </div>
  )
}
