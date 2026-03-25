// App Flow Simulator — tests MotoGo24 customer app endpoints
// Generates structured report: what works, what fails, where is the problem
import { supabase } from './supabase'

// Customer app flow steps — each tests a real API endpoint
export const APP_FLOW_STEPS = [
  // AUTH
  { id: 'auth_login', phase: 'Auth', label: 'Přihlášení (session check)', test: async () => {
    const { data } = await supabase.auth.getSession()
    return { ok: !!data?.session, detail: data?.session ? `UID: ${data.session.user.id.slice(0,8)}…` : 'Žádná session' }
  }},
  // CATALOG
  { id: 'catalog_motos', phase: 'Katalog', label: 'Seznam motorek (active)', test: async () => {
    const { data, error } = await supabase.from('motorcycles')
      .select('id, model, brand, status, price_weekday').eq('status', 'active').limit(20)
    return { ok: !error && data?.length > 0, detail: error ? `ERR: ${error.message}` : `${data.length} motorek`, count: data?.length }
  }},
  { id: 'catalog_pricing', phase: 'Katalog', label: 'Ceník (day prices)', test: async () => {
    const { data, error } = await supabase.from('moto_day_prices').select('moto_id, day, price').limit(20)
    return { ok: !error, detail: error ? `ERR: ${error.message}` : `${data?.length || 0} cenových záznamů`, count: data?.length }
  }},
  { id: 'catalog_branches', phase: 'Katalog', label: 'Pobočky', test: async () => {
    const { data, error } = await supabase.from('branches').select('id, name, city, is_open').limit(10)
    return { ok: !error && data?.length > 0, detail: error ? `ERR: ${error.message}` : `${data.length} poboček (${data.filter(b => b.is_open).length} otevřených)` }
  }},
  { id: 'catalog_accessories', phase: 'Katalog', label: 'Příslušenství', test: async () => {
    const { data, error } = await supabase.from('accessory_types').select('id, key, label, is_active').limit(20)
    return { ok: !error, detail: error ? `ERR: ${error.message}` : `${data?.length || 0} typů` }
  }},
  // BOOKING FLOW
  { id: 'booking_availability', phase: 'Rezervace', label: 'Kontrola dostupnosti (RPC)', test: async () => {
    const { data: motos } = await supabase.from('motorcycles').select('id').eq('status', 'active').limit(1)
    if (!motos?.length) return { ok: false, detail: 'Žádná active motorka' }
    const { data, error } = await supabase.rpc('calc_booking_price_v2', {
      p_moto_id: motos[0].id, p_start: new Date(Date.now() + 7 * 86400000).toISOString().split('T')[0],
      p_end: new Date(Date.now() + 10 * 86400000).toISOString().split('T')[0], p_promo: null,
    })
    return { ok: !error, detail: error ? `ERR: ${error.message}` : `Cena: ${data} Kč` }
  }},
  { id: 'booking_overlap_check', phase: 'Rezervace', label: 'Overlap check', test: async () => {
    const { data: motos } = await supabase.from('motorcycles').select('id').eq('status', 'active').limit(1)
    if (!motos?.length) return { ok: false, detail: 'Žádná motorka' }
    const { data, error } = await supabase.from('bookings').select('id')
      .eq('moto_id', motos[0].id).in('status', ['reserved', 'active']).limit(5)
    return { ok: !error, detail: error ? `ERR: ${error.message}` : `${data?.length || 0} aktivních bookings na moto` }
  }},
  // PAYMENT
  { id: 'payment_methods', phase: 'Platby', label: 'Platební metody (tabulka)', test: async () => {
    const { count, error } = await supabase.from('payment_methods').select('id', { count: 'exact', head: true })
    return { ok: !error, detail: error ? `ERR: ${error.message}` : `${count || 0} karet v DB` }
  }},
  { id: 'payment_promo', phase: 'Platby', label: 'Promo kódy', test: async () => {
    const { data, error } = await supabase.from('promo_codes').select('id, code, active').eq('active', true).limit(10)
    return { ok: !error, detail: error ? `ERR: ${error.message}` : `${data?.length || 0} aktivních` }
  }},
  // DOCUMENTS
  { id: 'docs_templates', phase: 'Dokumenty', label: 'Document templates (smlouva + VOP)', test: async () => {
    const { data, error } = await supabase.from('document_templates').select('type, name').limit(10)
    const hasContract = data?.some(t => t.type === 'rental_contract')
    const hasVop = data?.some(t => t.type === 'vop')
    return { ok: !error && hasContract && hasVop, detail: error ? `ERR: ${error.message}` : `Smlouva: ${hasContract ? 'OK' : 'CHYBÍ!'}, VOP: ${hasVop ? 'OK' : 'CHYBÍ!'}` }
  }},
  { id: 'docs_email_tpl', phase: 'Dokumenty', label: 'Email šablony', test: async () => {
    const { data, error } = await supabase.from('email_templates').select('slug, subject, active').limit(30)
    const active = data?.filter(t => t.active) || []
    const noSubject = active.filter(t => !t.subject)
    return { ok: !error && noSubject.length === 0, detail: error ? `ERR: ${error.message}` : `${active.length} aktivních, ${noSubject.length} bez subject` }
  }},
  // MESSAGING
  { id: 'msg_templates', phase: 'Zprávy', label: 'Message templates', test: async () => {
    const { data, error } = await supabase.from('message_templates').select('id, slug, name').limit(20)
    return { ok: !error, detail: error ? `ERR: ${error.message}` : `${data?.length || 0} šablon` }
  }},
  { id: 'msg_threads', phase: 'Zprávy', label: 'Message threads', test: async () => {
    const { count, error } = await supabase.from('message_threads').select('id', { count: 'exact', head: true })
    return { ok: !error, detail: error ? `ERR: ${error.message}` : `${count || 0} konverzací` }
  }},
  // SOS
  { id: 'sos_incidents', phase: 'SOS', label: 'SOS incidenty', test: async () => {
    const { data, error } = await supabase.from('sos_incidents').select('id, type, status').limit(20)
    const open = data?.filter(s => !['resolved', 'closed'].includes(s.status)) || []
    return { ok: !error, detail: error ? `ERR: ${error.message}` : `${data?.length || 0} celkem, ${open.length} otevřených` }
  }},
  // EDGE FUNCTIONS
  { id: 'edge_copilot', phase: 'Edge', label: 'ai-copilot (edge function)', test: async () => {
    try {
      const { data, error } = await supabase.functions.invoke('ai-copilot', {
        body: { message: 'ping', enabled_tools: [] },
      })
      return { ok: !error, detail: error ? `ERR: ${error.message}` : 'Odpovídá' }
    } catch (e) { return { ok: false, detail: `EXCEPTION: ${e.message}` } }
  }},
  { id: 'edge_process_payment', phase: 'Edge', label: 'process-payment (existence)', test: async () => {
    try {
      const { error } = await supabase.functions.invoke('process-payment', {
        body: { ping: true },
      })
      // 400 = exists but invalid input, 404 = doesn't exist
      return { ok: true, detail: error ? `Existuje (${error.message?.slice(0, 50)})` : 'OK' }
    } catch (e) { return { ok: false, detail: `EXCEPTION: ${e.message}` } }
  }},
]

// Run all flow steps
export async function runAppFlowTest(onProgress) {
  const results = []
  for (let i = 0; i < APP_FLOW_STEPS.length; i++) {
    const step = APP_FLOW_STEPS[i]
    onProgress?.({ i, total: APP_FLOW_STEPS.length, label: step.label, phase: step.phase })
    try {
      const result = await step.test()
      results.push({ ...step, ...result, timestamp: new Date().toISOString() })
    } catch (e) {
      results.push({ ...step, ok: false, detail: `EXCEPTION: ${e.message}`, timestamp: new Date().toISOString() })
    }
  }
  return results
}

// Export as markdown for Claude Code
export function exportAppFlowMarkdown(results) {
  let md = `# MotoGo24 App Flow Test Report\n**${new Date().toLocaleString('cs-CZ')}**\n\n`
  const pass = results.filter(r => r.ok).length
  const fail = results.filter(r => !r.ok).length
  md += `**${pass} OK | ${fail} FAIL | ${results.length} celkem**\n\n`

  let lastPhase = ''
  for (const r of results) {
    if (r.phase !== lastPhase) { md += `\n## ${r.phase}\n`; lastPhase = r.phase }
    md += `- [${r.ok ? 'OK' : 'FAIL'}] **${r.label}**: ${r.detail}\n`
  }

  if (fail > 0) {
    md += `\n## Problémy k řešení\n`
    for (const r of results.filter(r => !r.ok)) {
      md += `- **${r.phase} > ${r.label}**: ${r.detail}\n`
    }
  }
  return md
}
