-- =============================================================================
-- FAQ: dárkové poukazy ani poukazy ze Slevomatu nelze uplatnit v e-shopu
-- Migrace: 20260924c_faq_eshop_vouchers.sql (DATOVÁ, bez změn schématu)
--
-- Rozhodnutí provozovatele 2026-09-24 (e-shop část 2, 20260924b): v e-shopu
-- appky platí jen promo kódy; dárkový poukaz MotoGo24 ani poukaz ze Slevomatu
-- nelze uplatnit, a promo kód nelze uplatnit na nákup dárkového poukazu.
-- FAQ 78d4791f („Můžu dárkový poukaz uplatnit na nákup ve vašem e-shopu?“)
-- dosud říkalo jen „ne“ — doplněn Slevomat a pravidlo pro promo kódy
-- (cs + de/en/es/fr/nl/pl; uk překlad řádek nemá). Čte ho web, appka i AI agenti.
--
-- Odpověď se přepíše JEN pokud je v DB stále původní text (ověřeno proti
-- živým datům přes REST 2026-09-24) — ruční úpravu z Velína nepřepíše.
-- Idempotentní (2. běh = 0 změn, NOTICE).
-- =============================================================================

DO $$
DECLARE
  f     record;
  cnt   integer;
  n_upd integer := 0;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
    ('cs', $t$Ne, to bohužel není možné. Naše poukazy lze uplatnit jen na zážitek - tzn. půjčit si motorku a vyrazit s větrem o závod.&nbsp;$t$, $t$Ne, to bohužel není možné. Dárkové poukazy MotoGo24 ani poukazy zakoupené přes Slevomat nelze uplatnit v e-shopu — slouží jen na zážitek, tzn. půjčit si motorku a vyrazit s větrem o závod. V e-shopu lze použít pouze slevový (promo) kód a ten nelze uplatnit na nákup dárkového poukazu.$t$),
    ('de', $t$Nein, das ist leider nicht möglich. Unsere Gutscheine können nur für ein Erlebnis eingelöst werden – das heißt, ein Motorrad mieten und mit dem Wind um die Wette fahren.&nbsp;$t$, $t$Nein, das ist leider nicht möglich. Geschenkgutscheine von MotoGo24 und über Slevomat gekaufte Gutscheine können im E-Shop nicht eingelöst werden – sie gelten nur für ein Erlebnis, also ein Motorrad mieten und mit dem Wind um die Wette fahren. Im E-Shop kann nur ein Rabattcode (Promo-Code) verwendet werden, der sich jedoch nicht auf den Kauf eines Geschenkgutscheins anwenden lässt.$t$),
    ('en', $t$No, unfortunately that's not possible. Our vouchers can only be redeemed for an experience - that is, renting a motorcycle and hitting the road with the wind at your back.&nbsp;$t$, $t$No, unfortunately that's not possible. MotoGo24 gift vouchers and vouchers bought via Slevomat cannot be used in the e-shop — they are only for the experience, i.e. renting a motorcycle and hitting the road with the wind at your back. In the e-shop you can only use a discount (promo) code, and it cannot be applied to buying a gift voucher.$t$),
    ('es', $t$No, lamentablemente no es posible. Nuestros vales solo se pueden canjear en una experiencia, es decir, alquilar una moto y salir a competir con el viento.&nbsp;$t$, $t$No, lamentablemente no es posible. Los vales regalo de MotoGo24 y los vales comprados a través de Slevomat no se pueden canjear en la tienda online: solo sirven para la experiencia, es decir, alquilar una moto y salir a competir con el viento. En la tienda online solo se puede usar un código de descuento (promocional), que no se puede aplicar a la compra de un vale regalo.$t$),
    ('fr', $t$Non, malheureusement ce n'est pas possible. Nos bons ne peuvent être utilisés que pour une expérience - c'est-à-dire louer une moto et partir affronter le vent.&nbsp;$t$, $t$Non, malheureusement ce n'est pas possible. Les bons cadeaux MotoGo24 et les bons achetés via Slevomat ne peuvent pas être utilisés dans la boutique en ligne – ils sont réservés à l'expérience, c'est-à-dire louer une moto et partir affronter le vent. Dans la boutique en ligne, seul un code de réduction (code promo) peut être utilisé, et il ne s'applique pas à l'achat d'un bon cadeau.$t$),
    ('nl', $t$Nee, dat is helaas niet mogelijk. Onze bongutschriften kunnen alleen worden ingewisseld voor een ervaring - dus een motor huren en eropuit gaan met de wind in de races.&nbsp;$t$, $t$Nee, dat is helaas niet mogelijk. Cadeaubonnen van MotoGo24 en bonnen gekocht via Slevomat kunnen niet in de webshop worden ingewisseld – ze gelden alleen voor de ervaring, dus een motor huren en eropuit gaan met de wind in de rug. In de webshop kun je alleen een kortingscode (promocode) gebruiken, en die geldt niet voor de aankoop van een cadeaubon.$t$),
    ('pl', $t$Nie, niestety to nie jest możliwe. Nasze vouchery można wykorzystać tylko na doświadczenie - tzn. wynająć motorower i wyruszyć na jazdę.&nbsp;$t$, $t$Nie, niestety to nie jest możliwe. Bonów podarunkowych MotoGo24 ani bonów kupionych przez Slevomat nie można wykorzystać w sklepie internetowym – służą wyłącznie na przeżycie, czyli wynajęcie motocykla i jazdę z wiatrem we włosach. W sklepie internetowym można użyć tylko kodu rabatowego (promocyjnego), którego nie można zastosować przy zakupie bonu podarunkowego.$t$)
    ) AS v(lang, old_txt, new_txt)
  LOOP
    IF f.lang = 'cs' THEN
      UPDATE public.faq_items SET answer = f.new_txt
       WHERE id = '78d4791f-d161-41eb-b754-6a3c732f2ea6' AND answer = f.old_txt;
    ELSE
      UPDATE public.faq_items
         SET translations = jsonb_set(translations, ARRAY[f.lang, 'answer'], to_jsonb(f.new_txt))
       WHERE id = '78d4791f-d161-41eb-b754-6a3c732f2ea6'
         AND translations -> f.lang ->> 'answer' = f.old_txt;
    END IF;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    n_upd := n_upd + cnt;
    IF cnt = 0 THEN
      RAISE NOTICE 'faq 78d4791f [%]: původní text nenalezen (už upraveno) — přeskočeno', f.lang;
    END IF;
  END LOOP;
  RAISE NOTICE 'faq 78d4791f: aktualizováno % jazykových verzí', n_upd;
END
$$;
