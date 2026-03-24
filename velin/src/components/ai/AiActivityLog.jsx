import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { AGENTS } from '../../lib/aiAgents'

export default function AiActivityLog({ limit = 20 }) {
  const [actions, setActions] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      const { data } = await supabase
        .from('ai_actions')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(limit)
      setActions(data || [])
    } catch { setActions([]) }
    finally { setLoading(false) }
  }

  function getAgentForTool(tool) {
    for (const a of AGENTS) {
      if (a.tools.includes(tool) || a.readTools.includes(tool)) return a
    }
    return null
  }

  if (loading) return <div className="text-sm" style={{ color: '#999', padding: 12 }}>Načítám aktivitu...</div>

  if (actions.length === 0) return (
    <div className="text-sm" style={{ color: '#999', textAlign: 'center', padding: 20 }}>
      Zatím žádná AI aktivita
    </div>
  )

  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>AI Aktivita ({actions.length})</span>
        <button onClick={load} style={{ fontSize: 11, color: '#2563eb', background: 'none', border: 'none', cursor: 'pointer' }}>Obnovit</button>
      </div>
      <div style={{ maxHeight: 400, overflow: 'auto' }}>
        {actions.map((a, i) => {
          const agent = getAgentForTool(a.tool)
          const isOk = a.success !== false
          return (
            <div key={a.id || i} style={{
              padding: '8px 10px', marginBottom: 4, borderRadius: 8,
              border: '1px solid ' + (isOk ? '#d4e8e0' : '#fecaca'),
              background: isOk ? '#f8fcfa' : '#fef2f2',
            }}>
              <div className="flex items-center gap-2">
                <span style={{ fontSize: 13 }}>{agent?.icon || '⚙️'}</span>
                <span className="text-sm font-bold" style={{ color: '#0f1a14', flex: 1 }}>
                  {a.tool}
                </span>
                <span style={{
                  fontSize: 10, padding: '1px 6px', borderRadius: 8,
                  background: isOk ? '#dcfce7' : '#fee2e2',
                  color: isOk ? '#166534' : '#dc2626',
                  fontWeight: 600,
                }}>
                  {isOk ? 'OK' : 'CHYBA'}
                </span>
              </div>
              {a.result?.summary && (
                <div className="text-sm mt-1" style={{ color: '#666', fontSize: 11 }}>
                  {a.result.summary}
                </div>
              )}
              <div className="text-sm" style={{ color: '#999', fontSize: 10, marginTop: 2 }}>
                {a.created_at ? new Date(a.created_at).toLocaleString('cs-CZ') : ''}
                {agent ? ` — ${agent.name}` : ''}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
