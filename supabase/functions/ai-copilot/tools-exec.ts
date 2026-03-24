// Tool executor — thin router that delegates to split modules
import type { SB } from './tools-constants.ts'
import { execReadCore } from './tools-read-core.ts'
import { execReadFinance } from './tools-read-finance.ts'
import { execReadMisc } from './tools-read-misc.ts'
import { execReadHR } from './tools-read-hr.ts'
import { execReadAccounting } from './tools-read-accounting.ts'
import { execReadExtra } from './tools-read-extra.ts'
import { execAnalytics } from './tools-analytics.ts'
import { execWriteCore } from './tools-write-core.ts'
import { execWriteOps } from './tools-write-ops.ts'
import { execOrchestrator } from './tools-orchestrator.ts'

// Write tools that require confirmation
const WRITE_TOOLS = new Set([
  'update_booking_status', 'update_booking_details', 'confirm_booking_payment',
  'update_motorcycle', 'update_motorcycle_pricing', 'update_branch', 'update_branch_accessories',
  'update_customer', 'send_customer_message',
  'update_invoice_status', 'create_accounting_entry', 'match_delivery_note',
  'create_service_order', 'update_service_order', 'create_maintenance_log',
  'create_attendance', 'manage_vacation', 'manage_shifts',
  'update_shop_order', 'update_product', 'create_promo_code',
  'update_app_setting', 'update_feature_flag',
  'update_sos_incident',
  'generate_test_report', 'check_data_integrity',
])

export function isWriteTool(name: string): boolean {
  return WRITE_TOOLS.has(name)
}

export async function executeTool(
  toolName: string,
  toolInput: Record<string, unknown>,
  supabaseAdmin: SB,
  dryRun = false,
): Promise<unknown> {
  const startTime = Date.now()
  try {
    let result: unknown
    const modules = [
      () => execReadCore(toolName, toolInput, supabaseAdmin),
      () => execReadFinance(toolName, toolInput, supabaseAdmin),
      () => execReadMisc(toolName, toolInput, supabaseAdmin),
      () => execReadHR(toolName, toolInput, supabaseAdmin),
      () => execReadAccounting(toolName, toolInput, supabaseAdmin),
      () => execReadExtra(toolName, toolInput, supabaseAdmin),
      () => execAnalytics(toolName, toolInput, supabaseAdmin),
      () => execWriteCore(toolName, toolInput, supabaseAdmin, dryRun),
      () => execWriteOps(toolName, toolInput, supabaseAdmin, dryRun),
      () => execOrchestrator(toolName, toolInput, supabaseAdmin),
    ]
    for (const mod of modules) {
      result = await mod()
      if (result !== null) { logTool(toolName, startTime); return result }
    }
    return { error: `Unknown tool: ${toolName}` }
  } catch (err) {
    console.error(`ai-copilot tool error: ${toolName}`, err)
    return { error: `Tool ${toolName} failed: ${(err as Error).message}` }
  }
}

function logTool(name: string, start: number) {
  console.log(`ai-copilot tool: ${name} (${Date.now() - start}ms)`)
}
