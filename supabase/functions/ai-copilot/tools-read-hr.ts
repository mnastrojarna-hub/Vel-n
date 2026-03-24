// Read tools: HR — employees, payrolls, attendance, vacations, shifts, documents
import type { SB } from './tools-constants.ts'

// deno-lint-ignore no-explicit-any
type R = Record<string, any>

export async function execReadHR(name: string, input: R, sb: SB): Promise<unknown> {
  switch (name) {
    case 'get_employees': {
      const { data } = await sb.from('acc_employees').select('id, name, position, phone, email, contract_type, gross_salary, hourly_rate, vacation_days_total, vacation_days_used, created_at').order('name')
      return { employees: data || [], count: (data || []).length }
    }

    case 'get_employee_detail': {
      const id = input.employee_id as string
      if (!id) return { error: 'employee_id je povinný' }
      const [empR, attR, vacR, shiftR, docR, payR] = await Promise.all([
        sb.from('acc_employees').select('*').eq('id', id).single(),
        sb.from('emp_attendance').select('*').eq('employee_id', id).order('date', { ascending: false }).limit(30),
        sb.from('emp_vacations').select('*').eq('employee_id', id).order('start_date', { ascending: false }).limit(10),
        sb.from('emp_shifts').select('*').eq('employee_id', id).order('date', { ascending: false }).limit(30),
        sb.from('emp_documents').select('*').eq('employee_id', id).order('created_at', { ascending: false }),
        sb.from('acc_payrolls').select('*').eq('employee_id', id).order('period', { ascending: false }).limit(12),
      ])
      if (!empR.data) return { error: 'Zaměstnanec nenalezen' }
      return { employee: empR.data, attendance: attR.data || [], vacations: vacR.data || [], shifts: shiftR.data || [], documents: docR.data || [], payrolls: payR.data || [] }
    }

    case 'get_attendance_overview': {
      const days = (input.days as number) || 7
      const since = new Date(Date.now() - days * 86400000).toISOString().slice(0, 10)
      const { data } = await sb.from('emp_attendance').select('*, acc_employees(name, position)').gte('date', since).order('date', { ascending: false })
      const byStatus: R = {}
      for (const a of (data || [])) { const s = a.status; byStatus[s] = (byStatus[s] || 0) + 1 }
      return { attendance: data || [], count: (data || []).length, by_status: byStatus }
    }

    case 'get_pending_vacations': {
      const { data } = await sb.from('emp_vacations').select('*, acc_employees(name, position)').eq('status', 'pending').order('start_date')
      return { vacations: data || [], count: (data || []).length }
    }

    case 'get_shifts_overview': {
      const days = (input.days_ahead as number) || 7
      const from = new Date().toISOString().slice(0, 10)
      const to = new Date(Date.now() + days * 86400000).toISOString().slice(0, 10)
      const { data } = await sb.from('emp_shifts').select('*, acc_employees(name, position)').gte('date', from).lte('date', to).order('date')
      return { shifts: data || [], count: (data || []).length }
    }

    case 'get_payrolls': {
      const limit = (input.limit as number) || 20
      const { data } = await sb.from('acc_payrolls').select('*, acc_employees(name)').order('period', { ascending: false }).limit(limit)
      return { payrolls: data || [], count: (data || []).length }
    }

    default: return null
  }
}
