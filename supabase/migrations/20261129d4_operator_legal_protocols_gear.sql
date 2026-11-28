-- =============================================================================
-- 20261129d4_operator_legal_protocols_gear.sql
-- Změna provozovatele (7/9): předávací protokol, protokol o poškození, smlouva o nájmu výbavy.
--
-- Zadání majitele 2026-11-27: provozovatelem je MotoGo24 s.r.o., IČO 29909864, sídlo Mezná 9,
-- 393 01 Mezná, zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích,
-- oddíl C, vložka 36876. Ve smlouvách „zastoupená jednatelem“ (bez jména).
--
-- Pravidlo (rozhodnutí 2026-11-27): provozovatel se do těchto tří dokumentů píše DOSLOVA, ne přes
-- proměnné {{company_name}} / {{company_ico}} / {{company_address}}. Už nainstalované verze aplikace
-- si totiž takové proměnné při zobrazení šablony doplňují z vlastních starých údajů – podepsaný
-- dokument by pak ukázal dosavadního provozovatele. Proměnné pro kontakty ({{company_phone}},
-- {{company_email}}, {{company_web}}), zákazníka a rezervaci zůstávají, jak jsou.
--
-- Mění se:
--   handover_protocol (živě verze 3): „Pronajímatel“, „Vystavil/a“ a „Předávající“ = MotoGo24 s.r.o.,
--     patička MotoGo24 s.r.o. · IČO: 29909864 · Mezná 9, 393 01 Mezná · C 36876 vedená u Krajského soudu…;
--   damage_protocol (verze 2): totéž – {{company_name}} / {{company_ico}} / {{company_address}} nahrazeny
--     doslovnými údaji, do patičky doplněn zápis v obchodním rejstříku;
--   gear_rental_contract (verze 1): blok „Pronajímatel“ = MotoGo24 s.r.o. / se sídlem Mezná 9, 393 01 Mezná /
--     IČO: 29909864 / zápis v obchodním rejstříku / zastoupená jednatelem (telefon a e-mail dál z proměnných),
--     řádek u podpisu a patička. Bankovní spojení se nedoplňuje (smlouva o výbavě ho neuvádí).
--
-- Jak: NOVÁ VERZE šablony (version + 1, stejně jako uložení ve Velínu → Dokumenty → Smluvní texty;
-- tabulka document_templates historii verzí nevede – dřívější znění zůstává jen v už vygenerovaných
-- dokumentech, které se nemažou). Mění se JEN uvedené pasáže, zbytek textu zůstává beze změny.
-- Bezpečnost: každá pasáž se nahradí jen tehdy, když je v textu v dosavadním znění ověřeném proti
-- živé DB 2026-11-27; co mezitím někdo upravil ve Velínu, se přeskočí s NOTICE. Zůstane-li v šabloně
-- dosavadní provozovatel nebo proměnná provozovatele, vypíše se WARNING (pak upravit ručně ve Velínu).
-- Překlady: zastaralé strojové překlady s dosavadním provozovatelem (předávací protokol, 7 jazyků) se
-- odstraní; v překladech protokolu o poškození se tytéž tři proměnné nahradí doslovnými údaji. Žádný
-- z nich se dnes nezobrazuje (nemají platný otisk) – Velín → Dokumenty → „Přeložit chybějící
-- a zastaralé“ je vytvoří znovu z nové češtiny. Idempotentní (2. běh nic nezmění, verze se nezvyšuje).
-- Bez BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================
-- Schváleno majitelem 2026-11-27.

DO $$
DECLARE
  t       record;
  r       record;
  l       text;
  v_new   text;
  v_tr    jsonb;
  v_one   text;
  cnt     integer;
  n_ch    integer;
  n_done  integer;
  n_skip  integer;
  n_del   integer;
  n_trv   integer;
  c_name  constant text := 'MotoGo24 s.r.o.';
  c_ico   constant text := '29909864';
  c_seat  constant text := 'Mezná 9, 393 01 Mezná';
  c_reg   constant text := 'zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876';
  c_regs  constant text := 'C 36876 vedená u Krajského soudu v Českých Budějovicích';
  -- patička dokumentů: MotoGo24 s.r.o. · IČO: 29909864 · Mezná 9, 393 01 Mezná · C 36876 vedená u …
  c_foot  constant text := c_name || ' · IČO: ' || c_ico || ' · ' || c_seat || ' · ' || c_regs;
  c_old   constant text := 'Semorádová|21874263|2225851630';                   -- stopy dosavadního provozovatele
  c_vars  constant text := '\{\{company_(name|ico|address)\}\}';               -- proměnné provozovatele (nesmí zůstat)
BEGIN
  FOR t IN
    SELECT id, type, version, content_html, content_translations, translation_src
      FROM public.document_templates
     WHERE type = ANY (ARRAY['handover_protocol', 'damage_protocol', 'gear_rental_contract']) AND active
     ORDER BY type
     FOR UPDATE
  LOOP
    v_new := t.content_html; n_ch := 0; n_done := 0; n_skip := 0; n_del := 0; n_trv := 0;
    -- how: 'tx' = přesný text, právě 1 výskyt · 'all' = přesný text, všechny výskyty
    FOR r IN
      SELECT * FROM (VALUES
        ('handover_protocol', 1, 'tx', $o$<td>MotoGo24, Bc. Petra Semorádová</td>$o$,
          '<td>' || c_name || '</td>', 'Pronajímatel'),
        ('handover_protocol', 2, 'tx', $o$<td>Bc. Petra Semorádová</td>$o$,
          '<td>' || c_name || '</td>', 'Vystavil/a'),
        ('handover_protocol', 3, 'tx', $o$Předávající<br>Bc. Petra Semorádová$o$,
          'Předávající<br>' || c_name, 'Předávající'),
        ('handover_protocol', 4, 'tx', $o$Bc. Petra Semorádová · IČO: 21874263 · Mezná 9, 393 01 Pelhřimov$o$,
          c_foot, 'patička'),
        ('damage_protocol', 1, 'tx', $o${{company_name}} · IČO: {{company_ico}} · {{company_address}} · info@motogo24.cz$o$,
          c_foot || ' · info@motogo24.cz', 'patička'),
        ('damage_protocol', 2, 'all', $o${{company_name}}$o$,
          c_name, 'Pronajímatel / Vystavil/a / podpis pronajímatele'),
        ('gear_rental_contract', 1, 'tx', $o$<strong>Pronajímatel</strong><br>{{company_name}}<br>{{company_address}}<br>IČO: {{company_ico}}<br>Telefon: {{company_phone}}$o$,
          '<strong>Pronajímatel</strong><br>' || c_name || '<br>se sídlem ' || c_seat || '<br>IČO: ' || c_ico || '<br>' || c_reg || '<br>zastoupená jednatelem<br>Telefon: {{company_phone}}',
          'blok Pronajímatel'),
        ('gear_rental_contract', 2, 'tx', $o$Pronajímatel<br>{{company_name}}</div>$o$,
          'Pronajímatel<br>' || c_name || '</div>', 'řádek u podpisu'),
        ('gear_rental_contract', 3, 'tx', $o${{company_name}} · IČO: {{company_ico}} · {{company_address}} · {{company_email}}$o$,
          c_foot || ' · {{company_email}}', 'patička')
      ) AS x(typ, ord, how, old, new, label)
      WHERE x.typ = t.type
      ORDER BY ord
    LOOP
      cnt := (length(v_new) - length(replace(v_new, r.old, ''))) / length(r.old);
      IF (r.how = 'all' AND cnt >= 1) OR cnt = 1 THEN
        v_new := replace(v_new, r.old, r.new);
        n_ch := n_ch + 1;
      ELSIF cnt = 0 AND strpos(v_new, r.new) > 0 THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE '%: pasáž „%“ nenalezena v dosavadním znění (výskytů %) – přeskočeno', t.type, r.label, cnt;
      END IF;
    END LOOP;

    -- překlady: s dosavadním provozovatelem a bez platného otisku pryč; jinak proměnné provozovatele doslova
    v_tr := coalesce(t.content_translations, '{}'::jsonb);
    FOR l IN SELECT k FROM jsonb_object_keys(v_tr) AS k LOOP
      CONTINUE WHEN jsonb_typeof(v_tr -> l) <> 'string';
      v_one := v_tr ->> l;
      -- platný otisk = překlad vznikl z ČEŠTINY PO TÉTO ZMĚNĚ (v_new); cokoli staršího s dosavadním provozovatelem pryč
      IF v_one ~ c_old AND (t.translation_src ->> l) IS DISTINCT FROM encode(extensions.digest(convert_to(v_new, 'UTF8'), 'sha1'), 'hex') THEN
        v_tr := v_tr - l; n_del := n_del + 1;
      ELSIF v_one ~ c_vars THEN
        v_tr := jsonb_set(v_tr, ARRAY[l], to_jsonb(replace(replace(replace(v_one,
                  '{{company_name}}', c_name), '{{company_ico}}', c_ico), '{{company_address}}', c_seat)));
        n_trv := n_trv + 1;
      END IF;
    END LOOP;

    IF v_new IS DISTINCT FROM t.content_html OR v_tr IS DISTINCT FROM coalesce(t.content_translations, '{}'::jsonb) THEN
      UPDATE public.document_templates d
         SET content_html = v_new,
             version = CASE WHEN v_new IS DISTINCT FROM t.content_html THEN coalesce(d.version, 1) + 1 ELSE d.version END,
             content_translations = v_tr,
             translation_src = (SELECT coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb)
                                  FROM jsonb_each(coalesce(d.translation_src, '{}'::jsonb)) AS s WHERE v_tr ? s.key),
             updated_at = now()
       WHERE d.id = t.id;
    END IF;

    RAISE NOTICE '%: pasáží změněno %, už hotovo %, přeskočeno %; nová verze: %; překlady: odstraněno %, proměnné nahrazeny v %',
      t.type, n_ch, n_done, n_skip,
      CASE WHEN v_new IS DISTINCT FROM t.content_html THEN (coalesce(t.version, 1) + 1)::text ELSE 'ne (beze změny)' END, n_del, n_trv;
    IF v_new ~ c_old THEN
      RAISE WARNING '%: v šabloně ZŮSTÁVÁ dosavadní provozovatel – upravte ručně (Velín → Dokumenty → Smluvní texty)', t.type;
    END IF;
    IF v_new ~ c_vars THEN
      RAISE WARNING '%: v šabloně ZŮSTÁVÁ proměnná provozovatele ({{company_name}} / {{company_ico}} / {{company_address}}) – starší verze aplikace by do ní doplnila dosavadního provozovatele; nahraďte ji doslovným údajem ve Velínu', t.type;
    END IF;
  END LOOP;
END $$;
