import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { CATEGORY_LABELS, ASSET_TYPE_LABELS, PAYMENT_LABELS, DOC_TYPE_MAP, SOURCE_LABELS } from './financialEventsConstants'

export function MiniLabel({ label, value, mono }) {
  return (
    <div className="mb-1">
      <span className="text-[9px] font-extrabold uppercase tracking-wide" style={{ color: '#6b7280' }}>{label}: </span>
      <span className={`text-sm font-bold ${mono ? 'font-mono' : ''}`} style={{ color: '#1a2e22' }}>{value}</span>
    </div>
  )
}

export function StatCard({ label, value, color }) {
  return (
    <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-lg font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}

export default function EventDetail({ event }) {
  const ai = event.metadata?.ai_classification
  const meta = event.metadata || {}
  const assetCls = ai?.asset_type || meta.asset_classification?.type || null
  const deprGroup = ai?.depreciation_group || meta.asset_classification?.depreciation_group || null
  const deprYears = ai?.depreciation_years || meta.asset_classification?.depreciation_years || null
  const deprMethod = ai?.depreciation_method || meta.asset_classification?.depreciation_method || null
  const storagePath = meta.storage_path
  const [photoUrl, setPhotoUrl] = useState(null)
  const [photoLoading, setPhotoLoading] = useState(false)

  async function loadPhoto() {
    if (!storagePath || photoUrl) return
    setPhotoLoading(true)
    try {
      const { data } = await supabase.storage.from('invoices-received').createSignedUrl(storagePath, 600)
      if (data?.signedUrl) setPhotoUrl(data.signedUrl)
    } catch (_) {}
    setPhotoLoading(false)
  }

  useEffect(() => { if (storagePath) loadPhoto() }, [storagePath])

  return (
    <div className="flex flex-wrap gap-6">
      {storagePath && (
        <div style={{ minWidth: 200, maxWidth: 300 }}>
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#2563eb' }}>Doklad</div>
          {photoLoading ? (
            <div className="text-sm" style={{ color: '#6b7280' }}>Nacitam...</div>
          ) : photoUrl ? (
            <a href={photoUrl} target="_blank" rel="noopener noreferrer">
              <img src={photoUrl} alt="Doklad" style={{ maxWidth: '100%', borderRadius: 8, border: '1px solid #d4e8e0', cursor: 'zoom-in' }} />
            </a>
          ) : (
            <div className="text-sm" style={{ color: '#6b7280' }}>Nelze nacist</div>
          )}
        </div>
      )}

      <div>
        <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Dokladova data</div>
        <div className="grid grid-cols-2 gap-x-6 gap-y-1">
          <MiniLabel label="Dodavatel" value={meta.supplier_name || '\u2014'} />
          <MiniLabel label="ICO" value={meta.supplier_ico || '\u2014'} mono />
          <MiniLabel label="Cislo faktury" value={meta.invoice_number || '\u2014'} mono />
          <MiniLabel label="VS" value={meta.variable_symbol || '\u2014'} mono />
          <MiniLabel label="Cislo uctu" value={meta.supplier_bank_account || '\u2014'} mono />
          <MiniLabel label="Splatnost" value={meta.due_date ? new Date(meta.due_date).toLocaleDateString('cs-CZ') : '\u2014'} />
          <MiniLabel label="Datum prijeti" value={meta.received_date ? new Date(meta.received_date).toLocaleDateString('cs-CZ') : '\u2014'} />
          <MiniLabel label="Platba" value={PAYMENT_LABELS[meta.payment_method] || meta.payment_method || '\u2014'} />
        </div>
      </div>

      {ai && (
        <div>
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#7c3aed' }}>AI klasifikace</div>
          <div className="grid grid-cols-2 gap-x-6 gap-y-1">
            <MiniLabel label="Kategorie" value={CATEGORY_LABELS[ai.category] || ai.category || '\u2014'} />
            <MiniLabel label="Ucet" value={ai.suggested_account || '\u2014'} mono />
            <MiniLabel label="Opakujici se" value={ai.is_recurring ? 'Ano' : 'Ne'} />
            <MiniLabel label="Poznamka" value={ai.classification_note || '\u2014'} />
          </div>
        </div>
      )}

      {assetCls && (
        <div>
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#b45309' }}>Majetek a odpisy</div>
          <div className="grid grid-cols-2 gap-x-6 gap-y-1">
            <MiniLabel label="Typ majetku" value={ASSET_TYPE_LABELS[assetCls] || assetCls} />
            {ai?.asset_name && <MiniLabel label="Polozka" value={ai.asset_name} />}
            {deprGroup && (
              <>
                <MiniLabel label="Odpis. skupina" value={deprGroup} mono />
                <MiniLabel label="Odpis. doba" value={deprYears ? `${deprYears} let` : '\u2014'} />
                <MiniLabel label="Metoda" value={deprMethod === 'accelerated' ? 'Zrychlene' : deprMethod === 'linear' ? 'Rovnomerne' : '\u2014'} />
              </>
            )}
            {assetCls === 'dlouhodoby_majetek' && (
              <div className="col-span-2 mt-1 p-2 rounded" style={{ background: '#fef3c7', border: '1px solid #fcd34d' }}>
                <span className="text-xs font-bold" style={{ color: '#b45309' }}>
                  Doporuceni: {deprMethod === 'accelerated' ? 'Zrychleny' : 'Rovnomerny'} odpis, skupina {deprGroup || 'sk2'} ({deprYears || 5} let)
                </span>
              </div>
            )}
          </div>
        </div>
      )}

      {(event.document_type || event.metadata?.document_type) && (
        <div>
          <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#0891b2' }}>Typ dokladu & smerovani</div>
          <div className="grid grid-cols-2 gap-x-6 gap-y-1">
            <MiniLabel label="Typ dokladu" value={(DOC_TYPE_MAP[event.document_type || event.metadata?.document_type] || DOC_TYPE_MAP.other).label} />
            <MiniLabel label="Smerovano do" value={(DOC_TYPE_MAP[event.document_type || event.metadata?.document_type] || DOC_TYPE_MAP.other).route || '\u2014'} />
            {event.metadata?.backup_path && <MiniLabel label="Zaloha foto" value={event.metadata.backup_path} mono />}
          </div>
        </div>
      )}

      <div>
        <div className="text-[9px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#6b7280' }}>Info</div>
        <div className="grid grid-cols-2 gap-x-6 gap-y-1">
          <MiniLabel label="ID" value={event.id?.slice(0, 8)} mono />
          <MiniLabel label="Confidence" value={event.confidence_score != null ? `${(event.confidence_score * 100).toFixed(0)}%` : '\u2014'} />
          <MiniLabel label="Vytvoreno" value={event.created_at ? new Date(event.created_at).toLocaleString('cs-CZ') : '\u2014'} />
          <MiniLabel label="Flexi ID" value={event.flexi_id || '\u2014'} mono />
          <MiniLabel label="Linked" value={event.linked_entity_type ? `${event.linked_entity_type} ${event.linked_entity_id?.slice(0, 8) || ''}` : '\u2014'} />
          <MiniLabel label="Zdroj" value={SOURCE_LABELS[event.source] || event.source} />
        </div>
      </div>
    </div>
  )
}
