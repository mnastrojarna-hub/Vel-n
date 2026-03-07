-- Status unification: confirmed -> reserved, in_progress -> in_service

-- 1. Bookings: rename 'confirmed' status to 'reserved'
DO $$ BEGIN
  UPDATE bookings SET status = 'reserved' WHERE status = 'confirmed';
EXCEPTION WHEN others THEN
  RAISE NOTICE 'bookings: confirmed already migrated or not present';
END $$;

-- 2. Service orders: rename 'in_progress' to 'in_service'
DO $$ BEGIN
  UPDATE service_orders SET status = 'in_service' WHERE status = 'in_progress';
EXCEPTION WHEN others THEN
  RAISE NOTICE 'service_orders: in_progress already migrated or not present';
END $$;

-- 3. Update service_orders CHECK constraint
ALTER TABLE service_orders DROP CONSTRAINT IF EXISTS service_orders_status_check;
DO $$ BEGIN
  ALTER TABLE service_orders ADD CONSTRAINT service_orders_status_check
    CHECK (status IN ('pending', 'in_service', 'completed', 'cancelled'));
EXCEPTION WHEN others THEN
  RAISE NOTICE 'service_orders_status_check: skipped';
END $$;

-- 4. Email template: rename slug from booking_confirmed to booking_reserved
DO $$ BEGIN
  UPDATE email_templates SET slug = 'booking_reserved' WHERE slug = 'booking_confirmed';
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'email_templates not found, skipping';
END $$;

-- 5. Add booking_completed email template
DO $$ BEGIN
  INSERT INTO email_templates (slug, name, subject, description, variables, body_html) VALUES
    (
      'booking_completed',
      'Dokonceni jizdy',
      'Vase jizda c. {{booking_number}} byla dokoncena - dekujeme!',
      'Odeslano zakaznikovi po vraceni motorky a dokonceni rezervace.',
      '{"customer_name", "booking_number", "motorcycle", "start_date", "end_date", "total_price"}',
      '<h2>Dekujeme za jizdu, {{customer_name}}!</h2><p>Vase rezervace c. <strong>{{booking_number}}</strong> motocyklu <strong>{{motorcycle}}</strong> byla uspesne dokoncena.</p><p>Termin: {{start_date}} - {{end_date}}</p><p>Celkova cena: {{total_price}} Kc</p><p>Budeme se tesit na dalsi jizdu!</p>'
    ),
    (
      'booking_modified',
      'Zmena rezervace',
      'Vase rezervace c. {{booking_number}} byla upravena',
      'Odeslano zakaznikovi pri zmene rezervace (novy termin, jina motorka, doplatek).',
      '{"customer_name", "booking_number", "motorcycle", "start_date", "end_date", "total_price", "price_difference"}',
      '<h2>Zmena rezervace, {{customer_name}}</h2><p>Vase rezervace c. <strong>{{booking_number}}</strong> byla upravena:</p><p>Motorka: <strong>{{motorcycle}}</strong></p><p>Novy termin: {{start_date}} - {{end_date}}</p><p>Celkova cena: {{total_price}} Kc</p><p>Rozdil: {{price_difference}} Kc</p>'
    )
  ON CONFLICT (slug) DO NOTHING;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'email_templates not found, skipping';
END $$;
