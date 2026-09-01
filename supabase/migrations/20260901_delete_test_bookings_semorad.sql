-- =============================================================================
-- ÚKLID: smazání VŠECH testovacích rezervací Jiřího Semoráda
-- (semorad@nastrojarstvi.com — testovací rodinný účet)
--
-- Maže rezervace, kde user = profil semorad@nastrojarstvi.com (příp. profil se
-- jménem "Jiří Semorád") a zároveň `is_test IS TRUE` NEBO nesou seed marker
-- 'SEED-KALENDAR-2026-0910%' (testovací obsazenost kalendáře 9-10/2026 ze
-- seedu 20260820/20260821). REÁLNÉ rezervace účtu (is_test=false) zůstávají.
--
-- Seed vkládal POUZE řádky do `bookings` (žádné door codes, faktury, extras —
-- is_test rezervace jsou z těchto cest vyjmuté), takže se čeká čistý DELETE.
-- Pro jistotu se ale před smazáním dynamicky odklidí VŠECHNY řádky odkazující
-- na mazané rezervace přes FK bez CASCADE/SET NULL (vlastněné tabulky DELETE,
-- ostatní nullable vazby SET NULL) — migrace tak NIKDY nespadne na FK a
-- nezablokuje SQL autodeploy.
--
-- Idempotentní: opakovaný běh nenajde žádné rezervace a nic neudělá.
-- =============================================================================

DO $cleanup$
DECLARE
  v_users uuid[];
  v_ids   uuid[];
  r       record;
  v_cnt   int;
BEGIN
  SELECT array_agg(id) INTO v_users
  FROM profiles
  WHERE lower(email) = 'semorad@nastrojarstvi.com'
     OR lower(full_name) IN ('jiří semorád', 'jiri semorad');

  IF v_users IS NULL THEN
    RAISE NOTICE 'CLEANUP-SEMORAD: profil Jiřího Semoráda nenalezen — nic ke smazání.';
    RETURN;
  END IF;

  SELECT array_agg(id) INTO v_ids
  FROM bookings
  WHERE user_id = ANY (v_users)
    AND (is_test IS TRUE OR notes LIKE 'SEED-KALENDAR-2026-0910%');

  IF v_ids IS NULL THEN
    RAISE NOTICE 'CLEANUP-SEMORAD: žádné testovací rezervace — nic ke smazání.';
    RETURN;
  END IF;

  -- Dynamický úklid všech FK vazeb na bookings.id bez ON DELETE CASCADE/SET NULL:
  -- tabulky vlastněné rezervací se mažou, u ostatních se nullable vazba odpojí.
  FOR r IN
    SELECT c.conrelid::regclass AS tbl,
           a.attname            AS col,
           a.attnotnull         AS notnull
    FROM pg_constraint c
    JOIN unnest(c.conkey) AS k(attnum) ON true
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
    WHERE c.confrelid = 'public.bookings'::regclass
      AND c.contype = 'f'
      AND c.confdeltype NOT IN ('c', 'n', 'd')  -- cascade / set null / set default zvládne DB sama
  LOOP
    IF r.tbl::text IN ('booking_extras', 'booking_discounts', 'booking_cancellations',
                       'branch_door_codes', 'email_send_locks', 'booking_complaints')
       OR r.notnull
    THEN
      EXECUTE format('DELETE FROM %s WHERE %I = ANY($1)', r.tbl, r.col) USING v_ids;
      GET DIAGNOSTICS v_cnt = ROW_COUNT;
    ELSE
      EXECUTE format('UPDATE %s SET %I = NULL WHERE %I = ANY($1)', r.tbl, r.col, r.col) USING v_ids;
      GET DIAGNOSTICS v_cnt = ROW_COUNT;
    END IF;
    IF v_cnt > 0 THEN
      RAISE NOTICE 'CLEANUP-SEMORAD: %.% — odklizeno % závislých řádků.', r.tbl, r.col, v_cnt;
    END IF;
  END LOOP;

  DELETE FROM bookings WHERE id = ANY (v_ids);
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  RAISE NOTICE 'CLEANUP-SEMORAD: smazáno % testovacích rezervací Jiřího Semoráda.', v_cnt;
END $cleanup$;
