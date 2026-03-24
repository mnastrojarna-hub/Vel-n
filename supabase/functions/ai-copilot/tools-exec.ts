// Tool executor — thin router that delegates to split modules
import type { SB } from './tools-constants.ts'
import { execReadCore } from './tools-read-core.ts'
import { execReadFinance } from './tools-read-finance.ts'
import { execReadMisc } from './tools-read-misc.ts'
import { execAnalytics } from './tools-analytics.ts'
import { execWriteCore } from './tools-write-core.ts'
import { execWriteOps } from './tools-write-ops.ts'

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
    // Try each module in order
    let result: unknown

    result = await execReadCore(toolName, toolInput, supabaseAdmin)
    if (result !== null) { logTool(toolName, startTime); return result }

    result = await execReadFinance(toolName, toolInput, supabaseAdmin)
    if (result !== null) { logTool(toolName, startTime); return result }

    result = await execReadMisc(toolName, toolInput, supabaseAdmin)
    if (result !== null) { logTool(toolName, startTime); return result }

    result = await execAnalytics(toolName, toolInput, supabaseAdmin)
    if (result !== null) { logTool(toolName, startTime); return result }

    result = await execWriteCore(toolName, toolInput, supabaseAdmin, dryRun)
    if (result !== null) { logTool(toolName, startTime); return result }

    result = await execWriteOps(toolName, toolInput, supabaseAdmin, dryRun)
    if (result !== null) { logTool(toolName, startTime); return result }

    return { error: `Unknown tool: ${toolName}` }
  } catch (err) {
    console.error(`ai-copilot tool error: ${toolName}`, err)
    return { error: `Tool ${toolName} failed: ${(err as Error).message}` }
  }
}

function logTool(name: string, start: number) {
  console.log(`ai-copilot tool: ${name} (${Date.now() - start}ms)`)
}
