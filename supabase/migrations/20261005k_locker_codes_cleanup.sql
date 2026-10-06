-- 2026-10-05: srovnání EXISTUJÍCÍCH nadcházejících rezervací s pravidlem „kód šatny jen při vybrané výbavě“
-- (20261005g). Jen rezervace, které ještě nezačaly vydávat výbavu: status reserved/active, ne test, šatna ještě
-- nezavřená (gear_collected_at NULL), protokol nepodepsaný (handover_protocol_filled_at NULL), motorka nepředaná
-- (picked_up_at NULL) a konec rezervace v budoucnu. Idempotentní: druhý běh nic nenajde.
--
-- 1) „Vlastní výbava“ + velikosti řidiče, které si zákazník SÁM doplnil později (poslední změna výbavy řidiče
--    v modification_history nastavila velikost a nezapnula vlastní výbavu; typicky web Upravit rezervaci →
--    Výbava u rezervace z appky) → zákazník výbavu chce: own_gear=false → trg_sync_locker_code vydá kód šatny
--    + zprávu „Kód šatny“ + mail.
-- 2) Ostatní „vlastní výbava“ + velikosti řidiče = předvyplněné starou appkou z profilu → velikosti řidiče NULL
--    (protokol je pak nenabízí jako převzaté; kód šatny se nemění — boty/spolujezdec ho drží dál).
-- 3) Web (booking_source 'web'): velikosti spolujezdce / bot BEZ zaplaceného řádku v booking_extras = předvyplněné
--    z profilu (web je do 2026-10-05 posílal i bez zaškrtnuté karty) → NULL; jen když je nikdo později neměnil
--    (modification_history). Protokol pak nenabízí nezaplacenou výbavu a úprava výbavy ji neúčtuje.
-- 4) own_gear=false bez vybrané výbavy (stará appka / Velín „Ne — půjčuje si“) s aktivním kódem šatny → kód šatny
--    zneplatnit (withheld 'Vlastní výbava' jako trg_sync_locker_code). Rezervace s own_gear NULL (web a starší
--    rezervace do 25. 9., kdy kód šatny dostal každý) se NEmění — web jim sliboval výběr velikosti na místě.
-- 5) Nárok na šatnu bez kódu šatny (zaplacené boty / spolujezdec bez velikosti — web „vyzkoušíte na místě“;
--    kód šatny nepřišel ani podle starého pravidla) → vydat: „prázdný“ UPDATE own_gear spustí trg_sync_locker_code
--    (kód + zpráva „Kód šatny“ + mail). Jen když kód šatny nikdy nebyl, nebo ho naposledy stáhla automatika
--    ('Vlastní výbava') — ručně zneplatněný kód z Velína se neobnovuje.
-- 6) Kdo měl před úklidem platný VYDANÝ kód šatny a po úklidu ho nemá (kroky 3 a 4) → zpráva v appce + push +
--    SMS/WA + mail s platnými kódy a vysvětlením (_door_codes_notify, p_bump).

DROP TABLE IF EXISTS pg_temp._k_live, pg_temp._k_had;
CREATE TEMP TABLE _k_live ON COMMIT DROP AS
  SELECT b.id FROM public.bookings b
   WHERE b.status IN ('reserved','active') AND b.is_test IS NOT TRUE
     AND b.gear_collected_at IS NULL AND b.handover_protocol_filled_at IS NULL
     AND b.picked_up_at IS NULL AND b.end_date >= now();
CREATE TEMP TABLE _k_had ON COMMIT DROP AS
  SELECT DISTINCT c.booking_id AS id FROM public.branch_door_codes c JOIN _k_live l ON l.id = c.booking_id
   WHERE c.code_type = 'accessories' AND c.is_active AND c.sent_to_customer;

-- 1)
WITH h AS (
  SELECT b.id,
         (SELECT t.e
            FROM jsonb_array_elements(CASE WHEN jsonb_typeof(b.modification_history) = 'array'
                                           THEN b.modification_history ELSE '[]'::jsonb END)
                 WITH ORDINALITY AS t(e, i)
           WHERE jsonb_typeof(t.e->'gear_changes') = 'object'
             AND t.e->'gear_changes' ?| ARRAY['helmet','jacket','pants','gloves','own_gear']
           ORDER BY t.i DESC LIMIT 1) AS last_e
    FROM public.bookings b JOIN _k_live l ON l.id = b.id
   WHERE b.own_gear IS TRUE
     AND coalesce(nullif(btrim(b.helmet_size),''), nullif(btrim(b.jacket_size),''),
                  nullif(btrim(b.pants_size),''),  nullif(btrim(b.gloves_size),'')) IS NOT NULL
)
UPDATE public.bookings b SET own_gear = false
  FROM h
 WHERE b.id = h.id AND h.last_e IS NOT NULL
   AND coalesce(h.last_e->'gear_changes'->'own_gear'->>'to', '') <> 'true'
   AND EXISTS (SELECT 1 FROM unnest(ARRAY['helmet','jacket','pants','gloves']) k
                WHERE nullif(btrim(h.last_e->'gear_changes'->k->>'to'), '') IS NOT NULL);

-- 2)
UPDATE public.bookings b
   SET helmet_size = NULL, jacket_size = NULL, pants_size = NULL, gloves_size = NULL
  FROM _k_live l
 WHERE l.id = b.id AND b.own_gear IS TRUE
   AND coalesce(nullif(btrim(b.helmet_size),''), nullif(btrim(b.jacket_size),''),
                nullif(btrim(b.pants_size),''),  nullif(btrim(b.gloves_size),'')) IS NOT NULL;

-- 3) názvy řádků jako _booking_extra_is_gear, rozdělené na boty / spolujezdce (cs/en/de/es/fr/nl/pl/uk)
WITH x AS (
  SELECT b.id,
         EXISTS (SELECT 1 FROM public.booking_extras e WHERE e.booking_id = b.id
                    AND (lower(e.name) ~ '(spolujez|passenger|beifahrer|passager|pasajero|passagier|pasażer)' OR e.name ~ '(пасажир|Пасажир)')
                    AND NOT (lower(e.name) ~ '(bot|boots|stiefel|laarzen|buty)' OR e.name ~ '(Взуття|взуття)')) AS paid_pass,
         EXISTS (SELECT 1 FROM public.booking_extras e WHERE e.booking_id = b.id
                    AND (lower(e.name) ~ '(bot|boots|stiefel|laarzen|buty)' OR e.name ~ '(Взуття|взуття)')
                    AND NOT (lower(e.name) ~ '(spolujez|passenger|beifahrer|passager|pasajero|passagier|pasażer)' OR e.name ~ '(пасажир|Пасажир)')) AS paid_boots,
         EXISTS (SELECT 1 FROM public.booking_extras e WHERE e.booking_id = b.id
                    AND (lower(e.name) ~ '(bot|boots|stiefel|laarzen|buty)' OR e.name ~ '(Взуття|взуття)')
                    AND (lower(e.name) ~ '(spolujez|passenger|beifahrer|passager|pasajero|passagier|pasażer)' OR e.name ~ '(пасажир|Пасажир)')) AS paid_pboots,
         (SELECT coalesce(jsonb_agg(DISTINCT k), '[]'::jsonb)
            FROM jsonb_array_elements(CASE WHEN jsonb_typeof(b.modification_history) = 'array'
                                           THEN b.modification_history ELSE '[]'::jsonb END) h,
                 jsonb_object_keys(CASE WHEN jsonb_typeof(h->'gear_changes') = 'object'
                                        THEN h->'gear_changes' ELSE '{}'::jsonb END) k) AS touched
    FROM public.bookings b JOIN _k_live l ON l.id = b.id
   WHERE b.booking_source = 'web'
)
UPDATE public.bookings b SET
  passenger_helmet_size = CASE WHEN NOT x.paid_pass AND NOT x.touched ?| ARRAY['passenger_helmet','passenger_jacket','passenger_pants','passenger_gloves']
                               THEN NULL ELSE b.passenger_helmet_size END,
  passenger_jacket_size = CASE WHEN NOT x.paid_pass AND NOT x.touched ?| ARRAY['passenger_helmet','passenger_jacket','passenger_pants','passenger_gloves']
                               THEN NULL ELSE b.passenger_jacket_size END,
  passenger_pants_size  = CASE WHEN NOT x.paid_pass AND NOT x.touched ?| ARRAY['passenger_helmet','passenger_jacket','passenger_pants','passenger_gloves']
                               THEN NULL ELSE b.passenger_pants_size END,
  passenger_gloves_size = CASE WHEN NOT x.paid_pass AND NOT x.touched ?| ARRAY['passenger_helmet','passenger_jacket','passenger_pants','passenger_gloves']
                               THEN NULL ELSE b.passenger_gloves_size END,
  boots_size            = CASE WHEN NOT x.paid_boots AND NOT x.touched ? 'boots' THEN NULL ELSE b.boots_size END,
  passenger_boots_size  = CASE WHEN NOT x.paid_pboots AND NOT x.touched ? 'passenger_boots' THEN NULL ELSE b.passenger_boots_size END
  FROM x
 WHERE b.id = x.id
   AND (   (NOT x.paid_pass AND NOT x.touched ?| ARRAY['passenger_helmet','passenger_jacket','passenger_pants','passenger_gloves']
            AND coalesce(nullif(btrim(b.passenger_helmet_size),''), nullif(btrim(b.passenger_jacket_size),''),
                         nullif(btrim(b.passenger_pants_size),''),  nullif(btrim(b.passenger_gloves_size),'')) IS NOT NULL)
        OR (NOT x.paid_boots AND NOT x.touched ? 'boots' AND nullif(btrim(b.boots_size),'') IS NOT NULL)
        OR (NOT x.paid_pboots AND NOT x.touched ? 'passenger_boots' AND nullif(btrim(b.passenger_boots_size),'') IS NOT NULL));

-- 4)
UPDATE public.branch_door_codes c SET is_active = false, withheld_reason = 'Vlastní výbava'
  FROM public.bookings b JOIN _k_live l ON l.id = b.id
 WHERE c.booking_id = b.id AND c.code_type = 'accessories' AND c.is_active
   AND b.own_gear IS FALSE AND NOT public._booking_needs_locker(b.id);

-- 5)
UPDATE public.bookings b SET own_gear = b.own_gear
  FROM _k_live l
 WHERE l.id = b.id AND public._booking_needs_locker(b.id)
   AND EXISTS (SELECT 1 FROM public.branch_door_codes m
                WHERE m.booking_id = b.id AND m.code_type = 'motorcycle' AND m.is_active)
   AND NOT EXISTS (SELECT 1 FROM public.branch_door_codes a
                    WHERE a.booking_id = b.id AND a.code_type = 'accessories' AND a.is_active)
   AND (NOT EXISTS (SELECT 1 FROM public.branch_door_codes a
                     WHERE a.booking_id = b.id AND a.code_type = 'accessories')
        OR (SELECT a.withheld_reason FROM public.branch_door_codes a
             WHERE a.booking_id = b.id AND a.code_type = 'accessories'
             ORDER BY a.updated_at DESC LIMIT 1) IS NOT DISTINCT FROM 'Vlastní výbava');

-- 6)
DO $$
DECLARE
  r record; v_n integer := 0;
BEGIN
  FOR r IN
    SELECT h.id FROM _k_had h
     WHERE NOT EXISTS (SELECT 1 FROM public.branch_door_codes c
                        WHERE c.booking_id = h.id AND c.code_type = 'accessories' AND c.is_active)
  LOOP
    BEGIN
      IF public._door_codes_notify(r.id, 'Přístupové kódy — bez šatny',
           'V rezervaci nemáte vybranou žádnou výbavu, kód šatny proto neplatí — k motorce ho nepotřebujete. '
           || 'Pokud výbavu chcete, doplňte velikosti v úpravě rezervace (aplikace nebo web) a kód šatny vám přijde. '
           || 'Platné kódy:', true) THEN
        v_n := v_n + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '20261005k: notify % failed: %', r.id, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE '20261005k: kód šatny bez výbavy stažen a oznámen u % rezervací; nově vydaný kód šatny (zaplacená výbava): %',
    v_n, (SELECT count(*) FROM public.branch_door_codes c JOIN _k_live l ON l.id = c.booking_id
           WHERE c.code_type = 'accessories' AND c.is_active AND c.created_at >= now() - interval '1 minute'
             AND c.booking_id NOT IN (SELECT id FROM _k_had));
END $$;
