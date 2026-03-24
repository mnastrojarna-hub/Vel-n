// E2E Test tools — create test data, verify edge functions, check app consistency
import type { SB } from './tools-constants.ts'

// deno-lint-ignore no-explicit-any
type R = Record<string, any>

const TEST_EMAIL_PREFIX = 'test.ai.tester+'
const TEST_PROMO_PREFIX = 'AITEST_'

export async function execE2ETest(name: string, input: R, sb: SB): Promise<unknown> {
  const now = new Date()

  switch (name) {
    // === CREATE TEST USER ===
    case 'create_test_user': {
      const suffix = Date.now().toString(36)
      const email = `${TEST_EMAIL_PREFIX}${suffix}@motogo24.cz`
      const password = `Test${suffix}!2024`
      // Create auth user
      const { data: authUser, error: authErr } = await sb.auth.admin.createUser({
        email, password, email_confirm: true,
        user_metadata: { full_name: `AI Tester ${suffix}`, phone: '+420000000000' },
      })
      if (authErr) return { error: `Auth: ${authErr.message}` }
      // Profile should be auto-created by handle_new_user trigger
      // Wait a moment and verify
      const { data: profile } = await sb.from('profiles').select('*').eq('id', authUser.user.id).single()
      return {
        status: 'created',
        test_user: { id: authUser.user.id, email, password, profile_exists: !!profile },
        instructions: `Testovací účet vytvořen. Přihlaste se na ${email} / ${password}. Po testování smažte účet.`,
      }
    }

    // === CREATE TEST PROMO CODE (100%) ===
    case 'create_test_promo': {
      const code = `${TEST_PROMO_PREFIX}${Date.now().toString(36).toUpperCase()}`
      const { data, error } = await sb.from('promo_codes').insert({
        code, type: 'percent', discount_value: 100, max_uses: 10,
        valid_to: new Date(now.getTime() + 7 * 86400000).toISOString().slice(0, 10),
        is_active: true, description: 'AI Tester - 100% sleva pro testování',
      }).select().single()
      if (error) return { error: error.message }
      return {
        status: 'created',
        promo_code: code, id: data?.id,
        instructions: `100% slevový kód "${code}" vytvořen (platný 7 dní, max 10 použití). Použijte pro testování plateb bez reálné platby.`,
      }
    }

    // === CLEANUP TEST DATA ===
    case 'cleanup_test_data': {
      const results: R = { users: 0, promos: 0, bookings: 0 }
      // Delete test promo codes
      const { data: promos } = await sb.from('promo_codes').select('id, code').ilike('code', `${TEST_PROMO_PREFIX}%`)
      if (promos && promos.length > 0) {
        await sb.from('promo_codes').delete().ilike('code', `${TEST_PROMO_PREFIX}%`)
        results.promos = promos.length
      }
      // Find test users
      const { data: testProfiles } = await sb.from('profiles').select('id, email').ilike('email', `${TEST_EMAIL_PREFIX}%`)
      if (testProfiles && testProfiles.length > 0) {
        for (const p of testProfiles) {
          // Delete bookings
          const { count } = await sb.from('bookings').select('id', { count: 'exact', head: true }).eq('user_id', p.id)
          if ((count || 0) > 0) {
            await sb.from('bookings').delete().eq('user_id', p.id)
            results.bookings += count || 0
          }
          // Delete auth user
          await sb.auth.admin.deleteUser(p.id)
          results.users++
        }
      }
      return { status: 'cleaned', ...results, summary: `Smazáno: ${results.users} testovacích uživatelů, ${results.promos} promo kódů, ${results.bookings} bookings` }
    }

    // === CHECK EDGE FUNCTIONS HEALTH ===
    case 'check_edge_functions': {
      const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
      const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || ''
      const functions = [
        'admin-auth', 'ai-copilot', 'generate-document', 'generate-invoice',
        'process-payment', 'process-refund', 'send-booking-email', 'send-message',
        'scan-document', 'receive-invoice', 'manage-payment-methods', 'webhook-receiver',
      ]
      const results: R[] = []
      for (const fn of functions) {
        try {
          const res = await fetch(`${supabaseUrl}/functions/v1/${fn}`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${anonKey}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ health_check: true }),
          })
          results.push({ function: fn, status: res.status < 500 ? 'ok' : 'error', http_status: res.status })
        } catch (e) {
          results.push({ function: fn, status: 'error', error: (e as Error).message })
        }
      }
      const ok = results.filter(r => r.status === 'ok').length
      return { functions: results, total: results.length, healthy: ok, unhealthy: results.length - ok }
    }

    // === VERIFY APP DATA CONSISTENCY ===
    case 'verify_app_consistency': {
      const issues: R[] = []
      // 1. Active motorcycles must have prices
      const { data: noPriceMotos } = await sb.from('motorcycles').select('id, model, spz').eq('status', 'active').is('price_weekday', null)
      if (noPriceMotos?.length) issues.push({ area: 'pricing', severity: 'high', issue: 'Aktivní motorky bez ceny', count: noPriceMotos.length, details: noPriceMotos })
      // 2. Active motorcycles must have branch
      const { data: noBranchMotos } = await sb.from('motorcycles').select('id, model, spz').eq('status', 'active').is('branch_id', null)
      if (noBranchMotos?.length) issues.push({ area: 'fleet', severity: 'high', issue: 'Aktivní motorky bez pobočky', count: noBranchMotos.length, details: noBranchMotos })
      // 3. Active motorcycles must have images
      const { data: noImageMotos } = await sb.from('motorcycles').select('id, model, spz').eq('status', 'active').is('image_url', null)
      if (noImageMotos?.length) issues.push({ area: 'content', severity: 'medium', issue: 'Motorky bez fotky', count: noImageMotos.length })
      // 4. Branches must have accessories
      const { data: branches } = await sb.from('branches').select('id, name')
      for (const br of (branches || [])) {
        const { count } = await sb.from('branch_accessories').select('id', { count: 'exact', head: true }).eq('branch_id', br.id)
        if ((count || 0) === 0) issues.push({ area: 'branch', severity: 'medium', issue: `Pobočka "${br.name}" nemá příslušenství`, branch_id: br.id })
      }
      // 5. Email templates must exist
      const required_templates = ['booking_reserved', 'booking_completed', 'booking_cancelled', 'voucher_purchased']
      const { data: templates } = await sb.from('email_templates').select('slug')
      const slugs = new Set((templates || []).map((t: R) => t.slug))
      for (const slug of required_templates) {
        if (!slugs.has(slug)) issues.push({ area: 'templates', severity: 'high', issue: `Chybí email šablona: ${slug}` })
      }
      // 6. Document templates
      const { data: docTemplates } = await sb.from('document_templates').select('type, active')
      const activeTypes = new Set((docTemplates || []).filter((t: R) => t.active).map((t: R) => t.type))
      for (const t of ['rental_contract', 'vop', 'handover_protocol']) {
        if (!activeTypes.has(t)) issues.push({ area: 'templates', severity: 'medium', issue: `Chybí aktivní šablona: ${t}` })
      }
      // 7. App settings
      const { data: settings } = await sb.from('app_settings').select('key')
      const keys = new Set((settings || []).map((s: R) => s.key))
      for (const k of ['company_info', 'header_banner']) {
        if (!keys.has(k)) issues.push({ area: 'settings', severity: 'high', issue: `Chybí app_setting: ${k}` })
      }
      // 8. Products must have images if active
      const { data: noImgProducts } = await sb.from('products').select('id, name').eq('is_active', true).is('images', null)
      if (noImgProducts?.length) issues.push({ area: 'eshop', severity: 'low', issue: 'Aktivní produkty bez fotek', count: noImgProducts.length })

      const high = issues.filter(i => i.severity === 'high').length
      const medium = issues.filter(i => i.severity === 'medium').length
      return { issues, total: issues.length, high, medium, low: issues.length - high - medium, app_ready: high === 0, timestamp: now.toISOString() }
    }

    // === GENERATE FULL E2E TEST REPORT ===
    case 'generate_e2e_report': {
      // Comprehensive check of everything a customer would see
      const report: R = { sections: [], timestamp: now.toISOString() }

      // Fleet availability
      const { data: activeMotos } = await sb.from('motorcycles').select('id, model, brand, category, price_weekday, image_url, branch_id, status, deposit_amount').eq('status', 'active')
      const readyMotos = (activeMotos || []).filter((m: R) => m.price_weekday && m.image_url && m.branch_id)
      report.sections.push({
        name: 'Dostupné motorky',
        status: readyMotos.length > 0 ? 'ok' : 'fail',
        details: `${readyMotos.length}/${(activeMotos || []).length} motorek kompletních (cena + fotka + pobočka)`,
        issues: (activeMotos || []).filter((m: R) => !m.price_weekday || !m.image_url || !m.branch_id).map((m: R) => `${m.model}: ${!m.price_weekday ? 'bez ceny' : ''} ${!m.image_url ? 'bez fotky' : ''} ${!m.branch_id ? 'bez pobočky' : ''}`),
      })

      // Active promo codes
      const { data: promos } = await sb.from('promo_codes').select('code, type, discount_value, is_active, valid_to').eq('is_active', true)
      const expired = (promos || []).filter((p: R) => p.valid_to && p.valid_to < now.toISOString().slice(0, 10))
      report.sections.push({
        name: 'Promo kódy',
        status: expired.length === 0 ? 'ok' : 'warn',
        details: `${(promos || []).length} aktivních, ${expired.length} expirovaných (ale stále active)`,
        issues: expired.map((p: R) => `${p.code} expiroval ${p.valid_to} ale je stále is_active=true`),
      })

      // Open branches
      const { data: openBranches } = await sb.from('branches').select('id, name, is_open')
      const closed = (openBranches || []).filter((b: R) => !b.is_open)
      report.sections.push({
        name: 'Pobočky',
        status: closed.length < (openBranches || []).length ? 'ok' : 'warn',
        details: `${(openBranches || []).length - closed.length}/${(openBranches || []).length} otevřených`,
      })

      // E-shop products
      const { data: products } = await sb.from('products').select('id, name, price, stock_quantity, is_active').eq('is_active', true)
      const outOfStock = (products || []).filter((p: R) => (p.stock_quantity || 0) <= 0)
      report.sections.push({
        name: 'E-shop produkty',
        status: outOfStock.length === 0 ? 'ok' : 'warn',
        details: `${(products || []).length} aktivních, ${outOfStock.length} vyprodaných`,
        issues: outOfStock.map((p: R) => `${p.name}: stock=0 ale stále aktivní`),
      })

      const failCount = report.sections.filter((s: R) => s.status === 'fail').length
      const warnCount = report.sections.filter((s: R) => s.status === 'warn').length
      report.summary = { total_sections: report.sections.length, pass: report.sections.length - failCount - warnCount, fail: failCount, warn: warnCount }
      report.overall = failCount === 0 ? (warnCount === 0 ? 'PASS' : 'PASS WITH WARNINGS') : 'FAIL'

      return report
    }

    default: return null
  }
}
