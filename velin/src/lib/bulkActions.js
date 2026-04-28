import { supabase } from './supabase'

/**
 * Export an array of objects to a CSV file (downloads it).
 * @param {string} filename — without extension
 * @param {Array<{key: string, label: string, format?: (v: any, row: any) => string}>} columns
 * @param {Array<object>} rows
 */
export function exportToCsv(filename, columns, rows) {
  const headers = columns.map(c => c.label)
  const data = rows.map(r => columns.map(c => {
    const v = r[c.key]
    if (c.format) return c.format(v, r)
    if (v === null || v === undefined) return ''
    if (Array.isArray(v)) return v.join('|')
    if (typeof v === 'object') return JSON.stringify(v)
    return String(v)
  }))
  const csv = [headers, ...data]
    .map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(','))
    .join('\n')
  // BOM for Excel UTF-8
  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `${filename}-${new Date().toISOString().slice(0, 10)}.csv`
  a.click()
  URL.revokeObjectURL(url)
}

export async function logAdminAudit(action, details) {
  try {
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
  } catch {}
}

/**
 * Bulk update rows in a Supabase table by id.
 */
export async function bulkUpdate(table, ids, patch, auditAction = null) {
  if (!ids?.length) return { error: 'no rows' }
  const { error } = await supabase.from(table).update(patch).in('id', ids)
  if (error) return { error: error.message }
  if (auditAction) await logAdminAudit(auditAction, { count: ids.length, patch, ids })
  return { ok: true }
}

/**
 * Bulk delete rows in a Supabase table by id.
 */
export async function bulkDelete(table, ids, auditAction = null) {
  if (!ids?.length) return { error: 'no rows' }
  const { error } = await supabase.from(table).delete().in('id', ids)
  if (error) return { error: error.message }
  if (auditAction) await logAdminAudit(auditAction, { count: ids.length, ids })
  return { ok: true }
}
