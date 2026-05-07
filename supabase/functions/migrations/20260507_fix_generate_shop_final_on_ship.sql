-- =============================================================
-- Migration: Fix generate_shop_final_on_ship trigger
-- Date: 2026-05-07
-- =============================================================
-- ROOT CAUSE: Předchozí verze (20260321_fix_shop_invoice_triggers.sql)
-- referenovala neexistující sloupce na shop_orders (`total_amount`,
-- `currency`) i na invoices (`amount`, `currency`, `issued_at`) a INSERTovala
-- bez povinných NOT NULL sloupců (`number`, `issue_date`, `due_date`,
-- `subtotal`, `tax_amount`). Bez `EXCEPTION WHEN OTHERS` proto kaskáda
-- triggerů na shop_orders ronila celý UPDATE zpět — kliknutí „Zaplaceno"
-- ve Velíně u digitálního poukazu (status: new→delivered přes
-- auto_process_voucher_order) shodilo transakci a payment_status='paid'
-- se nikdy neuložil.
--
-- FIX: Místo raw INSERTu do invoices se trigger asynchronně dovolá
-- edge fn `generate-invoice` (stejnou, kterou už volá Velín
-- z ShopOrderModals.jsx::updateStatus). Edge fn si dohledá čísla,
-- splatnost a položky sama, je idempotentní (skipne když shop_final
-- už pro objednávku existuje). Přidán EXCEPTION handler, aby selhání
-- generování faktury nikdy neshodilo platbu / posun stavu.
-- =============================================================

CREATE OR REPLACE FUNCTION generate_shop_final_on_ship()
RETURNS TRIGGER AS $$
DECLARE
  v_url text;
  v_key text;
BEGIN
  IF NEW.status NOT IN ('shipped', 'delivered') THEN RETURN NEW; END IF;
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
  IF NEW.payment_status <> 'paid' THEN RETURN NEW; END IF;

  IF EXISTS (SELECT 1 FROM invoices WHERE order_id = NEW.id AND type = 'shop_final') THEN
    RETURN NEW;
  END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'generate_shop_final_on_ship: app_settings missing, skipping order %', NEW.id;
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/generate-invoice',
    headers := jsonb_build_object('Content-Type','application/json',
                                  'Authorization','Bearer ' || v_key),
    body    := jsonb_build_object('type','shop_final','order_id', NEW.id, 'send_email', false)
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'generate_shop_final_on_ship error for order %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger zůstává beze změny (AFTER UPDATE OF status, status IN shipped/delivered + status changed).
