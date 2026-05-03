import { useState } from 'react'
import { supabase, supabaseUrl, supabaseAnonKey } from '../../lib/supabase'
import Button from '../ui/Button'

// Spustí překlad celého CS masteru (pages.*) přes edge fn `translate-pages-master`.
// Edge fn fetchne master z motogo24.cz/api/master.php, přeloží přes Anthropic,
// uloží do app_settings.pages_overlay.<page>.<lang>. Web čte živě, žádný FTP.
export default function TranslatePagesMasterButton() {
  const [running, setRunning] = useState(false)
  const [result, setResult] = useState(null)
  const [error, setError] = useState(null)

  async function run() {
    if (!confirm('Spustit překlad pages masteru do EN/DE/ES/FR/NL/PL? Volá Anthropic API pro každou kombinaci stránka × jazyk. Trvá 1–3 minuty.')) return
    setRunning(true); setResult(null); setError(null)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      const accessToken = session?.access_token || supabaseAnonKey
      const response = await fetch(`${supabaseUrl}/functions/v1/translate-pages-master`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'apikey': supabaseAnonKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({}),
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok || !data?.success) {
        throw new Error(data?.error || `HTTP ${response.status}`)
      }
      setResult(data)
    } catch (e) {
      setError(e?.message || String(e))
    } finally {
      setRunning(false)
    }
  }

  return (
    <div className="flex items-center gap-3 flex-wrap">
      <Button green onClick={run} disabled={running}>
        {running ? '🌍 Překládám pages master…' : '🌍 Přeložit pages master (vše)'}
      </Button>
      {result && (
        <span className="text-xs font-bold" style={{ color: result.errors ? '#dc2626' : '#16a34a' }}>
          Hotovo: {result.ok}/{result.total}
          {result.errors > 0 && ` (${result.errors} chyb)`}
        </span>
      )}
      {error && <span className="text-xs" style={{ color: '#dc2626' }}>Chyba: {error}</span>}
    </div>
  )
}
