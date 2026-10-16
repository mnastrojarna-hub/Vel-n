-- =============================================================================
-- 20261015m_owner_texts_overlay_postup.sql
-- datová migrace (bez změn schématu): cizí jazyky stránky Postup (místa převzetí, krok Vrácení, FAQ).
--
-- Pravidlo majitele (2026-10-11 doslova: „Mytí ani tankování není třeba na obslužné pobočce. Na
-- samoobsluze není potřeba tankovat. To důležité je pouze, aby motorka byla umytá a nesvítila
-- rezerva.“; upřesnění 2026-10-12: stav paliva neřešíme, plnou nádrž při převzetí nikdy neslibovat,
-- žádný poplatek za palivo):
--   → Vrácení kdekoli: tankovat netřeba, jen ať nesvítí rezerva. Umytá jen na samoobslužné pobočce
--     Velké Němčice u Brna; v Mezné u Pelhřimova i při vrácení jinde (odvoz z Mezné) bez mytí.
--
-- app_settings pages_overlay.<stránka>.<en|de|es|fr|nl|pl> = automatické překlady PHP stránek (Velín
-- „Přeložit vše naráz“); přebíjí lang/pages_<jazyk>.php a seznamy (faq, kroky, odrážky) bere CELÉ.
-- Každý list se nastaví PŘESNĚ na text z lang/pages_<jazyk>.php (jsonb_set jen toho listu).
-- uk overlay neexistuje (ukrajinština bere rovnou lang/pages_uk.php).
--
-- Bezpečnost: mění JEN text ve znění ověřeném proti živé DB (stav 2026-10-15); co mezitím
-- někdo upravil ve Velínu, se přeskočí s NOTICE. Idempotentní (2. běh nic nezmění). Bez
-- BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================

DO $$
DECLARE
  f record;
  cnt integer;
  v_cur text;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  -- klíč app_settings, cesta k textovému listu JSON, how + old:
  --   'full'   = celý živý list má otisk md5 = old (ověřený stav 2026-10-15) → nahradí se celý
  --   'phrase' = věta old (v listu jednou) se nahradí new, zbytek listu zůstává
  FOR f IN
    SELECT * FROM (VALUES
    ('pages_overlay.jak_pujcit_postup.en', '{intro_p2}', 'full', 'a2b23d72c603589821379b2d8031b09a', $t$At our <strong>motorcycle rental</strong> you do everything online: choose a bike, pick your dates and fill in the booking form – including gear and how you want to receive the bike. Pick it up in Mezná near Pelhřimov (from there we can also deliver it anywhere in the Czech Republic) or at the self-service branch in Velké Němčice near Brno. You pay online when you complete your booking.$t$),
    ('pages_overlay.jak_pujcit_postup.de', '{intro_p2}', 'full', '6d420f5cb64e17c139c7f1a58487cdac', $t$In unserem <strong>Motorradverleih</strong> erledigst du alles online: Motorrad wählen, Termin festlegen und Buchungsformular ausfüllen – inklusive Ausrüstung und Art der Übergabe. Hol das Motorrad in Mezná bei Pelhřimov ab (von dort liefern wir es dir auch überallhin in Tschechien) oder per Selbstbedienung in Velké Němčice bei Brno. Bezahlt wird online beim Abschluss der Buchung.$t$),
    ('pages_overlay.jak_pujcit_postup.es', '{intro_p2}', 'full', '7017e35edfd8c4e0b4332571363d61d7', $t$En nuestro <strong>alquiler de motos</strong> lo haces todo online: eliges la moto, escoges las fechas y rellenas el formulario de reserva, incluido el equipamiento y la forma de entrega. Recoge la moto en Mezná, cerca de Pelhřimov (desde allí también te la llevamos a cualquier lugar de la República Checa), o en el autoservicio de Velké Němčice, cerca de Brno. Pagas online al completar la reserva.$t$),
    ('pages_overlay.jak_pujcit_postup.fr', '{intro_p2}', 'full', '9ce4ae02b7ce7af52234f301424a43c0', $t$Dans notre <strong>location de motos</strong>, tu fais tout en ligne : tu choisis la moto, tu fixes tes dates et tu remplis le formulaire de réservation – équipement et mode de remise compris. Récupère la moto à Mezná, près de Pelhřimov (d'où nous pouvons aussi te la livrer n'importe où en Tchéquie), ou en libre-service à Velké Němčice, près de Brno. Tu paies en ligne en finalisant la réservation.$t$),
    ('pages_overlay.jak_pujcit_postup.nl', '{intro_p2}', 'full', 'f674c178e11e6d8de64d7f1f99b96241', $t$Bij onze <strong>motorverhuur</strong> doe je alles online: kies een motor, kies een datum en vul het reserveringsformulier in – inclusief uitrusting en overdrachtsmethode. Haal de motor op in Mezná bij Pelhřimov (vanaf daar bezorgen we ook overal in Tsjechië) of via zelfbediening in Velké Němčice bij Brno. Je betaalt online bij het voltooien van de reservering.$t$),
    ('pages_overlay.jak_pujcit_postup.pl', '{intro_p2}', 'full', '24fab655b71ba5d40fc9351840decb28', $t$W naszej <strong>wypożyczalni motocykli</strong> wszystko załatwisz online: wybierz motocykl, wybierz termin i wypełnij formularz rezerwacji – wraz z wyposażeniem i sposobem przekazania. Odbierz motocykl w oddziale Mezná koło Pelhřimova (stamtąd możemy go też podstawić w dowolne miejsce w Czechach) albo samoobsługowo w Velké Němčice koło Brna. Płacisz online przy finalizacji rezerwacji.$t$),
    ('pages_overlay.jak_pujcit_postup.en', '{process,steps,4,text}', 'full', 'cbae40a195377fb904a89854a593c024', $t$Choose how you get the bike – in person in Mezná near Pelhřimov, self-service in Velké Němčice near Brno, or delivered from Mezná anywhere in the Czech Republic.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_postup.de', '{process,steps,4,text}', 'full', '56b63b8fea6a5e7ce852e5e87e0dbf19', $t$Wähle, wie du das Motorrad bekommst – persönlich in Mezná bei Pelhřimov, per Selbstbedienung in Velké Němčice bei Brno oder per Lieferung ab Mezná überallhin in Tschechien.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_postup.es', '{process,steps,4,text}', 'full', '7b4967ec58f82d209c6609d7d16b21ad', $t$Elige dónde recibes la moto: en persona en nuestra sucursal de Mezná, cerca de Pelhřimov; en el autoservicio de Velké Němčice, cerca de Brno; o con entrega desde Mezná en cualquier lugar de la República Checa.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_postup.fr', '{process,steps,4,text}', 'full', '379bb6b924c1e33bbe722ed1085b874f', $t$Choisis comment tu récupères la moto – en personne à Mezná, près de Pelhřimov, en libre-service à Velké Němčice, près de Brno, ou par livraison depuis Mezná n'importe où en Tchéquie.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_postup.nl', '{process,steps,4,text}', 'full', 'a64ba67959d4b7c9ff220deda60ad97c', $t$Selecteer de ophaalmethode – persoonlijk in Mezná bij Pelhřimov, via zelfbediening in Velké Němčice bij Brno, of bezorging vanuit Mezná overal in Tsjechië.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_postup.pl', '{process,steps,4,text}', 'full', '2d9355cb769ff288bdcb1caf76f0921e', $t$Wybierz sposób odbioru – osobiście w oddziale Mezná koło Pelhřimova, samoobsługowo w Velké Němčice koło Brna albo podstawienie z oddziału Mezná w dowolne miejsce w Czechach.&nbsp;$t$),
    ('pages_overlay.jak_pujcit_postup.en', '{process,steps,11,text}', 'full', '52fe3f5083acc44154eb65cea9bd2d2a', $t$Return the bike on time – in person at the branch you rented it from (Mezná near Pelhřimov or the self-service branch in Velké Němčice near Brno), or, for bikes from Mezná, at a place agreed in advance. No need to refuel – just make sure the reserve light isn't on. It only needs to be returned washed at the self-service branch in Velké Němčice.$t$),
    ('pages_overlay.jak_pujcit_postup.de', '{process,steps,11,text}', 'full', 'aec185c493740d14232dc8e6cff7f23c', $t$Bring das Motorrad pünktlich zurück – persönlich in die Filiale, in der du es gemietet hast (Mezná bei Pelhřimov oder die Selbstbedienungsfiliale in Velké Němčice bei Brno), Motorräder aus Mezná auch an einen vorher vereinbarten Ort. Tanken musst du nicht – nur die Reserveleuchte sollte nicht leuchten. Gewaschen zurückbringen musst du es nur an der Selbstbedienungsfiliale in Velké Němčice.$t$),
    ('pages_overlay.jak_pujcit_postup.es', '{process,steps,11,text}', 'full', '42812cb9197b3e18f11527f30b196914', $t$Devuelve la moto a tiempo: en persona en la sucursal donde la alquilaste (Mezná, cerca de Pelhřimov, o el autoservicio de Velké Němčice, cerca de Brno) o, si es de Mezná, también en el lugar acordado previamente. No tienes que repostar; solo procura que no esté encendido el testigo de reserva. Solo en la sucursal de autoservicio de Velké Němčice hay que devolverla lavada.$t$),
    ('pages_overlay.jak_pujcit_postup.fr', '{process,steps,11,text}', 'full', 'fb82fc3253934db41c0f144e97989b50', $t$Rends la moto à l'heure – en personne à l'agence où tu l'as louée (Mezná, près de Pelhřimov, ou l'agence en libre-service de Velké Němčice, près de Brno) ou, pour les motos de Mezná, à un endroit convenu à l'avance. Pas besoin de faire le plein – veille seulement à ce que le voyant de réserve ne soit pas allumé. Tu ne dois la rendre lavée qu'à l'agence en libre-service de Velké Němčice.$t$),
    ('pages_overlay.jak_pujcit_postup.nl', '{process,steps,11,text}', 'full', 'fdb8ca2d86e2dcb9b99dc3869129f3dc', $t$Breng de motor op tijd terug – persoonlijk naar de vestiging waar je hem huurde (Mezná bij Pelhřimov of de zelfbedieningsvestiging in Velké Němčice bij Brno), motoren uit Mezná ook op de afgesproken plek. Tanken is niet nodig – zorg alleen dat het reservelampje niet brandt. Alleen bij de zelfbedieningsvestiging in Velké Němčice lever je hem gewassen in.$t$),
    ('pages_overlay.jak_pujcit_postup.pl', '{process,steps,11,text}', 'full', 'e27f90da752b106bd58f56b5ae686ae9', $t$Zwróć motocykl na czas – osobiście w oddziale, w którym go wypożyczyłeś (Mezná koło Pelhřimova albo samoobsługowy oddział Velké Němčice koło Brna), a motocykle z oddziału Mezná także w umówionym miejscu. Tankować nie musisz – byle nie świeciła się kontrolka rezerwy. Umyty motocykl oddajesz tylko w samoobsługowym oddziale Velké Němčice.$t$),
    ('pages_overlay.jak_pujcit_postup.en', '{faq,items,2,a}', 'full', 'a23f81d8f4076a1aff3b05e9aefb7a3d', $t$At our staffed branch in Mezná near Pelhřimov (from there we can also&nbsp;<strong>deliver the bike</strong>&nbsp;to a place of your choice) or at the self-service branch in Velké Němčice near Brno.$t$),
    ('pages_overlay.jak_pujcit_postup.de', '{faq,items,2,a}', 'full', '5222d3505817648f855348f5d97750a5', $t$In unserer Filiale mit Personal in Mezná bei Pelhřimov (von dort&nbsp;<strong>liefern wir dir das Motorrad</strong>&nbsp;auch an einen Ort deiner Wahl) oder an der Selbstbedienungsfiliale in Velké Němčice bei Brno.$t$),
    ('pages_overlay.jak_pujcit_postup.es', '{faq,items,2,a}', 'full', '77486b92e7152c3e60613275fadb3653', $t$En nuestra sucursal con personal de Mezná, cerca de Pelhřimov (desde allí también podemos&nbsp;<strong>llevarte la moto</strong>&nbsp;al lugar que elijas), o en la sucursal de autoservicio de Velké Němčice, cerca de Brno.$t$),
    ('pages_overlay.jak_pujcit_postup.fr', '{faq,items,2,a}', 'full', 'e3206c3ddc09379bc18806df9626b9f8', $t$À notre agence avec personnel de Mezná, près de Pelhřimov (d'où nous pouvons aussi te&nbsp;<strong>livrer la moto</strong>&nbsp;à l'endroit de ton choix), ou à l'agence en libre-service de Velké Němčice, près de Brno.$t$),
    ('pages_overlay.jak_pujcit_postup.nl', '{faq,items,2,a}', 'full', '64b53e784825a3032b2430d9ce5a149d', $t$Bij de bemande vestiging in Mezná bij Pelhřimov (van daaruit bieden we ook&nbsp;<strong>motorbezorging</strong>&nbsp;naar een plek van jouw keuze) of bij de zelfbedieningsvestiging in Velké Němčice bij Brno.$t$),
    ('pages_overlay.jak_pujcit_postup.pl', '{faq,items,2,a}', 'full', '6184081e28d9ced3581421cd56fa2e88', $t$W oddziale z obsługą w Mezná koło Pelhřimova (stamtąd oferujemy też&nbsp;<strong>podstawienie motocykla</strong>&nbsp;w wybrane przez ciebie miejsce) albo w samoobsługowym oddziale Velké Němčice koło Brna.$t$)
    ) AS x(k, path, how, old, new)
  LOOP
    UPDATE public.app_settings
       SET value = jsonb_set(value, f.path::text[], to_jsonb(CASE WHEN f.how = 'phrase'
                     THEN replace(value #>> f.path::text[], f.old, f.new) ELSE f.new END), false),
           updated_at = now()
     WHERE key = f.k AND jsonb_typeof(value) = 'object'
       AND jsonb_typeof(value #> f.path::text[]) = 'string'
       AND CASE WHEN f.how = 'phrase' THEN strpos(value #>> f.path::text[], f.old) > 0
                                       AND strpos(value #>> f.path::text[], f.new) = 0
                ELSE md5(value #>> f.path::text[]) = f.old END;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    IF cnt > 0 THEN
      n_upd := n_upd + cnt;
    ELSE
      SELECT value #>> f.path::text[] INTO v_cur FROM public.app_settings WHERE key = f.k;
      IF (CASE WHEN f.how = 'phrase' THEN strpos(coalesce(v_cur, ''), f.new) > 0 ELSE v_cur = f.new END) THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'overlay_postup: % % PŘESKOČENO – text mezitím změněn: %', f.k, f.path, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'overlay_postup: app_settings upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
