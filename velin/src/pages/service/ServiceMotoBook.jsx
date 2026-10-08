import { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import StatusBadge from '../../components/ui/StatusBadge'
import ServiceBook from '../../components/fleet/ServiceBook'
import { canSeeSection } from '../../lib/velinSections'

/** /servis/motorka/:id — servisní knížka motorky pro sekci Servis (i účet bez přístupu do Flotily). */
export default function ServiceMotoBook({ admin }) {
  const { id } = useParams()
  const navigate = useNavigate()
  const [moto, setMoto] = useState(null)
  useEffect(() => { supabase.from('motorcycles').select('id, model, spz, status, branches(name)').eq('id', id).single().then(({ data }) => setMoto(data || null)) }, [id])
  const canFleet = canSeeSection(admin, 'fleet')
  return (
    <div>
      <div className="flex items-center gap-3 mb-5 flex-wrap">
        <button onClick={() => navigate('/servis?tab=kniha')} className="cursor-pointer" style={{ background: 'none', border: 'none', fontSize: 18, color: '#1a2e22' }}>←</button>
        <h2 className="font-extrabold text-lg" style={{ color: '#0f1a14' }}>Servisní knížka · {moto?.model || '…'}</h2>
        {moto && <StatusBadge status={moto.status} />}
        <span className="text-sm font-mono" style={{ color: '#1a2e22' }}>{moto?.spz}</span>
        <span className="text-sm" style={{ color: '#6b7280' }}>{moto?.branches?.name}</span>
        {canFleet && <button onClick={() => navigate(`/flotila/${id}`)} className="ml-auto rounded-btn text-sm font-extrabold uppercase cursor-pointer" style={{ padding: '6px 14px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>Detail motorky</button>}
      </div>
      <ServiceBook motoId={id} />
    </div>
  )
}
