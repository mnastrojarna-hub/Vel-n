-- ============================================================================
-- POBOČKA REZERVACE v2 — jednorázový přepočet historie (2026-10-11, po 20261011e)
-- 20261010b dal staré nedokončené / bez důkazu / s pozdějšími kódy dveří AKTUÁLNÍ
-- pobočku motorky (Mezná → Velké Němčice); 20261010h posunul i staré navazující.
-- Pobočka = kde byla motorka při PŘEVZETÍ (picked_up_at, ne artefakt cronu ↔ ne-auto
-- protokol; storno = min(storno, začátek); jinak začátek). První použitelný důkaz:
--   1 kiosk v okně převzetí, 2 protokol na kiosku, 3 protokol z Velína (adresa;
--   po 10b jen při převzetí), 4 GPS první jízdy ≤ 30 km (ne přistavení),
--   5/6 1. zalogovaný přesun PO převzetí (odkud) ↔ kód platný při převzetí (před
--   zalogováním přesunů kód první), 7 přesun PŘED (kam), 8 první kód,
--   9 soused (předchozí/následující rezervace motorky s důkazem, bez přesunu / kódu
--   jinde mezi), 10 jediná možná pobočka (jen když dnešní hodnota není věrohodná).
-- Bez důkazu = beze změny; NIKDY aktuální pobočka motorky.
-- Věrohodnost (3–10): ne před branches.created_at; samoobslužná (ne přistavení /
-- storno) ne před dnem 1. převzetí na jejím kiosku. 1. přesun / 1. kód jako
-- „otevření“ pobočky NE (přesuny před 29. 9. chybí, kódy Mezné začínají až s funkcí).
-- Přeskočeno: test, živé, ruční změna (booking_branch_set), už přepočtené, _bb_keep.
-- Navazující / SOS dědí původní. Změny → admin_audit_log 'booking_branch_reattributed'
-- {old, new, rule, migration 'branch_v2'}; vrácení = old_data.branch_id (s GUC
-- motogo.branch_reattribution). Výpočet jen čte; zámek bookings až při zápisu.
-- Stejné jádro dotazu má diagnostika (náhled změn). Opakování = no-op.
-- ============================================================================

DROP TABLE IF EXISTS pg_temp._bb_keep;
CREATE TEMP TABLE _bb_keep ON COMMIT DROP AS   -- ruční výjimky (id rezervací), jinak prázdné
SELECT unnest('{}'::uuid[]) AS id;

DROP TABLE IF EXISTS pg_temp._bbx;
CREATE TEMP TABLE _bbx ON COMMIT DROP AS
WITH ts AS (
  SELECT COALESCE((SELECT applied_at FROM public._git_migrations WHERE filename = '20260929h_moto_move_guards.sql'),
                  timestamptz '2026-09-30 00:00+00') AS log_from,
         COALESCE((SELECT applied_at FROM public._git_migrations WHERE filename = '20261010b_booking_branch_attribution.sql'),
                  timestamptz '2026-10-10 00:00+00') AS b10_at
),
br AS MATERIALIZED (
  SELECT x.id, x.name, COALESCE(x.type = 'samoobslužná', false) AS ss, x.created_at,
         regexp_replace(lower(translate(concat_ws(' ', x.address, x.zip, x.city), 'ÁÄČĎÉĚËÍŇÓÖŘŠŤÚŮÜÝŽáäčďéěëíňóöřšťúůüýž',
                                        'AACDEEEINOORSTUUUYZaacdeeeinoorstuuuyz')), '[^a-z0-9]+', '', 'g') AS k1,
         regexp_replace(lower(translate(concat_ws(' ', x.address, x.city), 'ÁÄČĎÉĚËÍŇÓÖŘŠŤÚŮÜÝŽáäčďéěëíňóöřšťúůüýž',
                                        'AACDEEEINOORSTUUUYZaacdeeeinoorstuuuyz')), '[^a-z0-9]+', '', 'g') AS k2
    FROM public.branches x
),
mv AS MATERIALIZED (   -- zalogované přesuny (RPC admin_move_motorcycle od 2026-09-29); audit + tachometr = stejná transakce → UNION
  SELECT a.entity_id AS moto_id, a.created_at AS at,
         CASE WHEN a.old_data->>'branch_id' ~* '^[0-9a-f-]{36}$' THEN (a.old_data->>'branch_id')::uuid END AS fr,
         CASE WHEN a.new_data->>'branch_id' ~* '^[0-9a-f-]{36}$' THEN (a.new_data->>'branch_id')::uuid END AS too
    FROM public.admin_audit_log a
   WHERE a.action = 'motorcycle_migrated' AND a.old_data ? 'branch_id' AND a.entity_id IS NOT NULL
  UNION
  SELECT r.moto_id, r.recorded_at, r.branch_id, r.to_branch_id FROM public.moto_odometer_readings r WHERE r.kind = 'transfer'
),
mvm AS MATERIALIZED (
  SELECT moto_id, array_agg(at ORDER BY at, fr, too) AS t, array_agg(fr ORDER BY at, fr, too) AS fr,
         array_agg(too ORDER BY at, fr, too) AS too FROM mv GROUP BY moto_id
),
dc AS MATERIALIZED (   -- kódy dveří; t_eff = od kdy řádek platí na své pobočce (přepis na místě přesunem od 20261005e)
  SELECT c.booking_id, c.branch_id, COALESCE(c.moto_id, k.moto_id) AS moto_id,
         COALESCE((SELECT max(u.t) FROM mvm, unnest(mvm.t, mvm.too) u(t, too)
                    WHERE mvm.moto_id = COALESCE(c.moto_id, k.moto_id) AND u.too = c.branch_id
                      AND u.t > c.created_at AND u.t <= c.updated_at + interval '1 minute'), c.created_at) AS t_eff
    FROM public.branch_door_codes c JOIN public.bookings k ON k.id = c.booking_id
),
dcb AS (SELECT booking_id, array_agg(branch_id ORDER BY t_eff, branch_id) AS br, array_agg(t_eff ORDER BY t_eff, branch_id) AS t
          FROM dc GROUP BY booking_id),
dcm AS (SELECT moto_id, array_agg(branch_id ORDER BY t_eff, branch_id) AS br, array_agg(t_eff ORDER BY t_eff, branch_id) AS t
          FROM dc WHERE moto_id IS NOT NULL GROUP BY moto_id),
ke AS MATERIALIZED (   -- kiosk: úspěšné otevření kódem rezervace (ne krátkodobý / nouzový / fáze vrácení)
  SELECT e.booking_id, e.branch_id, e.created_at FROM public.branch_door_events e
   WHERE e.success IS TRUE AND e.branch_id IS NOT NULL AND e.booking_id IS NOT NULL
     AND e.kind IN ('motorcycle', 'accessories') AND COALESCE(e.detail->>'temp', '') <> 'true'
     AND COALESCE(e.detail->>'emergency', '') <> 'true' AND COALESCE(e.detail->>'odometer_phase', '') <> 'in'
),
keb AS (SELECT booking_id, array_agg(branch_id ORDER BY created_at, branch_id) AS br, array_agg(created_at ORDER BY created_at, branch_id) AS t
          FROM ke GROUP BY booking_id),
kpb AS MATERIALIZED (   -- protokol podepsaný na kiosku → pobočka zařízení
  SELECT DISTINCT ON (g.booking_id) g.booking_id, kd.branch_id, g.created_at FROM public.generated_documents g
    JOIN public.kiosk_devices kd ON kd.id::text = g.filled_data->>'_device_id'
   WHERE g.booking_id IS NOT NULL AND g.filled_data->>'_doc_type' = 'handover_protocol'
   ORDER BY g.booking_id, g.created_at
),
vpb AS MATERIALIZED (   -- protokol z Velína: místo převzetí = adresa pobočky (normalizovaně, s/bez PSČ)
  SELECT g.booking_id, array_agg(x.id ORDER BY g.created_at, x.id) AS br, array_agg(g.created_at ORDER BY g.created_at, x.id) AS t
    FROM public.generated_documents g
    JOIN br x ON regexp_replace(lower(translate(g.filled_data->>'pickup_location', 'ÁÄČĎÉĚËÍŇÓÖŘŠŤÚŮÜÝŽáäčďéěëíňóöřšťúůüýž',
                                'AACDEEEINOORSTUUUYZaacdeeeinoorstuuuyz')), '[^a-z0-9]+', '', 'g') IN (x.k1, x.k2)
   WHERE g.booking_id IS NOT NULL AND g.filled_data->>'_doc_type' = 'handover_protocol' AND g.filled_data->>'_device_id' IS NULL
   GROUP BY g.booking_id
),
rdb AS (   -- jízdy v appce: nejbližší pobočka ≤ 30 km od startu (NULL = dál)
  SELECT u.booking_id, array_agg(n.id ORDER BY u.started_at, u.id) AS br, array_agg(u.started_at ORDER BY u.started_at, u.id) AS t
    FROM public.user_rides u
    LEFT JOIN LATERAL (
      SELECT z.id FROM (SELECT y.id, sqrt(power((u.start_lng - y.gps_lng::float8) * cos(radians(u.start_lat)) * 111.32, 2)
                                          + power((u.start_lat - y.gps_lat::float8) * 110.57, 2)) AS km
                          FROM public.branches y WHERE y.gps_lat IS NOT NULL AND y.gps_lng IS NOT NULL) z
       WHERE z.km <= 30 ORDER BY z.km, z.id LIMIT 1) n ON true
   WHERE u.booking_id IS NOT NULL AND u.start_lat IS NOT NULL AND u.start_lng IS NOT NULL
   GROUP BY u.booking_id
),
bx AS MATERIALIZED (   -- první převzetí na kiosku pobočky (nezkušební rezervace); pobočka má vůbec stopu motorky
  SELECT br.id, br.ss, br.created_at,
         LEAST((SELECT min(ke.created_at) FROM ke JOIN public.bookings t ON t.id = ke.booking_id AND t.is_test IS NOT TRUE
                 WHERE ke.branch_id = br.id),
               (SELECT min(kpb.created_at) FROM kpb JOIN public.bookings t ON t.id = kpb.booking_id AND t.is_test IS NOT TRUE
                 WHERE kpb.branch_id = br.id)) AS k_first,
         (EXISTS (SELECT 1 FROM public.branch_door_codes c WHERE c.branch_id = br.id)
          OR EXISTS (SELECT 1 FROM ke WHERE ke.branch_id = br.id) OR EXISTS (SELECT 1 FROM vpb WHERE br.id = ANY (vpb.br))
          OR EXISTS (SELECT 1 FROM mv WHERE br.id IN (mv.fr, mv.too))
          OR EXISTS (SELECT 1 FROM public.motorcycles m WHERE m.branch_id = br.id)) AS used
    FROM br
),
b AS (
  SELECT bk.id, bk.moto_id, bk.branch_id, bk.status, bk.start_date, bk.end_date, bk.picked_up_at, bk.updated_at,
         bk.total_price, bk.booking_source,
         COALESCE(bk.extends_booking_id, CASE WHEN bk.sos_replacement IS TRUE THEN bk.replacement_for_booking_id END) AS parent,
         NOT EXISTS (SELECT 1 FROM public.bookings p WHERE p.id <> bk.id AND p.is_test IS NOT TRUE AND p.id =
           COALESCE(bk.extends_booking_id, CASE WHEN bk.sos_replacement IS TRUE THEN bk.replacement_for_booking_id END)) AS root,
         (COALESCE(bk.pickup_method, '') = 'delivery' OR COALESCE(btrim(bk.pickup_address), '') <> '') AS deliv,
         (bk.picked_up_at IS NOT NULL
          AND ((bk.picked_up_at AT TIME ZONE 'Europe/Prague')::date > (bk.end_date AT TIME ZONE 'Europe/Prague')::date
               OR (bk.handover_protocol_autofilled IS TRUE AND bk.handover_protocol_filled_at IS NOT NULL
                   AND abs(extract(epoch FROM bk.picked_up_at - bk.handover_protocol_filled_at)) <= 120))) AS pk_art,
         COALESCE(LEAST(
           CASE WHEN (bk.picked_up_at AT TIME ZONE 'Europe/Prague')::date <= (bk.end_date AT TIME ZONE 'Europe/Prague')::date
                 AND NOT (bk.handover_protocol_autofilled IS TRUE AND bk.handover_protocol_filled_at IS NOT NULL
                          AND abs(extract(epoch FROM bk.picked_up_at - bk.handover_protocol_filled_at)) <= 120)
                THEN bk.picked_up_at END,
           CASE WHEN bk.handover_protocol_autofilled IS NOT TRUE
                 AND (bk.handover_protocol_filled_at AT TIME ZONE 'Europe/Prague')::date <= (bk.end_date AT TIME ZONE 'Europe/Prague')::date
                THEN bk.handover_protocol_filled_at END),
           CASE WHEN bk.status = 'cancelled' THEN LEAST(COALESCE(bk.cancelled_at, bk.start_date), bk.start_date) END,
           bk.start_date) AS t_pick,
         GREATEST(bk.end_date, COALESCE(bk.returned_at, bk.end_date)) + interval '2 days' AS t_win_end,
         COALESCE(bk.status IN ('pending', 'reserved') AND bk.picked_up_at IS NULL AND bk.handover_protocol_filled_at IS NULL
                  AND (now() AT TIME ZONE 'Europe/Prague')::date <= (bk.start_date AT TIME ZONE 'Europe/Prague')::date, false) AS live,
         EXISTS (SELECT 1 FROM public.admin_audit_log a WHERE a.entity_type = 'bookings' AND a.entity_id = bk.id
                    AND a.action = 'booking_branch_set') AS expl
    FROM public.bookings bk WHERE bk.is_test IS NOT TRUE
),
b2 AS (   -- věrohodné pobočky: ne před created_at; samoobslužná (ne přistavení/storno) ne před dnem 1. převzetí na kiosku
  SELECT b.*, ARRAY(SELECT bx.id FROM bx
                     WHERE (bx.created_at IS NULL OR (bx.created_at AT TIME ZONE 'Europe/Prague')::date <= (b.t_pick AT TIME ZONE 'Europe/Prague')::date)
                       AND NOT (bx.ss AND NOT b.deliv AND b.status IS DISTINCT FROM 'cancelled'
                                AND (bx.k_first IS NULL OR (b.t_pick AT TIME ZONE 'Europe/Prague')::date < (bx.k_first AT TIME ZONE 'Europe/Prague')::date))
                     ORDER BY bx.id) AS ok
    FROM b
),
calc AS (
  SELECT b.*, x.*, s.sug, s.rule
    FROM b2 b CROSS JOIN ts
    LEFT JOIN keb ON keb.booking_id = b.id LEFT JOIN kpb ON kpb.booking_id = b.id
    LEFT JOIN vpb ON vpb.booking_id = b.id LEFT JOIN rdb ON rdb.booking_id = b.id
    LEFT JOIN dcb ON dcb.booking_id = b.id LEFT JOIN mvm ON mvm.moto_id = b.moto_id
    CROSS JOIN LATERAL (
      SELECT
        (SELECT u.br FROM unnest(keb.br, keb.t) u(br, t)
          WHERE u.t BETWEEN b.start_date - interval '2 days' AND LEAST(b.t_win_end, GREATEST(b.t_pick, b.start_date) + interval '1 day')
          ORDER BY u.t, u.br LIMIT 1) AS ev,
        (SELECT min(u.t) FROM unnest(keb.t) u(t)
          WHERE u.t BETWEEN b.start_date - interval '2 days' AND LEAST(b.t_win_end, GREATEST(b.t_pick, b.start_date) + interval '1 day')) AS ev_at,
        kpb.branch_id AS kp1,
        (SELECT u.br FROM unnest(vpb.br, vpb.t) u(br, t)
          WHERE u.t <= CASE WHEN u.t < ts.b10_at THEN b.t_win_end ELSE GREATEST(b.t_pick, b.start_date) + interval '1 day' END
          ORDER BY u.t, u.br LIMIT 1) AS vp1,
        CASE WHEN NOT b.deliv THEN
          (SELECT u.br FROM unnest(rdb.br, rdb.t) u(br, t)   -- jen PRVNÍ jízda v okně převzetí
            WHERE u.t BETWEEN b.start_date - interval '1 day' AND GREATEST(b.t_pick, b.start_date) + interval '1 day'
            ORDER BY u.t LIMIT 1) END AS rd,
        (SELECT u.fr FROM unnest(mvm.t, mvm.fr) u(t, fr) WHERE u.t > b.t_pick ORDER BY u.t, u.fr LIMIT 1) AS ma_fr,
        (SELECT min(u.t) FROM unnest(mvm.t) u(t) WHERE u.t > b.t_pick) AS ma_at,
        (SELECT u.br FROM unnest(dcb.br, dcb.t) u(br, t) WHERE u.t <= b.t_pick + interval '1 hour'
          ORDER BY u.t DESC, u.br LIMIT 1) AS dcp,
        (SELECT u.too FROM unnest(mvm.t, mvm.too) u(t, too) WHERE u.t <= b.t_pick ORDER BY u.t DESC, u.too LIMIT 1) AS mb_to,
        dcb.br[1] AS dcf
    ) x
    LEFT JOIN LATERAL (
      SELECT v.br AS sug, v.rule FROM (VALUES
          (1, x.ev, 'kiosk'), (2, x.kp1, 'kiosk_protocol'), (3, x.vp1, 'velin_protocol'), (4, x.rd, 'ride_gps'),
          (5, CASE WHEN b.t_pick >= ts.log_from THEN x.ma_fr ELSE x.dcp END,
              CASE WHEN b.t_pick >= ts.log_from THEN 'move_after' ELSE 'codes_at_pickup' END),
          (6, CASE WHEN b.t_pick >= ts.log_from THEN x.dcp ELSE x.ma_fr END,
              CASE WHEN b.t_pick >= ts.log_from THEN 'codes_at_pickup' ELSE 'move_after' END),
          (7, x.mb_to, 'move_before'), (8, x.dcf, 'codes_first')) v(o, br, rule)
       WHERE v.br IS NOT NULL AND (v.o <= 2 OR v.br = ANY (b.ok))
       ORDER BY v.o LIMIT 1) s ON true
),
km AS (   -- rezervace s vlastním důkazem (nebo ruční změnou) po motorkách → soused
  SELECT c.moto_id, array_agg(c.id ORDER BY c.t_pick, c.id) AS id, array_agg(c.t_pick ORDER BY c.t_pick, c.id) AS t,
         array_agg(CASE WHEN c.expl THEN c.branch_id ELSE c.sug END ORDER BY c.t_pick, c.id) AS br
    FROM calc c WHERE c.root AND NOT c.live AND c.moto_id IS NOT NULL AND (CASE WHEN c.expl THEN c.branch_id ELSE c.sug END) IS NOT NULL
   GROUP BY c.moto_id
),
nb AS (   -- soused = bezprostředně předchozí / následující taková rezervace téže motorky, mezi nimi žádný přesun ani kód jinde
  SELECT c.id,
         (SELECT k.br FROM ((SELECT * FROM unnest(km.id, km.t, km.br) k(id, t, br) WHERE k.id <> c.id AND k.t <= c.t_pick
                             ORDER BY k.t DESC, k.id LIMIT 1)
                            UNION ALL
                            (SELECT * FROM unnest(km.id, km.t, km.br) k(id, t, br) WHERE k.id <> c.id AND k.t > c.t_pick
                             ORDER BY k.t, k.id LIMIT 1)) k
           WHERE k.br = ANY (c.ok)
             AND NOT EXISTS (SELECT 1 FROM unnest(mvm.t) m(t) WHERE m.t BETWEEN LEAST(k.t, c.t_pick) AND GREATEST(k.t, c.t_pick))
             AND NOT EXISTS (SELECT 1 FROM unnest(dcm.t, dcm.br) d(t, br)
                              WHERE d.br <> k.br AND d.t BETWEEN LEAST(k.t, c.t_pick) AND GREATEST(k.t, c.t_pick))
           ORDER BY abs(extract(epoch FROM k.t - c.t_pick)), k.id LIMIT 1) AS br
    FROM calc c JOIN km ON km.moto_id = c.moto_id
    LEFT JOIN mvm ON mvm.moto_id = c.moto_id LEFT JOIN dcm ON dcm.moto_id = c.moto_id
   WHERE c.root AND NOT c.live AND c.sug IS NULL
),
res AS (   -- rozhodnutí pro kořenové rezervace (bez navazujících)
  SELECT c.id, c.branch_id AS old_branch, c.expl,
         COALESCE(c.sug, nb.br, el.br) AS new_branch,
         CASE WHEN c.sug IS NOT NULL THEN c.rule WHEN nb.br IS NOT NULL THEN 'neighbor'
              WHEN el.br IS NOT NULL THEN 'only_possible' END AS rule
    FROM calc c LEFT JOIN nb ON nb.id = c.id
    LEFT JOIN LATERAL (   -- jediná možná: jen když dnešní hodnota není věrohodná
      SELECT (SELECT min(u::text)::uuid FROM unnest(c.ok) u JOIN bx ON bx.id = u AND bx.used HAVING count(*) = 1) AS br
       WHERE c.sug IS NULL AND nb.br IS NULL AND (c.branch_id IS NULL OR NOT (c.branch_id = ANY (c.ok)))) el ON true
   WHERE c.root AND NOT c.live
)
SELECT id, old_branch, expl, new_branch, rule FROM res;

-- zápis: bez bumpu updated_at a bez debug_log mailového triggeru
SELECT set_config('motogo.branch_reattribution', 'branch_v2', true);
ALTER TABLE public.bookings DISABLE TRIGGER bookings_updated_at;
ALTER TABLE public.bookings DISABLE TRIGGER trg_booking_modified_email;

WITH upd AS (
  UPDATE public.bookings bk
     SET branch_id = s.new_branch
    FROM _bbx s
   WHERE bk.id = s.id AND s.new_branch IS NOT NULL AND NOT s.expl
     AND s.new_branch IS DISTINCT FROM s.old_branch
     AND bk.branch_id IS NOT DISTINCT FROM s.old_branch
     AND NOT EXISTS (SELECT 1 FROM _bb_keep k WHERE k.id = bk.id)
     AND NOT EXISTS (SELECT 1 FROM public.admin_audit_log a
                      WHERE a.entity_type = 'bookings' AND a.entity_id = bk.id
                        AND a.action = 'booking_branch_reattributed' AND a.new_data->>'migration' = 'branch_v2')
     AND EXISTS (SELECT 1 FROM public.branches x WHERE x.id = s.new_branch)
  RETURNING bk.id, s.old_branch, s.new_branch, s.rule
)
INSERT INTO public.admin_audit_log(admin_id, action, entity_type, entity_id, old_data, new_data)
SELECT NULL, 'booking_branch_reattributed', 'bookings', u.id, jsonb_build_object('branch_id', u.old_branch),
       jsonb_build_object('branch_id', u.new_branch, 'rule', u.rule, 'migration', 'branch_v2')
  FROM upd u;

-- Navazující / SOS náhrady (i ty, které 20261010h přesunul): pobočka původní (řetězy → více průchodů).
DO $$
BEGIN
  FOR i IN 1..5 LOOP
    WITH upd AS (
      UPDATE public.bookings c
         SET branch_id = p.branch_id
        FROM public.bookings p, (SELECT id, branch_id FROM public.bookings) o
       WHERE p.id = COALESCE(c.extends_booking_id, CASE WHEN c.sos_replacement IS TRUE THEN c.replacement_for_booking_id END)
         AND o.id = c.id AND p.id <> c.id AND p.branch_id IS NOT NULL AND c.branch_id IS DISTINCT FROM p.branch_id
         AND c.is_test IS NOT TRUE AND p.is_test IS NOT TRUE
         AND NOT public._booking_branch_follows(c.status, c.picked_up_at, c.handover_protocol_filled_at, c.start_date)
         AND NOT EXISTS (SELECT 1 FROM _bb_keep k WHERE k.id = c.id)
         AND NOT EXISTS (SELECT 1 FROM public.admin_audit_log a
                          WHERE a.entity_type = 'bookings' AND a.entity_id = c.id AND a.action = 'booking_branch_set')
      RETURNING c.id, o.branch_id AS old_br, p.branch_id AS new_br
    )
    INSERT INTO public.admin_audit_log(admin_id, action, entity_type, entity_id, old_data, new_data)
    SELECT NULL, 'booking_branch_reattributed', 'bookings', u.id, jsonb_build_object('branch_id', u.old_br),
           jsonb_build_object('branch_id', u.new_br, 'rule', 'inherit', 'migration', 'branch_v2')
      FROM upd u;
    EXIT WHEN NOT FOUND;
  END LOOP;
END $$;

ALTER TABLE public.bookings ENABLE TRIGGER trg_booking_modified_email;
ALTER TABLE public.bookings ENABLE TRIGGER bookings_updated_at;
SELECT set_config('motogo.branch_reattribution', '', true);
