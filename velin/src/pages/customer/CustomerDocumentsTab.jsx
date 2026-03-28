import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { useDebugMode } from '../../hooks/useDebugMode'
import { generateInvoiceHtml } from '../../lib/invoiceTemplate'
import { loadInvoiceData, printInvoiceHtml } from '../../lib/invoiceUtils'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import Modal from '../../components/ui/Modal'
import CustomerVerificationSection from './CustomerVerificationSection'

const DOC_ICONS = {
  contract: '📋', rental_contract: '📋', protocol: '📝', handover_protocol: '📝',
  vop: '📜', terms: '📜', invoice: '🧾', invoice_advance: '🧾', invoice_final: '🧾',
  invoice_shop: '🧾', payment_receipt: '🧾', drivers_license: '🪪', id_card: '🪪', passport: '🪪',
}

const DOC_TYPE_LABELS = {
  contract: 'Smlouva', rental_contract: 'Nájemní smlouva', protocol: 'Předávací protokol',
  handover_protocol: 'Předávací protokol', vop: 'VOP', invoice_advance: 'Zálohová faktura',
  payment_receipt: 'Daňový doklad', invoice_final: 'Konečná faktura', invoice_shop: 'Shop faktura',
  drivers_license: 'Řidičský průkaz', id_card: 'Občanský průkaz', passport: 'Cestovní pas',
}

const INV_TYPE_MAP = {
  proforma: { label: 'Zálohová faktura (ZF)', color: '#2563eb', bg: '#dbeafe' },
  advance: { label: 'Zálohová faktura (ZF)', color: '#2563eb', bg: '#dbeafe' },
  payment_receipt: { label: 'Daňový doklad (DP)', color: '#0891b2', bg: '#cffafe' },
  final: { label: 'Konečná faktura (KF)', color: '#1a8a18', bg: '#dcfce7' },
  shop_proforma: { label: 'Shop zálohová', color: '#8b5cf6', bg: '#ede9fe' },
  shop_final: { label: 'Shop konečná', color: '#059669', bg: '#d1fae5' },
}

const DOC_FILTER_OPTIONS = [
  { value: 'all', label: 'Vše' },
  { value: 'invoices', label: 'Faktury' },
  { value: 'contracts', label: 'Smlouvy' },
  { value: 'verification', label: 'Ověřovací doklady' },
  { value: 'other', label: 'Ostatní' },
]

const PER_PAGE = 15

export default function CustomerDocumentsTab({ userId }) {
  const debugMode = useDebugMode()
  const [docs, setDocs] = useState([])
  const [invoices, setInvoices] = useState([])
  const [generatedDocs, setGeneratedDocs] = useState([])
  const [profile, setProfile] = useState(null)
  const [verificationDocs, setVerificationDocs] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [viewDoc, setViewDoc] = useState(null)
  const [viewHtml, setViewHtml] = useState(null)

  // Filters
  const [search, setSearch] = useState('')
  const [typeFilter, setTypeFilter] = useState('all')
  const [sortOrder, setSortOrder] = useState('date_desc')
  const [page, setPage] = useState(1)

  useEffect(() => { loadAll() }, [userId])

  async function loadAll() {
    setLoading(true)
    setError(null)
    try {
      const [docsRes, invRes, genRes, profRes] = await Promise.all([
        supabase.from('documents').select('*').eq('user_id', userId).order('created_at', { ascending: false }),
        supabase.from('invoices').select('*').eq('customer_id', userId).order('issue_date', { ascending: false, nullsFirst: false }),
        supabase.from('generated_documents').select('*').eq('customer_id', userId).order('created_at', { ascending: false }),
        supabase.from('profiles').select('id, full_name, license_number, license_expiry, license_group').eq('id', userId).single(),
      ])
      if (docsRes.error) throw docsRes.error

      // Enrich generated docs with template info
      if (genRes.data?.length > 0) {
        const templateIds = [...new Set(genRes.data.map(d => d.template_id).filter(Boolean))]
        if (templateIds.length > 0) {
          const { data: templates } = await supabase.from('document_templates').select('id, name, type, content_html').in('id', templateIds)
          if (templates) {
            const tplMap = Object.fromEntries(templates.map(t => [t.id, t]))
            genRes.data.forEach(d => { d.document_templates = tplMap[d.template_id] || null })
          }
        }
      }

      const VERIFICATION_TYPES = ['drivers_license', 'id_card', 'passport', 'id_photo', 'license_photo']
      const INVOICE_SYNCED_TYPES = ['invoice_advance', 'payment_receipt', 'invoice_final', 'invoice_shop']
      const allDocs = docsRes.data || []
      setDocs(allDocs.filter(d => !VERIFICATION_TYPES.includes(d.type) && !INVOICE_SYNCED_TYPES.includes(d.type)))
      setInvoices(invRes.data || [])
      setGeneratedDocs(genRes.data || [])
      setVerificationDocs(allDocs.filter(d => VERIFICATION_TYPES.includes(d.type)))
      setProfile(profRes.data || null)
    } catch (e) {
      setError(e.message)
    }
    setLoading(false)
  }

  function getAllItems() {
    const items = []
    invoices.forEach(inv => {
      const tp = INV_TYPE_MAP[inv.type] || { label: inv.type || 'Faktura', color: '#1a2e22', bg: '#f3f4f6' }
      items.push({ id: inv.id, kind: 'invoice', icon: '🧾', name: inv.number || 'Faktura', typeBadge: tp, type: inv.type, date: inv.issue_date || inv.created_at?.slice(0, 10), amount: inv.total, raw: inv, category: 'invoices' })
    })
    generatedDocs.forEach(d => {
      const docType = d.document_templates?.type || 'contract'
      items.push({ id: d.id, kind: 'generated', icon: DOC_ICONS[docType] || '📄', name: d.document_templates?.name || DOC_TYPE_LABELS[docType] || 'Dokument', type: docType, date: d.created_at?.slice(0, 10), raw: d, category: 'contracts' })
    })
    docs.forEach(d => {
      items.push({ id: d.id, kind: 'document', icon: DOC_ICONS[d.type] || '📄', name: d.file_name || d.name || DOC_TYPE_LABELS[d.type] || d.type || 'Dokument', type: d.type, date: d.created_at?.slice(0, 10), raw: d, category: d.type === 'contract' || d.type === 'vop' ? 'contracts' : 'other' })
    })
    return items
  }

  function getFilteredItems() {
    let items = getAllItems()
    if (typeFilter !== 'all') items = items.filter(i => i.category === typeFilter)
    if (search) {
      const s = search.toLowerCase()
      items = items.filter(i => (i.name || '').toLowerCase().includes(s) || (i.type || '').toLowerCase().includes(s) || (i.date || '').includes(s))
    }
    items.sort((a, b) => {
      const da = a.date || '', db = b.date || ''
      return sortOrder === 'date_asc' ? da.localeCompare(db) : db.localeCompare(da)
    })
    return items
  }

  async function handleViewItem(item) {
    setError(null)
    if (item.kind === 'invoice') {
      try {
        const fullInv = await loadInvoiceData(item.raw.id)
        const html = generateInvoiceHtml({ ...fullInv, customer: fullInv.profiles || {}, items: fullInv.items || [] })
        setViewHtml(html); setViewDoc(item.raw)
      } catch (e) { setError(`Náhled faktury selhal: ${e.message}`) }
      return
    }
    if (item.kind === 'generated') { await handleViewGeneratedDoc(item.raw); return }
    await handleViewDoc(item.raw)
  }

  async function handleViewGeneratedDoc(doc) {
    if (doc.document_templates?.content_html && doc.filled_data) {
      let html = doc.document_templates.content_html
      for (const [k, v] of Object.entries(doc.filled_data)) html = html.replace(new RegExp(`\\{\\{${k}\\}\\}`, 'g'), v || '')
      setViewHtml(html); setViewDoc(doc); return
    }
    if (doc.filled_data) {
      const v = doc.filled_data
      setViewHtml(`<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Dokument</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h2>${v.company_name || 'MotoGo24'}</h2><p>Zákazník: ${v.customer_name || '—'}</p><p>Motocykl: ${v.moto_model || '—'} (${v.moto_spz || ''})</p><p>Období: ${v.start_date || '—'} — ${v.end_date || '—'} (${v.days || '—'} dní)</p><p>Cena: ${v.total_price || '—'} Kč</p></div></body></html>`)
      setViewDoc(doc); return
    }
    const path = doc.pdf_path || doc.file_path
    if (path) {
      try {
        const { data, error: err } = await supabase.storage.from('documents').download(path)
        if (!err) { setViewHtml(await data.text()); setViewDoc(doc); return }
      } catch {}
    }
    setError('Dokument nemá obsah — zkuste jej znovu vygenerovat')
  }

  async function handleViewDoc(doc) {
    const path = doc.pdf_path || doc.file_path
    if (!path) { setError('Dokument nemá cestu k souboru'); return }
    try {
      const { data, error: err } = await supabase.storage.from('documents').download(path)
      if (err) throw err
      setViewHtml(await data.text()); setViewDoc(doc)
    } catch {
      const label = doc.file_name || doc.type || 'Dokument'
      setViewHtml(`<html><body style="font-family:sans-serif;padding:40px;text-align:center;color:#666"><h2>${label}</h2><p>Soubor není uložen v online úložišti.</p></body></html>`)
      setViewDoc(doc)
    }
  }

  async function handleDownload(item) {
    try {
      if (item.kind === 'invoice') {
        const fullInv = await loadInvoiceData(item.raw.id)
        const html = generateInvoiceHtml({ ...fullInv, customer: fullInv.profiles || {}, items: fullInv.items || [] })
        downloadBlob(html, `faktura_${item.raw.number || item.raw.id}.html`); return
      }
      const doc = item.raw || item
      if (doc.filled_data) {
        const v = doc.filled_data
        downloadBlob(`<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Dokument</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h2>${v.company_name || 'MotoGo24'}</h2><p>Zákazník: ${v.customer_name || '—'}</p><p>Motocykl: ${v.moto_model || '—'} (${v.moto_spz || ''})</p></div></body></html>`, doc.document_templates?.name || 'dokument.html')
        return
      }
      const path = doc.pdf_path || doc.file_path
      if (path) {
        const { data, error: err } = await supabase.storage.from('documents').download(path)
        if (!err && data) {
          const url = URL.createObjectURL(data)
          const a = document.createElement('a'); a.href = url; a.download = doc.file_name || 'dokument.html'; a.click(); URL.revokeObjectURL(url); return
        }
      }
      setError('Soubor není dostupný ke stažení')
    } catch (e) { setError(`Stažení selhalo: ${e.message}`) }
  }

  function downloadBlob(html, filename) {
    const blob = new Blob([html], { type: 'text/html' })
    const url = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = url; a.download = filename; a.click(); URL.revokeObjectURL(url)
  }

  async function handlePrint(item) {
    try {
      if (item.kind === 'invoice') {
        const fullInv = await loadInvoiceData(item.raw.id)
        const html = generateInvoiceHtml({ ...fullInv, customer: fullInv.profiles || {}, items: fullInv.items || [] })
        printInvoiceHtml(html); return
      }
      if (viewHtml) printInvoiceHtml(viewHtml)
    } catch (e) { setError(`Tisk selhal: ${e.message}`) }
  }

  function getVerificationStatus() {
    const hasLicense = verificationDocs.some(d => d.type === 'drivers_license' || d.type === 'license_photo')
    const hasIdCard = verificationDocs.some(d => d.type === 'id_card' || d.type === 'id_photo')
    const hasPassport = verificationDocs.some(d => d.type === 'passport')
    const hasIdentity = hasIdCard || hasPassport
    const licenseValid = profile?.license_expiry ? new Date(profile.license_expiry) > new Date() : false
    const licenseGroupFilled = profile?.license_group && profile.license_group.length > 0
    const hasMotoGroup = licenseGroupFilled && profile.license_group.some(g => ['A', 'A2', 'A1', 'AM'].includes(g))
    const allOk = hasLicense && hasIdentity && licenseValid && licenseGroupFilled && hasMotoGroup
    return { hasLicense, hasIdCard, hasPassport, hasIdentity, licenseValid, licenseGroupFilled, hasMotoGroup, allOk }
  }

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  const filteredItems = getFilteredItems()
  const totalPages = Math.ceil(filteredItems.length / PER_PAGE)
  const pagedItems = filteredItems.slice((page - 1) * PER_PAGE, page * PER_PAGE)
  const vs = getVerificationStatus()

  return (
    <div className="space-y-5">
      {error && <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {/* Ověření dokladů — pouze ŘP + OP/pas */}
      <Card>
        <h3 className="text-sm font-extrabold uppercase tracking-widest mb-4" style={{ color: '#1a2e22' }}>Overeni dokladu zakaznika</h3>
        <div className="space-y-3 mb-4">
          {/* 1. Řidičský průkaz */}
          <div className="p-4 rounded-lg" style={{ background: '#f1faf7' }}>
            <div className="flex items-center gap-2 mb-2">
              <span style={{ fontSize: 14 }}>{vs.hasLicense ? '✅' : '❌'}</span>
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Ridicsky prukaz (RP)</span>
              <Badge label={vs.hasLicense ? 'Vyfoceno' : 'Chybi'} color={vs.hasLicense ? '#1a8a18' : '#dc2626'} bg={vs.hasLicense ? '#dcfce7' : '#fee2e2'} />
            </div>
            <div className="flex flex-wrap gap-2">
              <Badge
                label={vs.licenseValid ? `Platny do ${profile?.license_expiry}` : profile?.license_expiry ? `Expirovany (${profile.license_expiry})` : 'Platnost nevyplnena'}
                color={vs.licenseValid ? '#1a8a18' : '#dc2626'}
                bg={vs.licenseValid ? '#dcfce7' : '#fee2e2'}
              />
              <Badge
                label={vs.licenseGroupFilled ? `Skupiny: ${(profile?.license_group || []).join(', ')}` : 'Skupiny nevyplneny'}
                color={vs.licenseGroupFilled ? '#1a8a18' : '#b45309'}
                bg={vs.licenseGroupFilled ? '#dcfce7' : '#fef3c7'}
              />
              {vs.licenseGroupFilled && profile?.license_group && (
                <Badge
                  label={profile.license_group.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) ? 'Skupina pro motorky OK' : 'Chybi skupina A/A2/A1'}
                  color={profile.license_group.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) ? '#1a8a18' : '#dc2626'}
                  bg={profile.license_group.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) ? '#dcfce7' : '#fee2e2'}
                />
              )}
            </div>
          </div>

          {/* 2. Doklad totožnosti (OP nebo pas) */}
          <div className="p-4 rounded-lg" style={{ background: '#f1faf7' }}>
            <div className="flex items-center gap-2 mb-2">
              <span style={{ fontSize: 14 }}>{vs.hasIdentity ? '✅' : '❌'}</span>
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Doklad totoznosti (OP nebo pas)</span>
              <Badge label={vs.hasIdentity ? 'Vyfoceno' : 'Chybi'} color={vs.hasIdentity ? '#1a8a18' : '#dc2626'} bg={vs.hasIdentity ? '#dcfce7' : '#fee2e2'} />
            </div>
            {vs.hasIdentity && (
              <div className="flex gap-2">
                {vs.hasIdCard && <Badge label="Obcansky prukaz" color="#1a8a18" bg="#dcfce7" />}
                {vs.hasPassport && <Badge label="Cestovni pas" color="#1a8a18" bg="#dcfce7" />}
              </div>
            )}
          </div>
        </div>

        <div className="p-3 rounded-lg" style={{ background: vs.allOk ? '#dcfce7' : '#fef3c7', border: `1px solid ${vs.allOk ? '#86efac' : '#fcd34d'}` }}>
          <div className="flex items-center gap-2">
            <span style={{ fontSize: 16 }}>{vs.allOk ? '✅' : '⚠️'}</span>
            <span className="text-sm font-bold" style={{ color: vs.allOk ? '#1a8a18' : '#b45309' }}>
              {vs.allOk ? 'Vsechny doklady overeny — kody k boxu mohou byt uvolneny' : 'Doklady neuplne — kody k boxu NELZE uvolnit'}
            </span>
          </div>
          {!vs.allOk && (
            <ul className="mt-2 space-y-1" style={{ fontSize: 12, color: '#92400e' }}>
              {!vs.hasLicense && <li>• Chybi vyfoceny ridicsky prukaz</li>}
              {vs.hasLicense && !vs.licenseValid && <li>• Ridicsky prukaz je neplatny nebo expirovany</li>}
              {vs.hasLicense && !vs.licenseGroupFilled && <li>• Ridicske skupiny nejsou vyplneny v profilu</li>}
              {vs.hasLicense && vs.licenseGroupFilled && !profile?.license_group?.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) && <li>• Zakaznik nema ridicskou skupinu pro motorky (A/A2/A1/AM)</li>}
              {!vs.hasIdentity && <li>• Chybi vyfoceny doklad totoznosti (OP nebo pas)</li>}
            </ul>
          )}
        </div>
      </Card>

      {/* Filtr + seznam dokumentů */}
      <Card>
        <div className="flex flex-wrap items-center gap-3 mb-4">
          <SearchInput value={search} onChange={v => { setSearch(v); setPage(1) }} placeholder="Hledat v dokumentech…" />
          <div className="flex gap-1">
            {DOC_FILTER_OPTIONS.map(opt => (
              <button key={opt.value} onClick={() => { setTypeFilter(opt.value); setPage(1) }}
                className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
                style={{ padding: '6px 14px', background: typeFilter === opt.value ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none', boxShadow: typeFilter === opt.value ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
                {opt.label}
              </button>
            ))}
          </div>
          <select value={sortOrder} onChange={e => { setSortOrder(e.target.value); setPage(1) }}
            className="rounded-btn text-sm font-bold outline-none cursor-pointer"
            style={{ padding: '6px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
            <option value="date_desc">Nejnovější</option>
            <option value="date_asc">Nejstarší</option>
          </select>
          <span className="text-sm" style={{ color: '#1a2e22' }}>
            {filteredItems.length} {filteredItems.length === 1 ? 'dokument' : filteredItems.length < 5 ? 'dokumenty' : 'dokumentů'}
          </span>
        </div>

        {pagedItems.length === 0 ? (
          <p style={{ color: '#1a2e22', fontSize: 13 }}>{search || typeFilter !== 'all' ? 'Žádné dokumenty odpovídající filtru' : 'Žádné dokumenty'}</p>
        ) : (
          <div className="space-y-2">
            {pagedItems.map(item => {
              const tp = item.typeBadge || (DOC_TYPE_LABELS[item.type] ? { label: DOC_TYPE_LABELS[item.type], color: '#1a2e22', bg: '#f1faf7' } : null)
              return (
                <div key={`${item.kind}-${item.id}`} className="flex items-center gap-4 p-3 rounded-lg cursor-pointer hover:shadow-sm transition-shadow"
                  style={{ background: '#f1faf7' }} onClick={() => handleViewItem(item)}>
                  <span style={{ fontSize: 16 }}>{item.icon}</span>
                  <div className="flex-1 min-w-0">
                    <span className="text-sm font-bold">{item.name}</span>
                    {tp && <Badge label={tp.label} color={tp.color} bg={tp.bg} style={{ marginLeft: 8 }} />}
                  </div>
                  {item.amount != null && <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{item.amount.toLocaleString('cs-CZ')} Kč</span>}
                  <span className="text-sm" style={{ color: '#1a2e22' }}>{item.date || '—'}</span>
                  <div className="flex gap-2" onClick={e => e.stopPropagation()}>
                    <button onClick={() => handleViewItem(item)} className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>Náhled</button>
                    <button onClick={() => handlePrint(item)} className="text-sm font-bold cursor-pointer" style={{ color: '#1a2e22', background: 'none', border: 'none' }}>Tisk</button>
                    <button onClick={() => handleDownload(item)} className="text-sm font-bold cursor-pointer" style={{ color: '#1a2e22', background: 'none', border: 'none' }}>Stáhnout</button>
                  </div>
                </div>
              )
            })}
          </div>
        )}
        <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
      </Card>

      {/* Náhled dokumentu */}
      {viewDoc && (
        <Modal open title={viewDoc.number ? `Faktura ${viewDoc.number}` : (viewDoc.document_templates?.name || viewDoc.file_name || viewDoc.name || 'Dokument')} onClose={() => { setViewDoc(null); setViewHtml(null) }} wide>
          {viewHtml ? (
            <div className="border rounded-lg overflow-auto" style={{ maxHeight: 600, background: '#fff' }}>
              <iframe srcDoc={viewHtml} style={{ width: '100%', height: 550, border: 'none' }} title="Náhled dokumentu" />
            </div>
          ) : (
            <div className="py-8 text-center" style={{ color: '#1a2e22', fontSize: 13 }}>Dokument nemá náhled.</div>
          )}
          <div className="flex justify-end gap-3 mt-4">
            {viewHtml && <Button onClick={() => { const win = window.open('', '_blank'); if (win) { win.document.write(viewHtml); win.document.close(); win.onload = () => win.print() } }}>Tisk / PDF</Button>}
            <Button onClick={() => handleDownload({ kind: viewDoc.number ? 'invoice' : 'document', raw: viewDoc })}>Stáhnout</Button>
            <Button onClick={() => { setViewDoc(null); setViewHtml(null) }}>Zavřít</Button>
          </div>
        </Modal>
      )}

      {debugMode && (
        <div className="p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA CustomerDocuments</strong><br/>
          <div>invoices: {invoices.length}, generated: {generatedDocs.length}, docs: {docs.length}, verification: {verificationDocs.length}</div>
          <div>ŘP={String(vs.hasLicense)}, OP={String(vs.hasIdCard)}, pas={String(vs.hasPassport)}, valid={String(vs.licenseValid)}, groups={String(vs.licenseGroupFilled)}, allOk={String(vs.allOk)}</div>
        </div>
      )}
    </div>
  )
}

