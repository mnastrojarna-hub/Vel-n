-- =============================================================================
-- 20261015t_owner_texts_banner.sql
-- datová migrace (bez změn schématu): překlady horního banneru webu i appky (header_banner).
--
-- Odpovědi majitele 2026-10-11/12: dvě pobočky – obslužná Mezná u Pelhřimova (odtud i přistavení
-- a odvoz) a samoobslužná Velké Němčice u Brna (převzetí i vrácení jen na pobočce, kódy z aplikace /
-- e-mailu); aplikace MotoGo24 je na Google Play (Android) i v App Store (iPhone).
--
-- Banner (app_settings.header_banner) se ukazuje nahoře na každé stránce webu ve všech jazycích i v appce.
-- Překlad se použije jen když translations_src = SHA-1 (hex) českého textu – stejně to počítá web
-- (layout-banner.php), appka i Velín. Doplní jen překlady k aktuálnímu textu; enabled/text/bg/color
-- zůstávají. Po změně textu ve Velínu („Uložit banner“) Velín přeloží znovu sám.
-- Otisk textu „V zimním období od 1.11.2026 do 25.3.2027 zavřeno.“ = a298ae81878e23ac13221512d1ef1604c30b4157.
--
-- Bezpečnost: mění JEN text ve znění ověřeném proti živé DB (stav 2026-10-15); co mezitím
-- někdo upravil ve Velínu, se přeskočí s NOTICE. Idempotentní (2. běh nic nezmění). Bez
-- BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================

DO $$
DECLARE
  c_text constant text := $t$V zimním období od 1.11.2026 do 25.3.2027 zavřeno.$t$;
  v_tr constant jsonb := jsonb_build_object(
      'en', 'Closed for the winter season from 1 November 2026 to 25 March 2027.',
      'de', $t$In der Wintersaison vom 1. November 2026 bis 25. März 2027 geschlossen.$t$,
      'es', $t$Cerrado durante la temporada de invierno, del 1 de noviembre de 2026 al 25 de marzo de 2027.$t$,
      'fr', $t$Fermé pendant la saison d'hiver, du 1er novembre 2026 au 25 mars 2027.$t$,
      'nl', 'Gesloten in het winterseizoen, van 1 november 2026 tot en met 25 maart 2027.',
      'pl', 'Nieczynne w sezonie zimowym, od 1 listopada 2026 do 25 marca 2027.',
      'uk', $t$Зачинено на зимовий сезон: з 1 листопада 2026 до 25 березня 2027.$t$);
  v_val jsonb;
  cnt integer;
BEGIN
  UPDATE public.app_settings
     SET value = value || jsonb_build_object(
           'translations', v_tr,
           'translations_src', encode(extensions.digest(convert_to(value ->> 'text', 'UTF8'), 'sha1'), 'hex')),
         updated_at = now()
   WHERE key = 'header_banner'
     AND jsonb_typeof(value) = 'object'
     AND value ->> 'text' = c_text
     AND (value ->> 'translations_src') IS DISTINCT FROM
         encode(extensions.digest(convert_to(value ->> 'text', 'UTF8'), 'sha1'), 'hex');
  GET DIAGNOSTICS cnt = ROW_COUNT;
  IF cnt > 0 THEN
    RAISE NOTICE 'header_banner: doplněny překlady (% jazyků)', (SELECT count(*) FROM jsonb_object_keys(v_tr));
  ELSE
    SELECT value INTO v_val FROM public.app_settings WHERE key = 'header_banner';
    RAISE NOTICE 'header_banner: beze změny (text: %, translations_src: %)',
      left(coalesce(v_val ->> 'text', '∅'), 80), coalesce(v_val ->> 'translations_src', '∅');
  END IF;
END $$;
