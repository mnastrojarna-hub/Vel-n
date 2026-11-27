-- =============================================================================
-- 20261129d3_operator_legal_gdpr.sql
-- Změna provozovatele (6/9): Zásady ochrany osobních údajů (GDPR) – document_templates type = gdpr.
--
-- Zadání majitele 2026-11-27: provozovatelem je MotoGo24 s.r.o., IČO 29909864, sídlo Mezná 9,
-- 393 01 Mezná, zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích,
-- oddíl C, vložka 36876; účet 2303580494/2010 (Fio banka). Ve smlouvách „zastoupená jednatelem“
-- (bez jména). Datum účinnosti = den nasazení (pražský čas), ve tvaru dosavadního textu.
--
-- Mění se (živě verze 5):
--   1) správce osobních údajů: MotoGo24 s.r.o.;
--   2) IČO: 29909864;
--   3) sídlo: Mezná 9, 393 01 Mezná + zápis v obchodním rejstříku;
--   4) „Tento dokument je platný a účinný od 1. 8. 2026“ → den nasazení.
-- Nemění se: účely, doby uchování, zpracovatelé ani žádný jiný text. (Případnou větu o změně správce
-- pro stávající zákazníky doplní majitel / právník ve Velínu – není součástí této migrace.)
--
-- Jak: NOVÁ VERZE šablony (version + 1, stejně jako uložení ve Velínu → Dokumenty → Smluvní texty;
-- tabulka document_templates historii verzí nevede – dřívější znění zůstává jen v už vygenerovaných
-- dokumentech, které se nemažou). Mění se JEN uvedené pasáže, zbytek textu (podmínky, ceny, lhůty)
-- zůstává beze změny.
-- Bezpečnost: každá pasáž se nahradí jen tehdy, když je v textu v dosavadním znění ověřeném proti
-- živé DB 2026-11-27; co mezitím někdo upravil ve Velínu, se přeskočí s NOTICE. Zůstane-li v šabloně
-- po běhu dosavadní provozovatel, vypíše se WARNING (pak upravit ručně ve Velínu).
-- Zastaralé strojové překlady, které dosavadního provozovatele obsahují, se odstraní (nikde se
-- nezobrazují – nemají platný otisk; Velín → Dokumenty → „Přeložit chybějící a zastaralé“ je vytvoří
-- znovu z nové češtiny). Idempotentní (2. běh nic nezmění, verze se znovu nezvyšuje).
-- Bez BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================
-- Schváleno majitelem 2026-11-27.

DO $$
DECLARE
  t       record;
  r       record;
  l       text;
  v_new   text;
  cnt     integer;
  n_ch    integer;
  n_done  integer;
  n_skip  integer;
  n_tr    integer;
  -- den nasazení (Praha) ve tvaru „1. 8. 2026“
  v_date  constant text := to_char(now() AT TIME ZONE 'Europe/Prague', 'FMDD. FMMM. YYYY');
  c_reg   constant text := 'zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876';
  c_regs  constant text := 'C 36876 vedená u Krajského soudu v Českých Budějovicích';
  c_old   constant text := 'Semorádová|21874263|2225851630';   -- stopy dosavadního provozovatele
BEGIN
  FOR t IN
    SELECT id, type, version, content_html, content_translations
      FROM public.document_templates
     WHERE type = ANY (ARRAY['gdpr']) AND active
     ORDER BY type
     FOR UPDATE
  LOOP
    v_new := t.content_html; n_ch := 0; n_done := 0; n_skip := 0; n_tr := 0;
    -- how: 're' = regulární výraz, právě 1 výskyt · 'tx' = přesný text, právě 1 výskyt · 'all' = přesný text, všechny výskyty
    FOR r IN
      SELECT * FROM (VALUES
        ('gdpr', 1, 'tx', $o$<span style="font-size: medium;">Bc. Petra Semorádová</span>$o$,
          $n$<span style="font-size: medium;">MotoGo24 s.r.o.</span>$n$,
          'správce – název'),
        ('gdpr', 2, 'all', $o$IČO: 21874263$o$,
          $n$IČO: 29909864$n$,
          'správce – IČO'),
        ('gdpr', 3, 'tx', $o$Sídlo: Mezná 9, 393 01 Pelhřimov$o$,
          'Sídlo: Mezná 9, 393 01 Mezná; ' || c_reg,
          'správce – sídlo a zápis v rejstříku'),
        ('gdpr', 4, 'tx', $o$platný a účinný od 1. 8. 2026$o$,
          'platný a účinný od ' || v_date,
          'datum účinnosti')
      ) AS x(typ, ord, how, old, new, label)
      WHERE x.typ = t.type
      ORDER BY ord
    LOOP
      IF r.how = 're' THEN
        SELECT count(*) INTO cnt FROM regexp_matches(v_new, r.old, 'g');
      ELSE
        cnt := (length(v_new) - length(replace(v_new, r.old, ''))) / length(r.old);
      END IF;
      IF (r.how = 'all' AND cnt >= 1) OR cnt = 1 THEN
        v_new := CASE WHEN r.how = 're' THEN regexp_replace(v_new, r.old, r.new) ELSE replace(v_new, r.old, r.new) END;
        n_ch := n_ch + 1;
      ELSIF cnt = 0 AND strpos(v_new, r.new) > 0 THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE '%: pasáž „%“ nenalezena v dosavadním znění (výskytů %) – přeskočeno', t.type, r.label, cnt;
      END IF;
    END LOOP;

    IF v_new IS DISTINCT FROM t.content_html THEN
      UPDATE public.document_templates
         SET content_html = v_new, version = coalesce(version, 1) + 1, updated_at = now()
       WHERE id = t.id;
    END IF;

    -- zastaralé překlady s dosavadním provozovatelem (bez platného otisku aktuální češtiny)
    FOR l IN SELECT k FROM jsonb_object_keys(coalesce(t.content_translations, '{}'::jsonb)) AS k LOOP
      UPDATE public.document_templates
         SET content_translations = content_translations - l, translation_src = translation_src - l
       WHERE id = t.id
         AND (content_translations ->> l) ~ c_old
         AND (translation_src ->> l) IS DISTINCT FROM encode(extensions.digest(convert_to(content_html, 'UTF8'), 'sha1'), 'hex');
      GET DIAGNOSTICS cnt = ROW_COUNT;
      n_tr := n_tr + cnt;
    END LOOP;

    RAISE NOTICE '%: pasáží změněno %, už hotovo %, přeskočeno %; nová verze: %; odstraněno zastaralých překladů: %',
      t.type, n_ch, n_done, n_skip,
      CASE WHEN v_new IS DISTINCT FROM t.content_html THEN (coalesce(t.version, 1) + 1)::text ELSE 'ne (beze změny)' END, n_tr;
    IF v_new ~ c_old THEN
      RAISE WARNING '%: v šabloně ZŮSTÁVÁ dosavadní provozovatel – upravte ručně (Velín → Dokumenty → Smluvní texty)', t.type;
    END IF;
  END LOOP;
END $$;
