import { useState } from 'react'
import { AGENTS } from '../../lib/aiAgents'
import { getAgentPrompt, updateAgentPrompt } from '../../lib/aiAgentPrompts'
import { getLongTermMemory, addLongTermMemory, removeLongTermMemory, clearLongTermMemory, getFlashMemory, clearFlashMemory, MEMORY_CATEGORIES } from '../../lib/aiAgentMemory'

export default function AiAgentConfig({ agentId, onClose }) {
  const agent = AGENTS.find(a => a.id === agentId)
  if (!agent) return null

  const [promptData, setPromptData] = useState(() => getAgentPrompt(agentId))
  const [longMem, setLongMem] = useState(() => getLongTermMemory(agentId))
  const [flashMem] = useState(() => getFlashMemory(agentId))
  const [newSituation, setNewSituation] = useState('')
  const [newForbidden, setNewForbidden] = useState('')
  const [newMemory, setNewMemory] = useState('')
  const [memCat, setMemCat] = useState('general')
  const [tab, setTab] = useState('prompt')
  const [saved, setSaved] = useState(false)

  function save(data) {
    const next = { ...promptData, ...data }
    setPromptData(next)
    updateAgentPrompt(agentId, next)
    setSaved(true)
    setTimeout(() => setSaved(false), 1500)
  }

  function addSituation() {
    if (!newSituation.trim()) return
    save({ situations: [...(promptData.situations || []), newSituation.trim()] })
    setNewSituation('')
  }

  function removeSituation(idx) {
    save({ situations: (promptData.situations || []).filter((_, i) => i !== idx) })
  }

  function addForbiddenItem() {
    if (!newForbidden.trim()) return
    save({ forbidden: [...(promptData.forbidden || []), newForbidden.trim()] })
    setNewForbidden('')
  }

  function removeForbiddenItem(idx) {
    save({ forbidden: (promptData.forbidden || []).filter((_, i) => i !== idx) })
  }

  function addMem() {
    if (!newMemory.trim()) return
    setLongMem(addLongTermMemory(agentId, newMemory.trim(), memCat))
    setNewMemory('')
  }

  const tabs = [
    { id: 'prompt', label: 'Zadání', icon: '📝' },
    { id: 'situations', label: 'Situace', icon: '🎯' },
    { id: 'forbidden', label: 'Zakázáno', icon: '🚫' },
    { id: 'memory_long', label: 'Paměť', icon: '🧠' },
    { id: 'memory_flash', label: 'Flash', icon: '⚡' },
  ]

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 9999, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(0,0,0,0.5)' }}>
      <div style={{ background: '#fff', borderRadius: 16, width: '90%', maxWidth: 640, maxHeight: '85vh', overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {/* Header */}
        <div style={{ padding: '14px 18px', borderBottom: '2px solid #d4e8e0', display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ fontSize: 22 }}>{agent.icon}</span>
          <div style={{ flex: 1 }}>
            <div style={{ fontWeight: 800, fontSize: 15, color: '#0f1a14' }}>{agent.name}</div>
            <div style={{ fontSize: 11, color: '#666' }}>{agent.desc}</div>
          </div>
          {saved && <span style={{ fontSize: 11, color: '#22c55e', fontWeight: 600 }}>Uloženo</span>}
          <button onClick={onClose} style={{ background: 'none', border: 'none', fontSize: 18, cursor: 'pointer', color: '#999' }}>✕</button>
        </div>

        {/* Tabs */}
        <div style={{ display: 'flex', borderBottom: '1px solid #d4e8e0' }}>
          {tabs.map(t => (
            <button key={t.id} onClick={() => setTab(t.id)} style={{
              flex: 1, padding: '8px 4px', fontSize: 11, fontWeight: tab === t.id ? 700 : 400, border: 'none', cursor: 'pointer',
              background: tab === t.id ? '#f1faf7' : '#fff', color: tab === t.id ? '#0f1a14' : '#999',
              borderBottom: tab === t.id ? '2px solid #74FB71' : 'none',
            }}>{t.icon} {t.label}</button>
          ))}
        </div>

        {/* Content */}
        <div style={{ flex: 1, overflow: 'auto', padding: 16 }}>
          {/* PROMPT */}
          {tab === 'prompt' && (
            <div>
              <div style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14', marginBottom: 6 }}>Systémový prompt (zadání agenta)</div>
              <textarea value={promptData.prompt || ''} onChange={e => setPromptData({ ...promptData, prompt: e.target.value })}
                onBlur={() => save({ prompt: promptData.prompt })}
                style={{ width: '100%', minHeight: 200, fontSize: 12, padding: 10, borderRadius: 8, border: '1px solid #d4e8e0', resize: 'vertical', fontFamily: 'inherit', lineHeight: 1.6 }}
              />
              <div style={{ fontSize: 11, color: '#999', marginTop: 4 }}>Tento text říká agentovi KDO je a CO má dělat. Upravte dle potřeby.</div>
            </div>
          )}

          {/* SITUATIONS */}
          {tab === 'situations' && (
            <div>
              <div style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14', marginBottom: 6 }}>Situační pravidla — jak se zachovat v konkrétních případech</div>
              {(promptData.situations || []).map((s, i) => (
                <div key={i} style={{ display: 'flex', alignItems: 'start', gap: 6, marginBottom: 6, padding: '6px 8px', borderRadius: 6, background: '#f1faf7', border: '1px solid #d4e8e0' }}>
                  <span style={{ fontSize: 12, color: '#22c55e', marginTop: 1 }}>🎯</span>
                  <span style={{ flex: 1, fontSize: 12, color: '#1a2e22' }}>{s}</span>
                  <button onClick={() => removeSituation(i)} style={{ background: 'none', border: 'none', color: '#dc2626', cursor: 'pointer', fontSize: 12 }}>✕</button>
                </div>
              ))}
              <div style={{ display: 'flex', gap: 6, marginTop: 8 }}>
                <input value={newSituation} onChange={e => setNewSituation(e.target.value)} placeholder="Když nastane situace X, udělej Y..."
                  onKeyDown={e => e.key === 'Enter' && addSituation()}
                  style={{ flex: 1, fontSize: 12, padding: '6px 10px', borderRadius: 6, border: '1px solid #d4e8e0' }} />
                <button onClick={addSituation} style={{ padding: '6px 12px', borderRadius: 6, border: 'none', background: '#74FB71', cursor: 'pointer', fontSize: 12, fontWeight: 700 }}>+ Přidat</button>
              </div>
            </div>
          )}

          {/* FORBIDDEN */}
          {tab === 'forbidden' && (
            <div>
              <div style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14', marginBottom: 6 }}>Zakázané akce — co agent NESMÍ dělat</div>
              {(promptData.forbidden || []).map((f, i) => (
                <div key={i} style={{ display: 'flex', alignItems: 'start', gap: 6, marginBottom: 6, padding: '6px 8px', borderRadius: 6, background: '#fef2f2', border: '1px solid #fecaca' }}>
                  <span style={{ fontSize: 12, marginTop: 1 }}>🚫</span>
                  <span style={{ flex: 1, fontSize: 12, color: '#dc2626' }}>{f}</span>
                  <button onClick={() => removeForbiddenItem(i)} style={{ background: 'none', border: 'none', color: '#dc2626', cursor: 'pointer', fontSize: 12 }}>✕</button>
                </div>
              ))}
              <div style={{ display: 'flex', gap: 6, marginTop: 8 }}>
                <input value={newForbidden} onChange={e => setNewForbidden(e.target.value)} placeholder="Nikdy nedělej X..."
                  onKeyDown={e => e.key === 'Enter' && addForbiddenItem()}
                  style={{ flex: 1, fontSize: 12, padding: '6px 10px', borderRadius: 6, border: '1px solid #d4e8e0' }} />
                <button onClick={addForbiddenItem} style={{ padding: '6px 12px', borderRadius: 6, border: 'none', background: '#fee2e2', color: '#dc2626', cursor: 'pointer', fontSize: 12, fontWeight: 700 }}>+ Přidat</button>
              </div>
            </div>
          )}

          {/* LONG-TERM MEMORY */}
          {tab === 'memory_long' && (
            <div>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
                <div style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14' }}>Dlouhodobá paměť ({longMem.length} záznamů)</div>
                {longMem.length > 0 && <button onClick={() => { clearLongTermMemory(agentId); setLongMem([]) }} style={{ fontSize: 11, color: '#dc2626', background: 'none', border: 'none', cursor: 'pointer' }}>Vymazat vše</button>}
              </div>
              {longMem.map((m, i) => (
                <div key={i} style={{ display: 'flex', alignItems: 'start', gap: 6, marginBottom: 4, padding: '5px 8px', borderRadius: 6, background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
                  <span style={{ fontSize: 11 }}>{MEMORY_CATEGORIES[m.category]?.icon || '📝'}</span>
                  <div style={{ flex: 1 }}>
                    <span style={{ fontSize: 12, color: '#1a2e22' }}>{m.text}</span>
                    <div style={{ fontSize: 10, color: '#999' }}>{new Date(m.timestamp).toLocaleString('cs-CZ')}</div>
                  </div>
                  <button onClick={() => setLongMem(removeLongTermMemory(agentId, i))} style={{ background: 'none', border: 'none', color: '#999', cursor: 'pointer', fontSize: 11 }}>✕</button>
                </div>
              ))}
              <div style={{ display: 'flex', gap: 4, marginTop: 8 }}>
                <select value={memCat} onChange={e => setMemCat(e.target.value)} style={{ fontSize: 11, padding: '4px 6px', borderRadius: 4, border: '1px solid #d4e8e0' }}>
                  {Object.entries(MEMORY_CATEGORIES).map(([k, v]) => <option key={k} value={k}>{v.icon} {v.label}</option>)}
                </select>
                <input value={newMemory} onChange={e => setNewMemory(e.target.value)} placeholder="Zapamatuj si, že..."
                  onKeyDown={e => e.key === 'Enter' && addMem()}
                  style={{ flex: 1, fontSize: 12, padding: '6px 10px', borderRadius: 6, border: '1px solid #d4e8e0' }} />
                <button onClick={addMem} style={{ padding: '6px 10px', borderRadius: 6, border: 'none', background: '#74FB71', cursor: 'pointer', fontSize: 12, fontWeight: 700 }}>+</button>
              </div>
            </div>
          )}

          {/* FLASH MEMORY */}
          {tab === 'memory_flash' && (
            <div>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
                <div style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14' }}>Flash paměť — aktuální session ({flashMem.length} záznamů)</div>
                {flashMem.length > 0 && <button onClick={() => clearFlashMemory(agentId)} style={{ fontSize: 11, color: '#dc2626', background: 'none', border: 'none', cursor: 'pointer' }}>Vymazat</button>}
              </div>
              <div style={{ fontSize: 11, color: '#999', marginBottom: 8 }}>Automaticky se plní během konverzace. Vymazáno při zavření prohlížeče.</div>
              {flashMem.length === 0 && <div style={{ fontSize: 12, color: '#999', textAlign: 'center', padding: 20 }}>Zatím žádné záznamy v aktuální session</div>}
              {flashMem.map((m, i) => (
                <div key={i} style={{ padding: '4px 8px', borderRadius: 4, marginBottom: 3, background: '#fffbeb', border: '1px solid #fde68a', fontSize: 11, color: '#92400e' }}>
                  ⚡ {m.text} <span style={{ color: '#999' }}>({new Date(m.timestamp).toLocaleTimeString('cs-CZ')})</span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
