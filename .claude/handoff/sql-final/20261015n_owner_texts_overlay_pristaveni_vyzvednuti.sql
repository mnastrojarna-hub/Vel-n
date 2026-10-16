-- =============================================================================
-- 20261015n_owner_texts_overlay_pristaveni_vyzvednuti.sql
-- datová migrace (bez změn schématu): cizí jazyky stránek Přistavení a Vyzvednutí.
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
    ('pages_overlay.jak_pujcit_pristaveni.en', '{intro}', 'full', 'b6f35a0b472ee686e1541b6acea7d5f9', $t$Want to set off without travelling to the rental first? We'll arrange <strong>delivery of the bike to an agreed place</strong> – your home, a hotel, a train station or the start of your trip. We deliver anywhere in the Czech Republic – straight from our branch in Mezná near Pelhřimov. Delivery is available for bikes from our staffed branch in Mezná; bikes from the self-service branch in Velké Němčice are picked up only at that branch.$t$),
    ('pages_overlay.jak_pujcit_pristaveni.de', '{intro}', 'full', '5f5eba98750ec232e82ca2f2bdc07916', $t$Du willst losfahren, ohne erst zum Verleih zu fahren? Wir organisieren die <strong>Lieferung des Motorrads an einen vereinbarten Ort</strong> – nach Hause, ins Hotel, zum Bahnhof oder an den Start deiner Tour. Wir liefern überallhin in Tschechien – direkt aus unserer Filiale in Mezná bei Pelhřimov. Die Lieferung gibt es für Motorräder aus unserer Filiale mit Personal in Mezná; Motorräder der Selbstbedienungsfiliale in Velké Němčice holst du nur direkt dort ab.$t$),
    ('pages_overlay.jak_pujcit_pristaveni.es', '{intro}', 'full', 'd18e60518ca38dd7caefa9e5aea7b90f', $t$¿Quieres salir sin tener que desplazarte hasta el alquiler? Te <strong>llevamos la moto al lugar acordado</strong>: a casa, al hotel, a la estación o al punto de salida de tu excursión. Te la llevamos a cualquier lugar de la República Checa, directamente desde nuestra sucursal de Mezná, cerca de Pelhřimov. La entrega está disponible para las motos de nuestra sucursal con personal de Mezná; las motos de la sucursal de autoservicio de Velké Němčice solo se recogen en esa sucursal.$t$),
    ('pages_overlay.jak_pujcit_pristaveni.fr', '{intro}', 'full', '34848782b397fa2cb72b2cda18da9da6', $t$Tu veux partir sans passer d'abord par l'agence ? Nous organisons la <strong>livraison de la moto à l'endroit convenu</strong> – chez toi, à l'hôtel, à la gare ou au point de départ de ta balade. Nous livrons partout en Tchéquie – directement depuis notre agence de Mezná, près de Pelhřimov. La livraison est proposée pour les motos de notre agence avec personnel de Mezná ; les motos de l'agence en libre-service de Velké Němčice se récupèrent uniquement sur place.$t$),
    ('pages_overlay.jak_pujcit_pristaveni.nl', '{intro}', 'full', '391fa5a674004a10b23645707942fc86', $t$Wil je vertrekken zonder eerst naar de verhuur te gaan? We zorgen voor <strong>bezorging van de motor op een afgesproken plek</strong> – thuis, bij je hotel, op het station of bij het startpunt van je tocht. We bezorgen overal in Tsjechië – rechtstreeks vanuit onze vestiging in Mezná bij Pelhřimov. Bezorging is mogelijk voor motoren van onze bemande vestiging in Mezná; motoren van de zelfbedieningsvestiging in Velké Němčice haal je alleen daar op.$t$),
    ('pages_overlay.jak_pujcit_pristaveni.pl', '{intro}', 'full', '3e41431fc70b903e08c31445e3ee704d', $t$Chcesz wyruszyć bez jazdy do wypożyczalni? Zorganizujemy <strong>dostawę motocykla w umówione miejsce</strong> – do domu, do hotelu, na dworzec albo na start twojej wycieczki. Dowieziemy go w dowolne miejsce w Czechach – prosto z naszego oddziału w Mezná koło Pelhřimova. Dostawę oferujemy dla motocykli z oddziału z obsługą w Mezná; motocykle z samoobsługowego oddziału Velké Němčice odbiera się tylko bezpośrednio w tym oddziale.$t$),
    ('pages_overlay.jak_pujcit_pristaveni.en', '{process,steps,9,text}', 'full', '0e0ac4fa464d47e18fad23d81f5041f7', $t$Return the bike on time at the place agreed in advance. No need to wash or refuel it – just make sure the reserve light isn't on.$t$),
    ('pages_overlay.jak_pujcit_pristaveni.de', '{process,steps,9,text}', 'full', '8289a0fa143009d3133b76da003bbe61', $t$Gib das Motorrad pünktlich am vorab vereinbarten Ort zurück. Waschen und tanken musst du nicht – nur die Reserveleuchte sollte nicht leuchten.$t$),
    ('pages_overlay.jak_pujcit_pristaveni.es', '{process,steps,9,text}', 'full', '2c9455609e7a99290a0217050f335b82', $t$Devuelve la moto a tiempo en el lugar acordado previamente. No tienes que lavarla ni repostar; solo procura que no esté encendido el testigo de reserva.$t$),
    ('pages_overlay.jak_pujcit_pristaveni.fr', '{process,steps,9,text}', 'full', '77ee71af2a6482f88c8d5de265fbcc12', $t$Rends la moto à l'heure, à l'endroit convenu à l'avance. Pas besoin de la laver ni de faire le plein – veille seulement à ce que le voyant de réserve ne soit pas allumé.$t$),
    ('pages_overlay.jak_pujcit_pristaveni.nl', '{process,steps,9,text}', 'full', '003269ba15b3f1d290c83f2c010d3720', $t$Breng de motor op tijd terug op de afgesproken plek. Wassen of tanken is niet nodig – zorg alleen dat het reservelampje niet brandt.$t$),
    ('pages_overlay.jak_pujcit_pristaveni.pl', '{process,steps,9,text}', 'full', '373b17ec4bcaa2382adc18e0329af83c', $t$Zwróć motocykl na czas w umówionym miejscu. Nie trzeba go myć ani tankować – byle nie świeciła się kontrolka rezerwy.$t$),
    ('pages_overlay.jak_pujcit_vyzvednuti.en', '{intro}', 'full', 'd20abaa0d47ac9671e38e323f133f3f4', $t$At <strong>MotoGo24 – motorcycle rental in the Vysočina region</strong>,&nbsp;picking up a bike takes just a few minutes. We rent with <strong>no deposit, rider gear included and 24/7 pick-up and return</strong>. Come to Mezná near Pelhřimov in person and hit the road! At the self-service branch in Velké Němčice near Brno you pick up the bike yourself with an access code from the app or e-mail.$t$),
    ('pages_overlay.jak_pujcit_vyzvednuti.de', '{intro}', 'full', '2630ef60220015636336d93e25f6e816', $t$Bei <strong>MotoGo24 – Motorradverleih in der Region Vysočina</strong>&nbsp;dauert die Abholung nur wenige Minuten. Wir vermieten <strong>ohne Kaution, mit Fahrerausrüstung inklusive und mit Abholung und Rückgabe rund um die Uhr</strong>. Komm persönlich nach Mezná bei Pelhřimov und ab auf die Straße! In der Selbstbedienungsfiliale in Velké Němčice bei Brno holst du das Motorrad selbst mit einem Zugangscode aus der App oder der E-Mail ab.$t$),
    ('pages_overlay.jak_pujcit_vyzvednuti.es', '{intro}', 'full', '653c572897c080e8b908df13ce738e76', $t$En <strong>MotoGo24 – alquiler de motos en la región de Vysočina</strong>,&nbsp;recoger la moto es cuestión de pocos minutos. Alquilamos <strong>sin fianza, con el equipamiento del piloto incluido y con recogida y devolución 24/7</strong>. ¡Ven en persona a Mezná, cerca de Pelhřimov, y sal a la carretera! En la sucursal de autoservicio de Velké Němčice, cerca de Brno, recoges la moto tú mismo con un código de acceso de la app o del e-mail.$t$),
    ('pages_overlay.jak_pujcit_vyzvednuti.fr', '{intro}', 'full', '70a908db218199d77a514ab7f8de2d4b', $t$Chez <strong>MotoGo24 – location de motos dans la région de Vysočina</strong>,&nbsp;la prise en charge de la moto ne prend que quelques minutes. Nous louons <strong>sans caution, avec l'équipement du pilote inclus, et le retrait comme le retour se font 24h/24</strong>. Viens nous voir à Mezná, près de Pelhřimov, et en route ! À l'agence en libre-service de Velké Němčice, près de Brno, tu récupères la moto toi-même avec un code d'accès reçu dans l'appli ou par e-mail.$t$),
    ('pages_overlay.jak_pujcit_vyzvednuti.nl', '{intro}', 'full', '7db17d587bd9a32cbd730a8ebd1b5d02', $t$Bij <strong>MotoGo24 – motorverhuur in de regio Vysočina</strong> is het ophalen van de motor in een paar minuten geregeld. We verhuren <strong>zonder borg, met rijuitrusting inbegrepen en met ophalen en inleveren 24/7</strong>. Kom persoonlijk naar Mezná bij Pelhřimov en ga op pad! Bij de zelfbedieningsvestiging in Velké Němčice bij Brno haal je de motor zelf op met een toegangscode uit de app of de e-mail.$t$),
    ('pages_overlay.jak_pujcit_vyzvednuti.pl', '{intro}', 'full', 'ab641fac658b232fe1cf6a101d3bb02a', $t$W <strong>MotoGo24 – wypożyczalni motocykli w regionie Vysočina</strong> odbiór motocykla to kwestia kilku minut. Wypożyczamy <strong>bez kaucji, z wyposażeniem kierowcy w cenie oraz z odbiorem i zwrotem 24/7</strong>. Przyjedź osobiście do oddziału w Mezná koło Pelhřimova i ruszaj w drogę! W samoobsługowym oddziale Velké Němčice koło Brna odbierzesz motocykl sam za pomocą kodu dostępu z aplikacji lub e-maila.$t$)
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
        RAISE NOTICE 'overlay_pristaveni_vyzvednuti: % % PŘESKOČENO – text mezitím změněn: %', f.k, f.path, left(coalesce(v_cur, '∅'), 200);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'overlay_pristaveni_vyzvednuti: app_settings upraveno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
