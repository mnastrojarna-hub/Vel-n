import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Pagination from '../../components/ui/Pagination'
import SearchInput from '../../components/ui/SearchInput'
import Modal from '../../components/ui/Modal'
import ImageUploader from '../../components/ui/ImageUploader'
import { autoTranslateRow } from '../../lib/autoTranslate'

const PER_PAGE = 25

export default function ProductsTab() {
  const [products, setProducts] = useState([])
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [search, setSearch] = useState('')
  const [detail, setDetail] = useState(null)
  const [showAdd, setShowAdd] = useState(false)

  useEffect(() => { load() }, [page, search])

  useEffect(() => {
    const channel = supabase
      .channel('products-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'products' }, () => load())
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [])

  async function load() {
    setLoading(true)
    let q = supabase
      .from('products')
      .select('*', { count: 'exact' })
      .order('sort_order', { ascending: true })

    if (search?.trim()) {
      q = q.or(`name.ilike.%${search.trim()}%,sku.ilike.%${search.trim()}%,category.ilike.%${search.trim()}%`)
    }

    const { data, count } = await q.range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
    setProducts(data || [])
    setTotal(count || 0)
    setLoading(false)
  }

  async function toggleActive(product) {
    await debugAction('product.toggleActive', 'ProductsTab', () =>
      supabase.from('products').update({ is_active: !product.is_active }).eq('id', product.id)
    )
    load()
  }

  async function deleteProduct(id) {
    if (!confirm('Opravdu smazat tento produkt?')) return
    await debugAction('product.delete', 'ProductsTab', () =>
      supabase.from('products').delete().eq('id', id)
    )
    load()
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = n => n != null ? `${Number(n).toLocaleString('cs-CZ')} Kč` : '—'

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <SearchInput value={search} onChange={v => { setPage(1); setSearch(v) }} placeholder="Hledat produkt…" />
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Přidat produkt</Button>
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Foto</TH><TH>Název</TH><TH>SKU</TH><TH>Cena</TH><TH>Sklad</TH><TH>Velikosti</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {products.map(p => (
                <tr key={p.id} className="cursor-pointer hover:bg-[#f1faf7] transition-colors" style={{ borderBottom: '1px solid #d4e8e0' }}>
                  <TD>
                    {p.images?.[0] ? (
                      <img src={p.images[0]} alt={p.name} style={{ width: 48, height: 48, objectFit: 'cover', borderRadius: 8 }} />
                    ) : (
                      <div style={{ width: 48, height: 48, background: '#f1faf7', borderRadius: 8, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20 }}>📦</div>
                    )}
                  </TD>
                  <TD bold onClick={() => setDetail(p)}>{p.name}</TD>
                  <TD mono onClick={() => setDetail(p)}>{p.sku || '—'}</TD>
                  <TD bold onClick={() => setDetail(p)}>{fmt(p.price)}</TD>
                  <TD onClick={() => setDetail(p)}>
                    <span style={{
                      fontWeight: 700,
                      color: p.stock_quantity <= 0 ? '#dc2626' : p.stock_quantity <= 10 ? '#b45309' : '#1a8a18'
                    }}>
                      {p.stock_quantity} ks
                    </span>
                  </TD>
                  <TD onClick={() => setDetail(p)}>
                    {p.sizes?.length > 0 ? p.sizes.join(', ') : '—'}
                  </TD>
                  <TD>
                    <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase cursor-pointer"
                      onClick={() => toggleActive(p)}
                      style={{
                        padding: '3px 8px',
                        background: p.is_active ? '#dcfce7' : '#fee2e2',
                        color: p.is_active ? '#1a8a18' : '#dc2626',
                      }}>
                      {p.is_active ? 'Aktivní' : 'Neaktivní'}
                    </span>
                  </TD>
                  <TD>
                    <div className="flex gap-1">
                      <button onClick={() => setDetail(p)} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#2563eb' }}>✏️</button>
                      <button onClick={() => deleteProduct(p.id)} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#dc2626' }}>🗑️</button>
                    </div>
                  </TD>
                </tr>
              ))}
              {products.length === 0 && <TRow><TD colSpan={8}>Žádné produkty</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <ProductFormModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
      {detail && <ProductFormModal product={detail} onClose={() => setDetail(null)} onSaved={() => { setDetail(null); load() }} />}
    </div>
  )
}

function ProductFormModal({ product, onClose, onSaved }) {
  const isEdit = !!product
  const [form, setForm] = useState({
    name: product?.name || '',
    description: product?.description || '',
    price: product?.price || '',
    sku: product?.sku || '',
    stock_quantity: product?.stock_quantity ?? 0,
    category: product?.category || 'merch',
    color: product?.color || '',
    material: product?.material || '',
    sizes: product?.sizes?.join(', ') || '',
    images: Array.isArray(product?.images) ? product.images.filter(Boolean) : [],
    is_active: product?.is_active ?? true,
    sort_order: product?.sort_order ?? 0,
  })
  const [saving, setSaving] = useState(false)
  const [translating, setTranslating] = useState(false)
  const [err, setErr] = useState(null)

  // Stabilní cesta v bucketu — u úprav použij ID produktu, u nového vygeneruj UUID
  const folderId = useMemo(() => {
    if (product?.id) return `products/${product.id}`
    const r = (typeof crypto !== 'undefined' && crypto.randomUUID) ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`
    return `products/${r}`
  }, [product?.id])

  function set(k, v) { setForm(f => ({ ...f, [k]: v })) }

  async function handleSave() {
    if (!form.name.trim()) { setErr('Název je povinný'); return }
    if (!form.price || Number(form.price) <= 0) { setErr('Cena musí být větší než 0'); return }

    setSaving(true); setErr(null)
    try {
      const payload = {
        name: form.name.trim(),
        description: form.description.trim(),
        price: Number(form.price),
        sku: form.sku.trim() || null,
        stock_quantity: Number(form.stock_quantity) || 0,
        category: form.category.trim() || 'merch',
        color: form.color.trim() || null,
        material: form.material.trim() || null,
        sizes: form.sizes ? form.sizes.split(',').map(s => s.trim()).filter(Boolean) : [],
        images: (form.images || []).filter(Boolean),
        is_active: form.is_active,
        sort_order: Number(form.sort_order) || 0,
      }

      let savedId = product?.id
      if (isEdit) {
        const result = await debugAction('product.update', 'ProductFormModal', () =>
          supabase.from('products').update(payload).eq('id', product.id)
        , payload)
        if (result?.error) throw result.error
      } else {
        const result = await debugAction('product.create', 'ProductFormModal', () =>
          supabase.from('products').insert(payload).select().single()
        , payload)
        if (result?.error) throw result.error
        savedId = result?.data?.id
      }

      // Auto-překlad pro web (běží na pozadí, blokuje zavření modal po dobu překladu)
      if (savedId) {
        setSaving(false); setTranslating(true)
        await autoTranslateRow({ table: 'products', id: savedId, row: payload })
        setTranslating(false)
      }
      onSaved()
    } catch (e) { setErr(e.message); setSaving(false); setTranslating(false) }
  }

  return (
    <Modal open title={isEdit ? `Upravit: ${product.name}` : 'Nový produkt'} onClose={onClose} wide>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <div><Label>Název produktu *</Label><Input value={form.name} onChange={v => set('name', v)} placeholder="Snapback čepice" /></div>
          <div><Label>SKU (kód)</Label><Input value={form.sku} onChange={v => set('sku', v)} placeholder="MG24-CAP-001" /></div>
        </div>
        <div>
          <Label>Popis</Label>
          <textarea value={form.description} onChange={e => set('description', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 70, resize: 'vertical' }}
            placeholder="Popis produktu…" />
        </div>
        <div className="grid grid-cols-3 gap-3">
          <div><Label>Cena (Kč) *</Label><Input value={form.price} onChange={v => set('price', v)} placeholder="490" type="number" /></div>
          <div><Label>Skladem (ks)</Label><Input value={form.stock_quantity} onChange={v => set('stock_quantity', v)} placeholder="50" type="number" /></div>
          <div><Label>Pořadí</Label><Input value={form.sort_order} onChange={v => set('sort_order', v)} placeholder="1" type="number" /></div>
        </div>
        <div className="grid grid-cols-3 gap-3">
          <div><Label>Kategorie</Label><Input value={form.category} onChange={v => set('category', v)} placeholder="merch" /></div>
          <div><Label>Barva</Label><Input value={form.color} onChange={v => set('color', v)} placeholder="Černá" /></div>
          <div><Label>Materiál</Label><Input value={form.material} onChange={v => set('material', v)} placeholder="100% bavlna" /></div>
        </div>
        <div>
          <Label>Velikosti (oddělené čárkou)</Label>
          <Input value={form.sizes} onChange={v => set('sizes', v)} placeholder="XS, S, M, L, XL" />
        </div>
        <div>
          <Label>Obrázky produktu</Label>
          <ImageUploader
            value={form.images}
            onChange={urls => set('images', urls)}
            folder={folderId}
            helperText="Přetáhněte fotky z počítače, klikněte pro výběr nebo přidejte přes URL. První obrázek je hlavní (zobrazí se v e-shopu jako náhled)."
          />
        </div>

        <label className="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" checked={form.is_active} onChange={e => set('is_active', e.target.checked)}
            className="accent-[#1a8a18]" style={{ width: 18, height: 18 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Aktivní (viditelný v e-shopu)</span>
        </label>
      </div>

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || translating}>
          {saving ? 'Ukládám…' : translating ? '🌍 Překládám pro web…' : isEdit ? 'Uložit' : 'Vytvořit'}
        </Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
function Input({ value, onChange, placeholder, type = 'text' }) {
  return <input type={type} value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder}
    className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
}
