-- =============================================================================
-- „Dostupné dnes" lhalo u zavřené pobočky — get_motos_availability_status
-- o zavírání pobočky (ani o vozíkových blokacích) nevěděla
-- Migrace: 20260921_moto_availability_respects_branch_closure.sql
--   (navazuje na 20260920d_branch_closures.sql)
--
-- NÁLEZ 2026-09-21 (ověřeno na ŽIVÉ DB): `get_motos_availability_status()`
-- vracela pro KTM SX 50 stojící na TRVALE ZAVŘENÉ pobočce Pohořelice
-- `next_available_date = 2026-09-21` (= dnes). Web z této RPC skládá odznak
-- na kartě motorky v katalogu (`components.php#renderMotoCard`): prázdné/dnešní
-- datum = „Dostupné dnes". Kus na zavřené pobočce (a po zavedení sezónních
-- období KAŽDÝ kus pobočky zavřené od–do, protože ta zůstává na webu vidět)
-- se tak zákazníkovi hlásil jako volný, i když ho rezervovat nelze.
--
-- PŘÍČINA: funkce si obsazenost počítala vlastním dotazem nad `bookings` —
-- neznala tedy ani zavírání pobočky, ani servisní bloky, ani kusy přiřazené
-- jako vozík k cizí rezervaci. Jediný zdroj pravdy je `get_moto_booked_dates`
-- (rezervace + vozík + servis + `branch_closed`), takže ho nově používá i ona.
--
-- OPRAVA:
--   * `next_available_date` = první den od dneška, který NENÍ v žádném bloku
--     z `get_moto_booked_dates` (horizont 400 dní),
--   * funkce vrací řádek pro KAŽDOU motorku se statusem active/maintenance
--     (dřív jen pro některé) — volná dnes = dnešní datum,
--   * když v horizontu volný den NENÍ (typicky trvale zavřená pobočka),
--     vrací `next_available_date = NULL` a web podle toho odznak VYNECHÁ
--     (`supabase.php` k tomu doplní příznak `available_unknown`) — dřív by
--     prázdná hodnota znamenala „Dostupné dnes", tedy přesný opak pravdy.
--
-- Signatura i typ návratu beze změny (moto_id uuid, next_available_date date),
-- jediný konzument v repu je web `supabase.php#fetchMotos`. Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_motos_availability_status()
RETURNS TABLE (
  moto_id            uuid,
  next_available_date date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH mm AS (
    SELECT m.id
    FROM motorcycles m
    WHERE COALESCE(m.status, 'active') IN ('active', 'maintenance')
  ),
  blocked AS (
    -- Jeden dotaz na kus: rezervace + vozík + servis + zavřená pobočka.
    -- GREATEST() je pojistka proti obrácenému rozsahu ve špatných datech
    -- (daterange(start > end) by jinak shodil celou funkci).
    SELECT mm.id,
           COALESCE(
             array_agg(daterange(b.start_date, GREATEST(b.end_date, b.start_date), '[]'))
               FILTER (WHERE b.start_date IS NOT NULL),
             ARRAY[]::daterange[]
           ) AS ranges
    FROM mm
    LEFT JOIN LATERAL public.get_moto_booked_dates(mm.id) b ON true
    GROUP BY mm.id
  )
  SELECT
    blocked.id,
    (
      SELECT g.d::date
      FROM generate_series(CURRENT_DATE, CURRENT_DATE + 400, INTERVAL '1 day') AS g(d)
      WHERE NOT EXISTS (
        SELECT 1 FROM unnest(blocked.ranges) AS r
        WHERE r @> g.d::date
      )
      ORDER BY g.d
      LIMIT 1
    ) AS next_available_date
  FROM blocked;
$$;

COMMENT ON FUNCTION public.get_motos_availability_status() IS
  'Nejbližší volný den per motorka (web katalog — odznak na kartě). Obsazenost bere VÝHRADNĚ z get_moto_booked_dates (rezervace + vozík + servis + zavřená pobočka). NULL = v horizontu 400 dní volný den není (např. trvale zavřená pobočka) → web odznak nezobrazí.';

GRANT EXECUTE ON FUNCTION public.get_motos_availability_status() TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
