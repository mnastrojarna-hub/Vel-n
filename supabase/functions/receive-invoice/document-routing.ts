// ===== receive-invoice/document-routing.ts =====
// Routes parsed documents to appropriate tables based on document_type

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

export async function routeDocument(
  parsed: Record<string, any>,
  financialEventId: string,
  supabase: ReturnType<typeof createClient>
) {
  try {
    switch (parsed.document_type) {
      case 'contract_purchase': {
        // Try to match with fleet via VIN/serial_number
        if (parsed.purchase?.serial_number) {
          const { data: moto } = await supabase
            .from('motorcycles')
            .select('id')
            .or(`vin.ilike.%${parsed.purchase.serial_number}%`)
            .maybeSingle()

          if (moto) {
            await supabase.from('financial_events')
              .update({ linked_entity_type: 'motorcycle', linked_entity_id: moto.id })
              .eq('id', financialEventId)
          }
        }

        // Long-term asset record
        await supabase.from('acc_long_term_assets').insert({
          name: parsed.purchase?.item_description || 'Neurčeno',
          category: 'vehicles',
          purchase_price: parsed.purchase?.amount_czk || 0,
          current_value: parsed.purchase?.amount_czk || 0,
          acquired_date: parsed.purchase?.payment_date || new Date().toISOString().slice(0, 10),
          depreciation_group: 2,
          depreciation_method: 'linear',
          invoice_number: parsed.invoice_number,
          supplier: parsed.purchase?.seller,
          status: 'active',
        })
        break
      }

      case 'contract_loan':
      case 'leasing': {
        // Main liability
        await supabase.from('acc_liabilities').insert({
          counterparty: parsed.loan?.provider,
          type: 'loan',
          amount: parsed.loan?.total_to_pay_czk || parsed.loan?.principal_czk || 0,
          variable_symbol: parsed.loan?.contract_number,
          due_date: parsed.loan?.last_payment_date,
          description: 'Úvěr/leasing: ' + (parsed.loan?.purpose || parsed.loan?.contract_number || ''),
          status: 'pending',
        })

        // Monthly payments
        if (parsed.loan?.first_payment_date && parsed.loan?.monthly_payment_czk) {
          const payments: any[] = []
          const current = new Date(parsed.loan.first_payment_date)
          const end = new Date(parsed.loan.last_payment_date)

          while (current <= end) {
            payments.push({
              counterparty: parsed.loan.provider,
              type: 'loan',
              amount: parsed.loan.monthly_payment_czk,
              due_date: current.toISOString().slice(0, 10),
              description: 'Splátka ' + current.toISOString().slice(0, 7),
              status: 'pending',
            })
            current.setMonth(current.getMonth() + 1)
          }
          if (payments.length > 0) {
            await supabase.from('acc_liabilities').insert(payments)
          }
        }
        break
      }

      case 'contract_employment': {
        const contractTypeMap = (raw: string | null) => {
          if (!raw) return 'hpp'
          const r = raw.toLowerCase()
          if (r.includes('dpp')) return 'dpp'
          if (r.includes('dpč') || r.includes('dpc')) return 'dpc'
          if (r.includes('ičo') || r.includes('ico')) return 'ico'
          return 'hpp'
        }

        await supabase.from('acc_employees').insert({
          name: parsed.employment?.employee_name || 'Neurčeno',
          contract_type: contractTypeMap(parsed.employment?.contract_type),
          gross_salary: parsed.employment?.gross_salary_czk || 0,
          start_date: parsed.employment?.start_date,
          end_date: parsed.employment?.end_date,
          active: false, // inactive until admin approves
        })

        await supabase.from('accounting_exceptions').insert({
          financial_event_id: financialEventId,
          reason: 'Nová pracovní smlouva ke schválení: ' + (parsed.employment?.employee_name || 'neuvedeno'),
          suggested_fix: {
            action: 'activate_employee',
            data: parsed.employment,
          },
        })
        break
      }

      case 'insurance': {
        await supabase.from('acc_liabilities').insert({
          counterparty: parsed.insurance?.provider,
          type: 'other',
          amount: parsed.insurance?.annual_premium_czk || 0,
          due_date: parsed.insurance?.valid_from,
          description: 'Pojistné: ' + (parsed.insurance?.coverage_type || '') + ' ' + (parsed.insurance?.contract_number || ''),
          status: 'pending',
        })

        // Store valid_to in financial_event metadata
        if (parsed.insurance?.valid_to) {
          const { data: currentEvent } = await supabase
            .from('financial_events')
            .select('metadata')
            .eq('id', financialEventId)
            .single()

          await supabase.from('financial_events').update({
            metadata: {
              ...(currentEvent?.metadata || {}),
              insurance_valid_to: parsed.insurance.valid_to,
            },
          }).eq('id', financialEventId)
        }
        break
      }
    }
  } catch (err) {
    console.error('routeDocument error:', err)
    // Non-fatal — document was still saved to financial_events
  }
}
