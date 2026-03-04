/**
 * MotoGo24 — Edge Function: Inventory Check
 * Kontrola zásob pod minimem, automatické vytvoření objednávek.
 * Volá se z cron-daily nebo ručně.
 *
 * POST /functions/v1/inventory-check
 * Auth: SERVICE_ROLE_KEY
 */

import { corsResponse, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/supabase-client.ts';
import type { InventoryCheckResponse } from '../_shared/types.ts';

/** Ověří SERVICE_ROLE_KEY v Authorization headeru. */
function verifyServiceRole(authHeader: string | null): boolean {
  if (!authHeader) return false;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  return authHeader === `Bearer ${serviceRoleKey}`;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!verifyServiceRole(authHeader)) {
      return errorResponse('Service role key required', 401);
    }

    const admin = getAdminClient();

    // Najdi položky pod minimem
    const { data: lowStockItems, error: queryError } = await admin
      .from('inventory')
      .select('id, name, sku, stock, min_stock, unit, unit_price, supplier_id, branch_id')
      .filter('stock', 'lte', 'min_stock');

    if (queryError) {
      console.error('Inventory query error:', queryError);
      return errorResponse('Failed to query inventory', 500);
    }

    if (!lowStockItems || lowStockItems.length === 0) {
      const response: InventoryCheckResponse = {
        success: true,
        items_below_min: 0,
        orders_created: 0,
      };
      return jsonResponse(response);
    }

    let ordersCreated = 0;

    // Seskup položky podle dodavatele a pobočky
    const groupedItems = new Map<string, typeof lowStockItems>();
    for (const item of lowStockItems) {
      const key = `${item.supplier_id ?? 'unknown'}_${item.branch_id ?? 'unknown'}`;
      const group = groupedItems.get(key) ?? [];
      group.push(item);
      groupedItems.set(key, group);
    }

    for (const [, items] of groupedItems) {
      const firstItem = items[0];
      const supplierId = firstItem.supplier_id as string | null;
      const branchId = firstItem.branch_id as string | null;

      // Zkontroluj, jestli neexistuje aktivní objednávka pro tohoto dodavatele
      if (supplierId) {
        const { data: existingOrder } = await admin
          .from('purchase_orders')
          .select('id')
          .eq('supplier_id', supplierId)
          .in('status', ['draft', 'sent', 'confirmed'])
          .maybeSingle();

        if (existingOrder) {
          console.log(`Active order exists for supplier ${supplierId}, skipping`);
          continue;
        }
      }

      // Vytvoř draft objednávku
      const orderItems = items.map((item) => {
        const currentStock = Number(item.stock ?? 0);
        const minStock = Number(item.min_stock ?? 0);
        const orderQuantity = Math.max(minStock * 2 - currentStock, minStock); // Objednej na 2× minimum

        return {
          inventory_id: item.id as string,
          name: item.name as string,
          sku: item.sku as string,
          quantity: orderQuantity,
          unit: item.unit as string,
          unit_price: Number(item.unit_price ?? 0),
          total_price: orderQuantity * Number(item.unit_price ?? 0),
        };
      });

      const totalAmount = orderItems.reduce((s, i) => s + i.total_price, 0);

      const { data: order, error: orderError } = await admin
        .from('purchase_orders')
        .insert({
          supplier_id: supplierId,
          branch_id: branchId,
          status: 'draft',
          items: orderItems,
          total_amount: totalAmount,
          note: `Automatická objednávka — ${items.length} položek pod minimem`,
        })
        .select('id')
        .single();

      if (orderError) {
        console.error('Purchase order creation error:', orderError);
        continue;
      }

      ordersCreated++;
      console.log(`Created purchase order ${order?.id} with ${orderItems.length} items`);
    }

    // Notifikuj admina
    if (ordersCreated > 0) {
      await admin.from('notification_log').insert({
        type: 'system',
        template: 'inventory_alert',
        recipient: Deno.env.get('ADMIN_EMAIL') ?? '',
        status: 'pending',
        metadata: {
          items_below_min: lowStockItems.length,
          orders_created: ordersCreated,
        },
      });
    }

    const response: InventoryCheckResponse = {
      success: true,
      items_below_min: lowStockItems.length,
      orders_created: ordersCreated,
    };
    return jsonResponse(response);
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('inventory-check error:', errorMessage);
    return errorResponse('Internal server error', 500);
  }
});
