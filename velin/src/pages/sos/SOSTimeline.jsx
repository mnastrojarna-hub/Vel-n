import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'


export default function SOSTimeline({ incidentId }) {
  const [events, setEvents] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    // Reset state when incident changes to prevent stale data
    setEvents([])
    setLoading(true)
    if (incidentId) load()
    else setLoading(false)
  }, [incidentId])

  async function load() {
    setLoading(true)
    const { data } = await supabase
      .from('sos_timeline')
      .select('*')
      .eq('incident_id', incidentId)
      .order('created_at')
    setEvents(data || [])
    setLoading(false)
  }

  if (loading) return <div className="text-xs py-2" style={{ color: '#8aab99' }}>Načítám timeline…</div>

  if (events.length === 0) return <div className="text-xs py-2" style={{ color: '#8aab99' }}>Žádné záznamy v timeline</div>

  return (
    <div className="space-y-2 mt-3">
      <div className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Timeline</div>
      {events.map(e => (
        <div key={e.id} className="flex items-start gap-2">
          <div className="mt-1.5 w-2 h-2 rounded-full shrink-0" style={{ background: '#74FB71' }} />
          <div>
            <div className="text-xs font-bold" style={{ color: '#0f1a14' }}>{e.action || e.description || '—'}</div>
            {e.data?.note && <div className="text-[10px]" style={{ color: '#4a6357' }}>{e.data.note}</div>}
            {e.data?.latitude && e.data?.longitude && (
              <a href={`https://www.google.com/maps?q=${e.data.latitude},${e.data.longitude}`}
                target="_blank" rel="noopener noreferrer"
                className="inline-flex items-center gap-1 text-[10px] font-bold px-1.5 py-0.5 rounded-btn mt-0.5"
                style={{ background: '#dbeafe', color: '#2563eb', textDecoration: 'none' }}>
                GPS: {Number(e.data.latitude).toFixed(5)}, {Number(e.data.longitude).toFixed(5)}
              </a>
            )}
            <div className="text-[10px]" style={{ color: '#8aab99' }}>
              {e.created_at ? new Date(e.created_at).toLocaleString('cs-CZ') : ''}
              {e.performed_by && ` · ${e.performed_by}`}
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}
