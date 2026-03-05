-- ═══════════════════════════════════════════════════════
-- Status unification: confirmed → reserved, in_progress → in_service
-- ═══════════════════════════════════════════════════════

-- 1. Bookings: rename 'confirmed' status to 'reserved'
UPDATE bookings SET status = 'reserved' WHERE status = 'confirmed';

-- 2. Service orders: rename 'in_progress' to 'in_service'
UPDATE service_orders SET status = 'in_service' WHERE status = 'in_progress';

-- 3. Update service_orders CHECK constraint
ALTER TABLE service_orders DROP CONSTRAINT IF EXISTS service_orders_status_check;
ALTER TABLE service_orders ADD CONSTRAINT service_orders_status_check
  CHECK (status IN ('pending', 'in_service', 'completed', 'cancelled'));

-- 4. Email template: rename slug from booking_confirmed to booking_reserved
UPDATE email_templates SET slug = 'booking_reserved' WHERE slug = 'booking_confirmed';

-- 5. Add booking_completed email template (ride finished notification)
INSERT INTO email_templates (slug, name, subject, description, variables, body_html) VALUES
  (
    'booking_completed',
    'Dokončení jízdy',
    'Vaše jízda č. {{booking_number}} byla dokončena – děkujeme!',
    'Odesláno zákazníkovi po vrácení motorky a dokončení rezervace.',
    '["customer_name", "booking_number", "motorcycle", "start_date", "end_date", "total_price"]',
    '<h2>Děkujeme za jízdu, {{customer_name}}!</h2><p>Vaše rezervace č. <strong>{{booking_number}}</strong> motocyklu <strong>{{motorcycle}}</strong> byla úspěšně dokončena.</p><p>Termín: {{start_date}} – {{end_date}}</p><p>Celková cena: {{total_price}} Kč</p><p>Budeme se těšit na další jízdu!</p>'
  ),
  (
    'booking_modified',
    'Změna rezervace',
    'Vaše rezervace č. {{booking_number}} byla upravena',
    'Odesláno zákazníkovi při změně rezervace (nový termín, jiná motorka, doplatek).',
    '["customer_name", "booking_number", "motorcycle", "start_date", "end_date", "total_price", "price_difference"]',
    '<h2>Změna rezervace, {{customer_name}}</h2><p>Vaše rezervace č. <strong>{{booking_number}}</strong> byla upravena:</p><p>Motorka: <strong>{{motorcycle}}</strong></p><p>Nový termín: {{start_date}} – {{end_date}}</p><p>Celková cena: {{total_price}} Kč</p><p>Rozdíl: {{price_difference}} Kč</p>'
  )
ON CONFLICT (slug) DO NOTHING;
