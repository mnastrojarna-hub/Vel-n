import { supabase } from '../../lib/supabase'
import { STORAGE_FOLDERS } from './financialEventsConstants'

export async function createLiabilityFromEvent(event) {
  const meta = event.metadata || {}; const ai = meta.ai_classification || {}
  await supabase.from('acc_liabilities').insert({ counterparty: meta.supplier_name || 'Neznamy dodavatel', type: 'supplier', amount: event.amount_czk || 0, paid_amount: 0, due_date: meta.due_date || null, description: ai.classification_note || meta.invoice_number || '', variable_symbol: meta.variable_symbol || null, invoice_number: meta.invoice_number || null, status: 'pending', financial_event_id: event.id })
}

export async function ensureSupplier(event) {
  const meta = event.metadata || {}; if (!meta.supplier_name) return
  const normalized = meta.supplier_name.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim()
  const { data: existing } = await supabase.from('suppliers').select('id').eq('normalized_name', normalized).limit(1)
  if (existing && existing.length > 0) return
  await supabase.from('suppliers').insert({ name: meta.supplier_name, normalized_name: normalized, ico: meta.supplier_ico || null, bank_account: meta.supplier_bank_account || null })
}

export async function backupPhotoToFolder(event, docType) {
  const meta = event.metadata || {}; const sourcePath = meta.storage_path; if (!sourcePath) return
  const folder = STORAGE_FOLDERS[docType] || STORAGE_FOLDERS.other
  const fileName = `${new Date().toISOString().slice(0, 10)}_${event.id.slice(0, 8)}_${sourcePath.split('/').pop()}`
  const targetPath = `${folder}/${fileName}`
  try {
    const { data: fileData } = await supabase.storage.from('invoices-received').download(sourcePath)
    if (fileData) {
      await supabase.storage.from('documents').upload(targetPath, fileData, { upsert: true })
      await supabase.from('financial_events').update({ metadata: { ...meta, backup_path: targetPath, backup_bucket: 'documents' } }).eq('id', event.id)
    }
  } catch (e) { console.error('[FE] Photo backup failed:', e.message) }
}

export async function createDeliveryNoteFromEvent(event) {
  const meta = event.metadata || {}
  if (event.linked_entity_type === 'delivery_note' && event.linked_entity_id) return
  const { data: dl } = await supabase.from('delivery_notes').insert({ dl_number: meta.invoice_number || meta.dl_number || `DL-${event.id.slice(0, 8)}`, supplier_name: meta.supplier_name || null, supplier_ico: meta.supplier_ico || null, total_amount: event.amount_czk || 0, delivery_date: event.duzp || new Date().toISOString().slice(0, 10), variable_symbol: meta.variable_symbol || null, items: meta.items || null, notes: meta.notes || [meta.supplier_name, meta.invoice_number].filter(Boolean).join('\n'), storage_path: meta.backup_path || meta.storage_path || null, extracted_data: meta.ai_classification || meta, source: 'financial_event', financial_event_id: event.id }).select().single()
  if (dl) { await supabase.from('financial_events').update({ linked_entity_type: 'delivery_note', linked_entity_id: dl.id }).eq('id', event.id) }
}

export async function createContractFromEvent(event, docType) {
  const meta = event.metadata || {}
  if (event.linked_entity_type === 'contract' && event.linked_entity_id) return
  const contractTypeMap = { smlouva: meta.contract_subtype || 'other', pracovni_smlouva: 'employment', zadost_dovolena: 'vacation_request' }
  const { data: contract } = await supabase.from('contracts').insert({ contract_number: meta.invoice_number || meta.contract_number || `SM-${event.id.slice(0, 8)}`, contract_type: contractTypeMap[docType] || 'other', title: meta.title || meta.supplier_name || `Smlouva ze skeneru`, counterparty: meta.supplier_name || null, counterparty_ico: meta.supplier_ico || null, amount: event.amount_czk || null, valid_from: event.duzp || new Date().toISOString().slice(0, 10), valid_until: meta.due_date || null, status: 'pending', notes: meta.notes || [meta.supplier_name, meta.invoice_number].filter(Boolean).join('\n'), storage_path: meta.backup_path || meta.storage_path || null, extracted_data: meta.ai_classification || meta, source: 'financial_event', financial_event_id: event.id, employee_id: meta.employee_id || null }).select().single()
  if (contract) { await supabase.from('financial_events').update({ linked_entity_type: 'contract', linked_entity_id: contract.id }).eq('id', event.id) }
}

// Založí NEBO doplní majetek dle účetní klasifikace z OCR (dlouhodobý / krátkodobý / materiál).
// DEDUPLIKACE: vozidlo/motorka se páruje nezaměnitelně dle VIN/SPZ (i když byla zanesena přes Flotilu),
// ostatní majetek dle názvu — pokud existuje, jen se DOPLNÍ chybějící (cena, doklad, odpisy), nevznikne duplicita.
// Idempotentní přes metadata.asset_created. Chyby polkne (nesmí shodit schválení).
export async function createAssetFromEvent(event) {
  const meta = event.metadata || {}
  if (meta.asset_created) return
  const ai = meta.ai_classification || {}; const cls = meta.asset_classification || {}
  const type = ai.asset_type || cls.type || null
  if (!type || !['dlouhodoby_majetek', 'kratkodoby_majetek', 'material'].includes(type)) return
  const name = ai.asset_name || cls.asset_name || meta.supplier_name || meta.invoice_number || 'Položka ze skeneru'
  const price = event.amount_czk || 0
  const acquired = event.duzp || new Date().toISOString().slice(0, 10)
  const invNum = meta.invoice_number || null
  const norm = (s) => String(s || '').replace(/\s/g, '').toUpperCase()
  const vin = norm(cls.vin || ai.vin)
  const spz = norm(cls.license_plate || ai.license_plate)
  // odpisová doba dle skupiny (§30 ZDP): sk1=3, sk2=5, sk3=10, sk4=20, sk5=30, sk6=50
  const GROUP_YEARS = { 1: 3, 2: 5, 3: 10, 4: 20, 5: 30, 6: 50 }
  try {
    if (type === 'dlouhodoby_majetek') {
      const grp = parseInt(String(ai.depreciation_group || cls.depreciation_group || '').replace(/\D/g, ''), 10) || 2
      const method = (ai.depreciation_method || cls.depreciation_method) === 'linear' ? 'linear' : 'accelerated'
      const years = parseInt(String(ai.depreciation_years || cls.depreciation_years || '').replace(/\D/g, ''), 10) || GROUP_YEARS[grp] || 5

      // 1) DEDUP — najdi existující majetek (motorka dle VIN/SPZ, jinak dle názvu)
      let existing = null, assetId = null
      if (vin || spz) {
        const { data: motos } = await supabase.from('motorcycles').select('id, model, spz, vin')
        const moto = (motos || []).find(m => (vin && norm(m.vin) === vin) || (spz && norm(m.spz) === spz))
        if (moto) {
          const { data: a } = await supabase.from('acc_long_term_assets').select('*').eq('motorcycle_id', moto.id).limit(1)
          existing = a && a[0]
          if (!existing) {
            // motorka je ve flotile, ale ještě ne v majetku → založ majetek navázaný na motorku
            const { data: ins } = await supabase.from('acc_long_term_assets')
              .insert({ name: name || `${moto.model} (${moto.spz || moto.vin || ''})`, category: 'vehicles', purchase_price: price, current_value: price, acquired_date: acquired, depreciation_group: grp, depreciation_method: method, status: 'active', motorcycle_id: moto.id, missing_purchase_doc: false, invoice_number: invNum })
              .select('id').single()
            assetId = ins?.id
          }
        }
      }
      if (!existing && !assetId && name) {
        const { data: a } = await supabase.from('acc_long_term_assets').select('*').ilike('name', name).limit(1)
        existing = a && a[0]
      }

      if (existing) {
        // 2) DOPLŇ co chybí — NEDUPLIKUJ
        const patch = {}
        if (!existing.purchase_price || existing.purchase_price === 0) { patch.purchase_price = price; patch.current_value = price }
        if (!existing.invoice_number && invNum) patch.invoice_number = invNum
        if (existing.missing_purchase_doc) patch.missing_purchase_doc = false
        if (!existing.acquired_date) patch.acquired_date = acquired
        if (Object.keys(patch).length) await supabase.from('acc_long_term_assets').update(patch).eq('id', existing.id)
        assetId = existing.id
      } else if (!assetId) {
        // 3) Úplně nový majetek
        const { data: ins } = await supabase.from('acc_long_term_assets')
          .insert({ name, category: 'equipment', purchase_price: price, current_value: price, acquired_date: acquired, depreciation_group: grp, depreciation_method: method, status: 'active', invoice_number: invNum })
          .select('id').single()
        assetId = ins?.id
      }

      // 4) Plán odpisů (rovnoměrný) — jen pokud ještě žádný neexistuje. acc_depreciation_entries.
      if (assetId && years > 0 && price > 0) {
        const { count } = await supabase.from('acc_depreciation_entries').select('id', { count: 'exact', head: true }).eq('asset_id', assetId)
        if (!count) {
          const yearAmt = Math.round(price / years)
          const startYear = new Date(acquired).getFullYear()
          const rows = []; let cum = 0
          for (let i = 1; i <= years; i++) {
            const amt = i === years ? (price - cum) : yearAmt
            cum += amt
            rows.push({ asset_id: assetId, year: startYear + i - 1, year_number: i, annual_amount: amt, cumulative_amount: cum, remaining_value: price - cum, depreciation_group: grp, method })
          }
          try { await supabase.from('acc_depreciation_entries').insert(rows) } catch (e) { console.error('[FE] depreciation schedule failed:', e.message) }
        }
      }
    } else {
      // Krátkodobý / materiál — dedup dle názvu
      const { data: a } = await supabase.from('acc_short_term_assets').select('id, purchase_price').ilike('name', name).limit(1)
      if (a && a[0]) {
        if (!a[0].purchase_price) await supabase.from('acc_short_term_assets').update({ purchase_price: price, current_value: price }).eq('id', a[0].id)
      } else {
        await supabase.from('acc_short_term_assets').insert({ name, category: type === 'material' ? 'material' : 'inventory', purchase_price: price, current_value: price, acquired_date: acquired, status: 'active' })
      }
    }
    await supabase.from('financial_events').update({ metadata: { ...meta, asset_created: true } }).eq('id', event.id)
  } catch (e) { console.error('[FE] asset create failed:', e.message) }
}

// Propíše doklad do nákladů (accounting_entries, type=expense). Idempotentní. Chyby polkne.
export async function createExpenseEntryFromEvent(event) {
  const meta = event.metadata || {}
  if (meta.expense_entry_created) return
  const ai = meta.ai_classification || {}
  const category = ai.category || meta.asset_classification?.type || 'ostatni_naklady'
  const desc = [meta.supplier_name, meta.invoice_number].filter(Boolean).join(' ') || 'Přijatý doklad'
  try {
    await supabase.from('accounting_entries').insert({
      type: 'expense', category, amount: event.amount_czk || 0,
      date: event.duzp || new Date().toISOString().slice(0, 10), description: desc,
    })
    await supabase.from('financial_events').update({ metadata: { ...meta, expense_entry_created: true } }).eq('id', event.id)
  } catch (e) { console.error('[FE] expense entry failed:', e.message) }
}

export async function createReceivedInvoiceFromEvent(event) {
  const meta = event.metadata || {}
  if (event.linked_entity_type === 'invoice' && event.linked_entity_id) return
  const ai = meta.ai_classification || {}
  const invNumber = meta.invoice_number || `FP-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}-${event.id.slice(0, 4)}`
  const noteParts = [meta.supplier_name, meta.supplier_ico ? `ICO: ${meta.supplier_ico}` : null, ai.category ? `Kategorie: ${ai.category}` : null, ai.classification_note, meta.payment_method ? `Platba: ${meta.payment_method}` : null, `FE: ${event.id.slice(0, 8)}`]
  const { data: inv } = await supabase.from('invoices').insert({ number: invNumber, type: 'received', total: event.amount_czk || 0, subtotal: event.amount_czk || 0, tax_amount: 0, issue_date: event.duzp || new Date().toISOString().slice(0, 10), due_date: meta.due_date || null, variable_symbol: meta.variable_symbol || null, notes: noteParts.filter(Boolean).join('\n'), status: 'issued', source: 'system' }).select().single()
  if (inv) { await supabase.from('financial_events').update({ linked_entity_type: 'invoice', linked_entity_id: inv.id }).eq('id', event.id) }
}
