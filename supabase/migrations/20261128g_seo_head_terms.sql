-- =============================================================================
-- 20261128g_seo_head_terms.sql
-- datová migrace (bez změn schématu): HLAVNÍ VÝRAZY – úvodní stránka jako jediná celostátní stránka pro
-- „půjčovna motorek“ a „motopůjčovna“ (titulek, popisek, H1, text v úvodní fotce, blok „O půjčovně“),
-- titulek a H1 kontaktu, text a copyright v patičce. NAHRAZUJE odložený návrh 20261128d (ten se nepoužije).
--
-- Datum: 2026-11-28. Podklad: export Google Search Console 4. 5.–25. 11. 2026 (majitel 27. 11.) – úvodní
-- stránka je hlavní adresou obou frází, ale Google ji čte jako krajskou („na Vysočině“ v titulku i H1);
-- pro stejné fráze ukazoval i celostátně psanou stránku /oblasti. Kód webu (motogo-web-php) má stejná
-- znění jako výchozí hodnoty a zároveň přesměrovává /oblasti a /pujcovna-motorek na úvodní stránku.
-- Mění se JEN české hodnoty (sloupec cms_variables.value). Sloupec translations (cizí jazyky) se nemění.
--
-- Bezpečnost: každý text se změní jen tehdy, když má v databázi PŘESNĚ znění ověřené proti živé DB
-- 2026-11-27 večer ('full' = celý text). Co mezitím někdo upravil ve Velínu, se přeskočí s NOTICE.
-- Idempotentní (2. běh nic nezmění). Bez BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci.
-- Záměrně nemění: schéma, žádný nový klíč (INSERT), staré „ploché“ klíče z triggeru
-- trg_sync_cms_flat_to_nested, texty stránky /pujcovna-motorek (česky se přesměrovává na úvod),
-- nadpisy sloupců patičky („Půjčovna motorek“, „Půjčovna motorek na sítích“).
-- PO NASAZENÍ: titulek, H1 a úvodní text úvodní stránky 8–12 týdnů NEMĚNIT (jinak nepůjde nic vyhodnotit).
-- Schváleno majitelem 2026-11-28.
-- =============================================================================

DO $$
DECLARE
  r record;
  n integer;
  v_cur text;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  -- x: pořadí, klíč, how ('full' = old je celé dosavadní znění; 'phrase' = old je část textu), old, new
  FOR r IN
    SELECT * FROM (VALUES
    -- / · Titulek úvodní stránky: obě hlavní fráze („půjčovna motorek“ + „motopůjčovna“) a „bez kauce“ místo „na Vysočině“ (kraj patří stránkám poboček)
    (1, 'web.home.seo.title', 'full', $o$Půjčovna motorek na Vysočině | MotoGo24$o$,
      $n$Půjčovna motorek bez kauce | Motopůjčovna MotoGo24$n$),
    -- / · Popisek pro vyhledávače: obě pobočky a přistavení po ČR místo „na Vysočině“, bez „nonstop provoz“ (v zimě zavřeno)
    (2, 'web.home.seo.description', 'full', $o$Půjč si motorku na Vysočině. Bez kauce, výbava pro řidiče v ceně, nonstop provoz. Cestovní, naked, supermoto, choppery, skútry i dětské motorky. Online rezervace i platba.$o$,
      $n$Půjč si motorku bez kauce a s výbavou pro řidiče v ceně. Motopůjčovna MotoGo24: pobočky Mezná u Pelhřimova a Velké Němčice u Brna, přistavení po celé ČR.$n$),
    -- / · Klíčová slova (vyhledávače je téměř nečtou): bez „Vysočina“ a „Pelhřimov“, ať neodporují titulku
    (3, 'web.home.seo.keywords', 'full', $o$půjčovna motorek Vysočina, pronájem motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna, motorky k pronájmu, online rezervace motorky$o$,
      $n$půjčovna motorek, motopůjčovna, půjčovna motorek bez kauce, pronájem motorek, půjčení motorky, půjčovna motocyklů, online rezervace motorky$n$),
    -- / · Hlavní nadpis: bez „na Vysočině a Moravě“ a bez slibu „převzetím kdykoliv“ (v zimě zavřeno); 45 znaků místo 88
    (4, 'web.home.h1', 'full', $o$Půjčovna motorek na Vysočině a Moravě – bez kauce, s výbavou v ceně a převzetím kdykoliv$o$,
      $n$Půjčovna motorek bez kauce a s výbavou v ceně$n$),
    -- / · Druhý řádek přes úvodní fotku: obě pobočky místo „Motopůjčovna na Vysočině“ (slovo motopůjčovna zůstává o řádek výš)
    (5, 'web.home.hero.body', 'full', $o$Motopůjčovna na Vysočině$o$,
      $n$Pobočky na Vysočině a u Brna$n$),
    -- / · Popisek záložní úvodní fotky: bez „na Vysočině“
    (6, 'web.home.hero.alt', 'full', $o$Půjčovna motorek na Vysočině$o$,
      $n$Půjčovna motorek MotoGo24$n$),
    -- / · Blok „O půjčovně MotoGo24“: první věta bez zúžení na Vysočinu (obě pobočky + přistavení po Česku); seznam výhod slovo od slova, jen vyčištěný zápis (jedna odrážka rozdělena na dvě, pryč dvě prázdné odrážky a řada mezer)
    (7, 'web.home.intro', 'full', $o$<strong>Půjč si motorku na Vysočině bez kauce a starostí. </strong>V MotoGo24 máme <span style="font-weight: bold">automatizované interní</span> <span style="font-weight: bold">procesy</span>. Věříme v jasná pravidla, rychlost a předvídatelnost pro zákazníka. Celý pronájem řídí náš vlastní informační systém, který zajišťuje jednotný průběh každé rezervace i každé mimořádné situace. Výsledkem je <span style="font-weight: bold">služba</span>, která <span style="font-weight: bold">odpovídá standardu velkých profesionálních společností </span>- <span style="font-weight: bold">s výhodou osobního přístupu rodinné motopůjčovny</span>.&nbsp;<div><br></div><div><span style="font-weight: bold">Hlavní benefity MotoGo24:</span></div><div><ul><li>Jsme jediná půjčovna motorek v Česku s<span style="font-weight: 700"> vlastní vymazlenou aplikací </span>a <span style="font-weight: 700">věrnostním programem.</span></li><li>Motorku půjčíme<span style="font-weight: 700"> každému nad 18 let s platným ŘP a bez omezení zkušeností.</span></li><li><span style="font-weight: 700">Pracujeme s přátelskou firemní filozofií a 100% smluvním krytím škod.</span></li><li>U nás vyřídíš <span style="font-weight: 700">vše online 24/7 </span>z pohodlí domova.</li><li><span style="font-weight: 700">Nevybíráme žádnou kauci.</span></li><li>Půjčujeme motorky s&nbsp;<span style="font-weight: 700">výbavou pro řidiče v ceně.</span></li><li><span style="font-weight: 700">Pokud máš vlastní motorku, můžeš si u nás samostatně půjčit výbavu </span>(pobočka Mezná).&nbsp; &nbsp; <span style="font-weight: 700">&nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; </span>Neomezujeme najeté km, cesty do zahraničí ani mimo EU <span style="font-size: 0.92rem">(stačí se řídit platností ZK).&nbsp;</span></li><li>Jsme <span style="font-weight: 700">největší motopůjčovna na Vysočině.</span></li><li>Nabízíme <span style="font-weight: 700">široký výběr modelů </span>i <span style="font-weight: 700">značek.</span></li><li>Pobočka v Mezné sídlí na <span style="font-weight: 700">strategickém místě mezi Prahou a Brnem </span>- snadno dostupném ze všech směrů.</li><li>Pohodlné zázemí motopůjčovny s <span style="font-weight: 700">převlékací kabinkou, toaletou, wifi a parkováním zdarma </span>(pobočka Mezná).</li><li><span style="font-weight: 700"><br></span></li><li><span style="font-weight: 700"><br></span></li></ul> <br></div>$o$,
      $n$<strong>Půjč si motorku bez kauce a starostí – na Vysočině, u Brna nebo s přistavením kamkoli v Česku.</strong> V MotoGo24 máme <strong>automatizované interní procesy</strong>. Věříme v jasná pravidla, rychlost a předvídatelnost pro zákazníka. Celý pronájem řídí náš vlastní informační systém, který zajišťuje jednotný průběh každé rezervace i každé mimořádné situace. Výsledkem je <strong>služba</strong>, která <strong>odpovídá standardu velkých profesionálních společností</strong> – <strong>s výhodou osobního přístupu rodinné motopůjčovny</strong>.<div><br></div><div><strong>Hlavní benefity MotoGo24:</strong></div><div><ul><li>Jsme jediná půjčovna motorek v Česku s <strong>vlastní vymazlenou aplikací</strong> a <strong>věrnostním programem</strong>.</li><li>Motorku půjčíme <strong>každému nad 18 let s platným ŘP a bez omezení zkušeností</strong>.</li><li><strong>Pracujeme s přátelskou firemní filozofií a 100% smluvním krytím škod.</strong></li><li>U nás vyřídíš <strong>vše online 24/7</strong> z pohodlí domova.</li><li><strong>Nevybíráme žádnou kauci.</strong></li><li>Půjčujeme motorky s <strong>výbavou pro řidiče v ceně</strong>.</li><li><strong>Pokud máš vlastní motorku, můžeš si u nás samostatně půjčit výbavu</strong> (pobočka Mezná).</li><li>Neomezujeme najeté km, cesty do zahraničí ani mimo EU (stačí se řídit platností ZK).</li><li>Jsme <strong>největší motopůjčovna na Vysočině</strong>.</li><li>Nabízíme <strong>široký výběr modelů</strong> i <strong>značek</strong>.</li><li>Pobočka v Mezné sídlí na <strong>strategickém místě mezi Prahou a Brnem</strong> – snadno dostupném ze všech směrů.</li><li>Pohodlné zázemí motopůjčovny s <strong>převlékací kabinkou, toaletou, wifi a parkováním zdarma</strong> (pobočka Mezná).</li></ul></div>$n$),
    -- /kontakt · Titulek kontaktu: co na stránce je; pryč „motopůjčovna a půjčovna motorek Vysočina“ (obě hlavní fráze patří jen úvodní stránce)
    (8, 'web.kontakt.seo.title', 'full', $o$Kontakt | MotoGo24 – motopůjčovna a půjčovna motorek Vysočina$o$,
      $n$Kontakt – telefon, e-mail a adresy poboček | MotoGo24$n$),
    -- /kontakt · Hlavní nadpis kontaktu: bez hlavní fráze „půjčovna motorek“
    (9, 'web.kontakt.h1', 'full', $o$Kontakty - půjčovna motorek Motogo24$o$,
      $n$Kontakt na MotoGo24$n$),
    -- patička (všechny stránky) · Text o nás: pobočka není „v Pelhřimově“ a rezervace není „ve třech krocích“; krátká fakta
    (10, 'web.layout.footer.aboutText', 'full', $o$Vítej u Motogo24, tvojí&nbsp;<strong>půjčovny motorek v Pelhřimově a u Brna</strong>! Nabízíme <strong>pronájem motorek</strong> pro místní i turisty. Vyber si z naší široké nabídky&nbsp; motorek a rezervuj online ve třech krocích. Objevuj s námi motorkářské trasy v ČR i v zahraničí!$o$,
      $n$MotoGo24 – půjčovna motorek se dvěma pobočkami: obslužnou v <strong>Mezné u Pelhřimova</strong> a samoobslužnou ve <strong>Velkých Němčicích u Brna</strong>. Půjčujeme bez kauce, s výbavou pro řidiče v ceně a s rezervací online.$n$),
    -- patička (všechny stránky) · Copyright: značka MotoGo24 bez „Vysočina“ (stejné jméno jako v titulku a u loga)
    (11, 'web.layout.footer.copyright', 'full', $o$© Půjčovna motorek Vysočina Motogo24 - všechna práva vyhrazena$o$,
      $n$© MotoGo24 – půjčovna motorek. Všechna práva vyhrazena.$n$)
    ) AS x(ord, key, how, old, new)
    ORDER BY ord
  LOOP
    UPDATE public.cms_variables
       SET value = to_jsonb(CASE WHEN r.how = 'phrase' THEN replace(value #>> '{}', r.old, r.new) ELSE r.new END),
           updated_at = now()
     WHERE key = r.key AND jsonb_typeof(value) = 'string'
       AND CASE WHEN r.how = 'phrase' THEN strpos(value #>> '{}', r.old) > 0 AND strpos(value #>> '{}', r.new) = 0
                ELSE value #>> '{}' = r.old END;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n > 0 THEN
      n_upd := n_upd + n;
    ELSE
      SELECT value #>> '{}' INTO v_cur FROM public.cms_variables WHERE key = r.key;
      IF NOT FOUND THEN
        n_skip := n_skip + 1;
        RAISE NOTICE 'seo_head_terms_g: % PŘESKOČENO – klíč v cms_variables neexistuje', r.key;
      ELSIF (CASE WHEN r.how = 'phrase' THEN strpos(coalesce(v_cur, ''), r.new) > 0 ELSE v_cur = r.new END) THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'seo_head_terms_g: % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', r.key, r.how, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'seo_head_terms_g: cms_variables změněno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
