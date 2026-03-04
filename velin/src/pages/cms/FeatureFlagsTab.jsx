import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'

export default function FeatureFlagsTab() {
  const [flags, setFlags] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    const { data, error: err } = await supabase
      .from('feature_flags')
      .select('*')
      .order('name')
    if (err) setError(err.message)
    else setFlags(data || [])
    setLoading(false)
  }

  async function toggle(flag) {
    const newEnabled = !flag.enabled
    const { error } = await supabase
      .from('feature_flags')
      .update({ enabled: newEnabled })
      .eq('id', flag.id)
    if (error) {
      setError(error.message)
      return
    }
    setFlags(f => f.map(fl => fl.id === flag.id ? { ...fl, enabled: newEnabled } : fl))
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: 'feature_flag_toggled',
        details: { flag: flag.name, enabled: newEnabled },
      })
    } catch {}
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  if (error) return <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>

  if (flags.length === 0) return <Card><p style={{ color: '#8aab99', fontSize: 13 }}>Žádné feature flags</p></Card>

  return (
    <div className="space-y-3">
      {flags.map(f => (
        <Card key={f.id}>
          <div className="flex items-center gap-4">
            <div className="flex-1">
              <div className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{f.name}</div>
              {f.description && (
                <div className="text-xs mt-1" style={{ color: '#8aab99' }}>{f.description}</div>
              )}
            </div>
            <ToggleSwitch enabled={f.enabled} onToggle={() => toggle(f)} />
          </div>
        </Card>
      ))}
    </div>
  )
}

function ToggleSwitch({ enabled, onToggle }) {
  return (
    <button
      onClick={onToggle}
      className="relative cursor-pointer transition-colors"
      style={{
        width: 48,
        height: 26,
        borderRadius: 13,
        background: enabled ? '#74FB71' : '#d4e8e0',
        border: 'none',
        padding: 0,
      }}
    >
      <span
        className="absolute top-1 transition-all rounded-full"
        style={{
          width: 18,
          height: 18,
          background: '#fff',
          left: enabled ? 26 : 4,
          boxShadow: '0 2px 4px rgba(0,0,0,.15)',
        }}
      />
    </button>
  )
}
