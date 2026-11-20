-- Obnova RPC get_user_pois() — v živé DB chybí (z 20260629_community_routes_pois.sql),
-- appka (Trasy → Místa, userPoisProvider) pak hlásí „Místa se nepodařilo načíst“.
-- Tělo beze změny proti 20260629; práva skupiny A dle 20261011d (jen přihlášení + server).
CREATE OR REPLACE FUNCTION public.get_user_pois()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', u.id, 'name', u.name, 'description', u.description,
    'lat', u.lat, 'lng', u.lng, 'image_url', u.image_url,
    'avg_rating',   (SELECT round(avg(rating)::numeric, 1) FROM poi_ratings r WHERE r.user_poi_id = u.id),
    'rating_count', (SELECT count(*) FROM poi_ratings r WHERE r.user_poi_id = u.id)
  ) ORDER BY u.created_at DESC), '[]'::jsonb)
  FROM public.user_pois u WHERE u.status = 'approved';
$$;

REVOKE ALL ON FUNCTION public.get_user_pois() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_pois() TO authenticated, service_role;
