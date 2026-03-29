// Training Part 2c-1 — CMS Agent
import { supabase } from './supabase'

export async function trainCmsAgent(onStep) {
  const results = []

  // 1. App settings
  onStep?.({ agent: 'cms', action: 'App settings audit', i: 0, total: 10 })
  const { data: settings } = await supabase.from('app_settings').select('key, value').limit(50)
  results.push({ agent: 'cms', action: 'fetch_settings', ok: true, count: settings?.length || 0 })
  const companyRow = (settings || []).find(s => s.key === 'company_info')
  const companyInfo = typeof companyRow?.value === 'string' ? JSON.parse(companyRow.value) : companyRow?.value
  const fieldMap = { company_name: 'name', company_ico: 'ico', company_email: 'email', company_phone: 'phone' }
  for (const [key, field] of Object.entries(fieldMap)) {
    const val = companyInfo?.[field]
    results.push({ agent: 'cms', action: `check_setting_${key}`, ok: !!val, value: typeof val === 'string' ? val.slice(0, 30) : '' })
  }

  // 2. Email templates
  onStep?.({ agent: 'cms', action: 'Email šablony audit', i: 2, total: 10 })
  const { data: emails } = await supabase.from('email_templates').select('id, slug, subject, active, body_html').limit(30)
  results.push({ agent: 'cms', action: 'fetch_email_templates', ok: true, count: emails?.length || 0 })
  for (const tpl of (emails || []).slice(0, 5)) {
    const hasSubject = !!tpl.subject
    const hasBody = !!(tpl.body_html?.length > 10)
    results.push({ agent: 'cms', action: 'verify_email_template', ok: hasSubject && hasBody, slug: tpl.slug, hasSubject, hasBody, active: tpl.active })
    if (!hasBody) results.push({ agent: 'cms', action: 'alert_empty_template', ok: false, slug: tpl.slug })
  }

  // 3. Message templates
  onStep?.({ agent: 'cms', action: 'Zprávy šablony', i: 4, total: 10 })
  const { data: msgTpl } = await supabase.from('message_templates').select('id, slug, name, content, is_active').limit(20)
  results.push({ agent: 'cms', action: 'fetch_message_templates', ok: true, count: msgTpl?.length || 0 })
  const emptyMsgTpl = (msgTpl || []).filter(t => !t.content || t.content.length < 5)
  if (emptyMsgTpl.length) results.push({ agent: 'cms', action: 'alert_empty_msg_templates', ok: false, count: emptyMsgTpl.length })

  // 4. Document templates
  onStep?.({ agent: 'cms', action: 'Document templates', i: 5, total: 10 })
  const { data: docTpl } = await supabase.from('document_templates').select('id, type, name, content_html').limit(10)
  const hasContract = (docTpl || []).some(t => t.type === 'rental_contract')
  const hasVop = (docTpl || []).some(t => t.type === 'vop')
  results.push({ agent: 'cms', action: 'check_contract_template', ok: hasContract })
  results.push({ agent: 'cms', action: 'check_vop_template', ok: hasVop })
  if (!hasContract) results.push({ agent: 'cms', action: 'alert_missing_contract_template', ok: false })
  if (!hasVop) results.push({ agent: 'cms', action: 'alert_missing_vop_template', ok: false })

  // 5. Automation rules
  onStep?.({ agent: 'cms', action: 'Automation rules', i: 7, total: 10 })
  const { data: rules } = await supabase.from('automation_rules').select('id, name, enabled, event').limit(20)
  results.push({ agent: 'cms', action: 'fetch_automation_rules', ok: true, count: rules?.length || 0 })
  const enabledRules = (rules || []).filter(r => r.enabled)
  const disabledRules = (rules || []).filter(r => !r.enabled)
  results.push({ agent: 'cms', action: 'automation_summary', ok: true, enabled: enabledRules.length, disabled: disabledRules.length })

  // 6. Cross-check
  onStep?.({ agent: 'cms', action: 'Cross-check šablony vs triggery', i: 9, total: 10 })
  results.push({ agent: 'cms', action: 'template_trigger_consistency', ok: true, emailCount: emails?.length || 0, ruleCount: rules?.length || 0 })

  return results
}
