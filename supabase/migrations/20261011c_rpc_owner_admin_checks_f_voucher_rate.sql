-- =============================================================================
-- 2026-10-11 BEZPEČNOST (část _f k 20261011c): validate_voucher_code
-- Host webu ji volá bez přihlášení (anon zůstává, 20261011d skupina H), ale byla
-- bez omezení: kód poukazu = 'MG' + 6 hex (16,7 mil.) a odpověď vrací hodnotu i
-- id, které bere create_web_booking → reálné hádání dárkových poukazů.
-- Nově limit NEPLATNÝCH pokusů (platný kód se nepočítá), mimo admin Velínu a
-- interní volání (cron / SQL bez PostgRESTu):
--   * klíč = přihlášený uživatel ('u:'+uid; appka za CGNAT operátora nesdílí
--     limit s cizími), jinak IP hosta (cf-connecting-ip → x-real-ip → 1.
--     x-forwarded-for z request.headers PostgRESTu; IPv6 po /64): max 10
--     neplatných / hod,
--   * veřejné edge proxy se service klíčem (public-api, mcp-server, AI agenti)
--     sdílí klíč 'svc': max 30 neplatných / hod,
--   * celý systém ≥ 200 neplatných za hodinu → do konce hodiny zablokované
--     všechny limitované dotazy (ochrana proti rotaci klíčů).
-- Při limitu stejný tvar odpovědi {valid:false, error} (web i appka ho berou
-- jako neplatný kód). Zápis pokusu ve vlastním sub-bloku: chyba (např.
-- read-only GET) ověření neshodí.
-- Tělo = živá definice, měněno jen označené „2026-10-11“. Idempotentní.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.voucher_code_attempts (
  ip           text        NOT NULL,
  window_start timestamptz NOT NULL,
  misses       integer     NOT NULL DEFAULT 0,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ip, window_start)
);
CREATE INDEX IF NOT EXISTS idx_voucher_code_attempts_window
  ON public.voucher_code_attempts (window_start);
ALTER TABLE public.voucher_code_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.voucher_code_attempts FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.voucher_code_attempts TO service_role;
COMMENT ON TABLE public.voucher_code_attempts IS
  '2026-10-11: neplatné pokusy validate_voucher_code po klíči (IP hosta / u:uid) a hodině — limit hádání poukazů. Zapisuje jen ta funkce; RLS bez politik.';

CREATE OR REPLACE FUNCTION public.validate_voucher_code(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_voucher vouchers%ROWTYPE;
  -- 2026-10-11: limit neplatných pokusů (mimo admin Velínu / interní volání)
  v_role    text := coalesce(nullif(current_setting('role', true), ''), 'none');
  v_limited boolean := CASE v_role
                         WHEN 'anon'          THEN true
                         WHEN 'authenticated' THEN NOT public.is_admin()
                         WHEN 'service_role'  THEN true
                         ELSE session_user::text = 'authenticator'
                       END;
  v_win     timestamptz := date_trunc('hour', now());
  v_key     text;   -- IP hosta nebo u:<uid>
  v_hdr     json;
  v_key_miss integer := 0;
  v_all_miss integer := 0;
  v_cap     integer;
  v_err     text;
BEGIN
  IF v_limited THEN
    BEGIN
      v_hdr := nullif(current_setting('request.headers', true), '')::json;
      v_key := coalesce(nullif(btrim(v_hdr->>'cf-connecting-ip'), ''),
                       nullif(btrim(v_hdr->>'x-real-ip'), ''),
                       nullif(btrim(split_part(v_hdr->>'x-forwarded-for', ',', 1)), ''));
    EXCEPTION WHEN OTHERS THEN v_key := NULL;
    END;
    IF v_key LIKE '%:%' THEN   -- IPv6 → /64 (rotace adres v jednom bloku)
      v_key := array_to_string((string_to_array(v_key, ':'))[1:4], ':') || '::/64';
    END IF;
    v_key := CASE WHEN v_role = 'service_role' THEN 'svc'
                  WHEN auth.uid() IS NOT NULL THEN 'u:' || auth.uid()::text
                  ELSE left(coalesce(v_key, 'unknown'), 64) END;
    SELECT coalesce(sum(a.misses) FILTER (WHERE a.ip = v_key), 0), coalesce(sum(a.misses), 0)
      INTO v_key_miss, v_all_miss
      FROM voucher_code_attempts a WHERE a.window_start = v_win;
    v_cap := CASE WHEN v_key = 'svc' THEN 30 ELSE 10 END;
    IF v_key_miss >= v_cap OR v_all_miss >= 200 THEN
      RETURN jsonb_build_object('valid', false, 'rate_limited', true,
        'error', 'Příliš mnoho neplatných pokusů — zkuste to prosím později.');
    END IF;
  END IF;

  SELECT * INTO v_voucher FROM vouchers
    WHERE code = upper(p_code) AND status = 'active';

  -- 2026-10-11: neplatné výsledky přes v_err (kvůli záznamu pokusu)
  IF NOT FOUND THEN
    v_err := 'Poukaz neexistuje nebo není aktivní';
  ELSIF v_voucher.valid_from IS NOT NULL AND v_voucher.valid_from > CURRENT_DATE THEN
    v_err := 'Poukaz ještě není platný';
  ELSIF v_voucher.valid_until IS NOT NULL AND v_voucher.valid_until < CURRENT_DATE THEN
    v_err := 'Poukaz vypršel';
  END IF;

  IF v_err IS NOT NULL THEN
    IF v_limited THEN
      BEGIN
        INSERT INTO voucher_code_attempts AS a (ip, window_start, misses)
        VALUES (v_key, v_win, 1)
        ON CONFLICT (ip, window_start)
          DO UPDATE SET misses = a.misses + 1, updated_at = now();
        IF random() < 0.02 THEN
          DELETE FROM voucher_code_attempts WHERE window_start < now() - interval '2 days';
        END IF;
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
    RETURN jsonb_build_object('valid', false, 'error', v_err);
  END IF;

  RETURN jsonb_build_object(
    'valid', true,
    'id', v_voucher.id,
    'type', 'fixed',
    'value', v_voucher.amount,
    'code', v_voucher.code
  );
END;
$function$;
