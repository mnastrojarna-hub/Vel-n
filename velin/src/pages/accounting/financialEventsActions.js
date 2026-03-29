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

export async function createReceivedInvoiceFromEvent(event) {
  const meta = event.metadata || {}
  if (event.linked_entity_type === 'invoice' && event.linked_entity_id) return
  const ai = meta.ai_classification || {}
  const invNumber = meta.invoice_number || `FP-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}-${event.id.slice(0, 4)}`
  const noteParts = [meta.supplier_name, meta.supplier_ico ? `ICO: ${meta.supplier_ico}` : null, ai.category ? `Kategorie: ${ai.category}` : null, ai.classification_note, meta.payment_method ? `Platba: ${meta.payment_method}` : null, `FE: ${event.id.slice(0, 8)}`]
  const { data: inv } = await supabase.from('invoices').insert({ number: invNumber, type: 'received', total: event.amount_czk || 0, subtotal: event.amount_czk || 0, tax_amount: 0, issue_date: event.duzp || new Date().toISOString().slice(0, 10), due_date: meta.due_date || null, variable_symbol: meta.variable_symbol || null, notes: noteParts.filter(Boolean).join('\n'), status: 'issued', source: 'system' }).select().single()
  if (inv) { await supabase.from('financial_events').update({ linked_entity_type: 'invoice', linked_entity_id: inv.id }).eq('id', event.id) }
}
