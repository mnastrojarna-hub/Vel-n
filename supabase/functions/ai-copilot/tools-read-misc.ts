// Read tools 19-25: Documents, Reviews, CMS, Audit, Government, SOS Detail, Pricing
import type { SB } from './tools-constants.ts'

// deno-lint-ignore no-explicit-any
type R = Record<string, any>

export async function execReadMisc(name: string, input: R, sb: SB): Promise<unknown> {
  const now = new Date()

  switch (name) {
    case 'get_documents': {
      try {
        const limit = (input.limit as number) || 20
        const docType = input.type as string | undefined
        if (docType === 'contracts') { const { data } = await sb.from('documents').select('id, type, user_id, created_at').order('created_at', { ascending: false }).limit(limit); return { documents: data || [], total_count: (data || []).length } }
        if (docType === 'templates') { const { data } = await sb.from('document_templates').select('id, type, name, active, version, updated_at').order('name', { ascending: true }); return { documents: data || [], total_count: (data || []).length } }
        if (docType === 'generated') { const { data } = await sb.from('generated_documents').select('*').order('created_at', { ascending: false }).limit(limit); return { documents: data || [], total_count: (data || []).length } }
        if (docType === 'emails') { const { data } = await sb.from('sent_emails').select('*').order('created_at', { ascending: false }).limit(limit); return { documents: data || [], total_count: (data || []).length } }
        const [cR, tR, gR, eR] = await Promise.all([
          sb.from('documents').select('id, type, created_at').order('created_at', { ascending: false }).limit(5),
          sb.from('document_templates').select('id, type, name, active').order('name', { ascending: true }),
          sb.from('generated_documents').select('id, created_at').order('created_at', { ascending: false }).limit(5),
          sb.from('sent_emails').select('id, created_at').order('created_at', { ascending: false }).limit(5),
        ])
        return { contracts: { recent: cR.data || [], count: (cR.data || []).length }, templates: { items: tR.data || [], count: (tR.data || []).length }, generated: { recent: gR.data || [], count: (gR.data || []).length }, emails: { recent: eR.data || [], count: (eR.data || []).length } }
      } catch { return { error: 'Table not available', data: [] } }
    }

    case 'get_reviews': {
      try {
        const limit = (input.limit as number) || 20
        let q = sb.from('reviews').select('id, user_id, rating, created_at').order('created_at', { ascending: false }).limit(limit)
        if (input.moto_id) q = q.eq('moto_id', input.moto_id)
        if (input.min_rating) q = q.gte('rating', input.min_rating)
        const { data: reviews, error: err } = await q
        if (err) throw err
        const uids = [...new Set((reviews || []).map((r: R) => r.user_id).filter(Boolean))]
        const { data: profiles } = uids.length > 0 ? await sb.from('profiles').select('id, full_name').in('id', uids) : { data: [] }
        const pm: R = {}; for (const p of (profiles || [])) pm[p.id] = p.full_name
        const enriched = (reviews || []).map((r: R) => ({ ...r, customer_name: pm[r.user_id] || null }))
        const ratings = (reviews || []).map((r: R) => r.rating as number).filter(Boolean)
        const avg = ratings.length > 0 ? Math.round(ratings.reduce((s, v) => s + v, 0) / ratings.length * 10) / 10 : null
        return { avg_rating: avg, total_count: (reviews || []).length, reviews: enriched }
      } catch { return { error: 'Table not available', data: [] } }
    }

    case 'get_cms_settings': {
      try {
        const section = input.section as string | undefined
        if (section === 'flags') { const { data } = await sb.from('feature_flags').select('*').order('name', { ascending: true }); return { feature_flags: data || [] } }
        if (section === 'variables') { const { data } = await sb.from('cms_variables').select('*').order('key', { ascending: true }); return { variables: data || [] } }
        if (section === 'settings') { const { data } = await sb.from('app_settings').select('*').order('key', { ascending: true }); return { app_settings: data || [] } }
        const [fR, vR, sR] = await Promise.all([
          sb.from('feature_flags').select('*').order('name', { ascending: true }),
          sb.from('cms_variables').select('*').order('key', { ascending: true }),
          sb.from('app_settings').select('*').order('key', { ascending: true }),
        ])
        return { feature_flags: fR.data || [], variables: vR.data || [], app_settings: sR.data || [] }
      } catch { return { error: 'Table not available', data: [] } }
    }

    case 'get_audit_log': {
      try {
        const limit = (input.limit as number) || 30
        let q = sb.from('admin_audit_log').select('id, admin_id, action, details, ip_address, created_at').order('created_at', { ascending: false }).limit(limit)
        if (input.admin_id) q = q.eq('admin_id', input.admin_id)
        if (input.action) q = q.ilike('action', `%${input.action}%`)
        const { data: logs, error: err } = await q
        if (err) throw err
        const aids = [...new Set((logs || []).map((l: R) => l.admin_id).filter(Boolean))]
        const { data: admins } = aids.length > 0 ? await sb.from('admin_users').select('id, email, name').in('id', aids) : { data: [] }
        const am: R = {}; for (const a of (admins || [])) am[a.id] = a
        return { logs: (logs || []).map((l: R) => ({ ...l, admin: am[l.admin_id] || null })), count: (logs || []).length }
      } catch { return { error: 'Table not available', data: [] } }
    }

    case 'get_government_overview': {
      try {
        const { data: motos, error: err } = await sb.from('motorcycles').select('id, model, brand, spz, stk_valid_until, insurance_price, status')
        if (err) throw err
        const today = now.toISOString().slice(0, 10)
        const d30 = new Date(now.getTime() + 30 * 86400000).toISOString().slice(0, 10)
        const d60 = new Date(now.getTime() + 60 * 86400000).toISOString().slice(0, 10)
        const d90 = new Date(now.getTime() + 90 * 86400000).toISOString().slice(0, 10)
        let expired = 0, w30 = 0, w60 = 0, w90 = 0, ok = 0, noStk = 0
        for (const m of (motos || [])) { const stk = m.stk_valid_until; if (!stk) { noStk++; continue }; if (stk < today) expired++; else if (stk <= d30) w30++; else if (stk <= d60) w60++; else if (stk <= d90) w90++; else ok++ }
        const totalIns = (motos || []).reduce((s: number, m: R) => s + (m.insurance_price || 0), 0)
        return { motorcycles: motos || [], stk_summary: { expired, within_30d: w30, within_60d: w60, within_90d: w90, ok, no_stk: noStk }, total_insurance_cost: totalIns }
      } catch { return { error: 'Table not available', data: [] } }
    }

    case 'get_sos_detail': {
      try {
        const incId = input.incident_id as string
        if (!incId) return { error: 'incident_id je povinný parametr' }
        const { data: incident, error: err } = await sb.from('sos_incidents').select('*').eq('id', incId).single()
        if (err || !incident) return { error: 'SOS incident nenalezen' }
        const { data: timeline } = await sb.from('sos_timeline').select('*').eq('incident_id', incId).order('created_at', { ascending: true })
        const [bR, mR, pR] = await Promise.all([
          incident.booking_id ? sb.from('bookings').select('id, start_date, end_date, status, total_price, payment_status').eq('id', incident.booking_id).single() : Promise.resolve({ data: null }),
          incident.moto_id ? sb.from('motorcycles').select('id, model, brand, spz, status').eq('id', incident.moto_id).single() : Promise.resolve({ data: null }),
          incident.user_id ? sb.from('profiles').select('id, full_name, email, phone').eq('id', incident.user_id).single() : Promise.resolve({ data: null }),
        ])
        return { incident, timeline: timeline || [], booking: bR.data || null, motorcycle: mR.data || null, customer: pR.data || null }
      } catch { return { error: 'Table not available', data: [] } }
    }

    case 'get_pricing_overview': {
      try {
        let q = sb.from('motorcycles').select('id, model, brand, spz, price_weekday, price_weekend, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, category, status')
        if (input.motorcycle_id) q = q.eq('id', input.motorcycle_id)
        const { data: motos, error: err } = await q
        if (err) throw err
        const mids = (motos || []).map((m: R) => m.id)
        const { data: dayPrices } = mids.length > 0 ? await sb.from('moto_day_prices').select('*').in('moto_id', mids) : { data: [] }
        const dpm: R = {}; for (const dp of (dayPrices || [])) { const mid = dp.moto_id; if (!dpm[mid]) dpm[mid] = []; dpm[mid].push(dp) }
        const enriched = (motos || []).map((m: R) => ({ id: m.id, model: m.model, brand: m.brand, spz: m.spz, category: m.category, status: m.status, prices_by_day: { mon: m.price_mon, tue: m.price_tue, wed: m.price_wed, thu: m.price_thu, fri: m.price_fri, sat: m.price_sat, sun: m.price_sun }, price_weekday: m.price_weekday, price_weekend: m.price_weekend, day_prices_table: dpm[m.id] || [] }))
        return { motorcycles: enriched }
      } catch { return { error: 'Table not available', data: [] } }
    }

    default: return null
  }
}
