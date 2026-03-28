// ===== receive-invoice/supplier-utils.ts =====
// Supplier upsert logic

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

export async function upsertSupplier(
  supplierName: string | null,
  aiClassification: Record<string, unknown> | null,
  supabase: ReturnType<typeof createClient>,
  extra?: { ico?: string; dic?: string; address?: string; bank_account?: string }
): Promise<string | null> {
  if (!supplierName) return null

  try {
    const normalized = supplierName
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .trim()

    // Search by ICO first (exact match), then by name prefix
    let existing = null
    if (extra?.ico) {
      const { data } = await supabase
        .from('suppliers')
        .select('id, name, default_category, ico, bank_account')
        .eq('ico', extra.ico)
        .maybeSingle()
      existing = data
    }
    if (!existing) {
      const { data } = await supabase
        .from('suppliers')
        .select('id, name, default_category, ico, bank_account')
        .ilike('normalized_name', '%' + normalized.substring(0, 10) + '%')
        .maybeSingle()
      existing = data
    }

    if (existing) {
      // Update missing fields
      const updates: Record<string, string> = {}
      if (!existing.default_category && aiClassification?.category)
        updates.default_category = aiClassification.category as string
      if (!existing.ico && extra?.ico) updates.ico = extra.ico
      if (!existing.bank_account && extra?.bank_account) updates.bank_account = extra.bank_account
      if (extra?.dic) updates.dic = extra.dic
      if (extra?.address) updates.address = extra.address
      if (Object.keys(updates).length > 0) {
        await supabase.from('suppliers').update(updates).eq('id', existing.id)
      }
      return existing.id
    }

    // Create new supplier
    const { data: newSupplier } = await supabase
      .from('suppliers')
      .insert({
        name: supplierName,
        normalized_name: normalized,
        default_category: (aiClassification?.category as string) || null,
        default_account: (aiClassification?.suggested_account as string) || null,
        ico: extra?.ico || null,
        dic: extra?.dic || null,
        address: extra?.address || null,
        bank_account: extra?.bank_account || null,
        notes: 'Automaticky vytvořen z OCR dokladu',
      })
      .select('id')
      .single()

    return newSupplier?.id || null
  } catch (err) {
    console.error('upsertSupplier error:', err)
    return null
  }
}
