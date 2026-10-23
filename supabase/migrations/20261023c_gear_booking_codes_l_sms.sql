-- =============================================================================
-- 2026-10-23 (c): Výpůjčka JEN výbavy — SMS/WhatsApp šablony (14/14)
-- message_templates door_codes_gear_only + door_codes_gate_gear_only + door_codes_gear_staffed (FIX-R1)
-- (sms + whatsapp × cs,en,de,es,fr,nl,pl,uk; cs tykání). ON CONFLICT DO NOTHING — úpravy z Velína zůstávají.
-- Výběr slugu: _gear_door_codes_sms_slug (brána → gate, obslužná bez brány → staffed, jinak gear_only).
-- Celek a pořadí souborů: viz 20261023c_gear_booking_codes.sql. Motorka beze změny (změny označené „2026-10-23“).
-- Idempotentní.
-- =============================================================================

-- Proměnné: {{booking_number}} {{door_code_gear}} {{locker_door}} {{valid_from}} {{valid_to}} (+ {{gate_code}}).
-- Bez brány = samoobsluha bez brány (postup v e-mailu s kódy); s bránou = samoobsluha Velké Němčice (displej);
-- staffed = obslužná pobočka (Mezná): kód výpůjčky se při převzetí nahlásí obsluze (bez {{locker_door}}).
-- WA bez Meta SID (posílá se text, jako ostatní kódy). Seed nepřepisuje úpravy z Velína.
-- en/de/nl/fr jen znaky GSM-7 (spojovník „-“ místo „–“, jako door_codes_gate en) → méně segmentů SMS.
INSERT INTO public.message_templates (slug, channel, language, name, body_template, content, category, is_marketing, is_active, variables)
SELECT t.slug, c.channel, t.lang, t.name, t.body, t.body, 'booking', false, true,
       CASE WHEN t.slug = 'door_codes_gate_gear_only'
            THEN ARRAY['booking_number', 'gate_code', 'door_code_gear', 'locker_door', 'valid_from', 'valid_to']
            WHEN t.slug = 'door_codes_gear_staffed'
            THEN ARRAY['booking_number', 'door_code_gear', 'valid_from', 'valid_to']
            ELSE ARRAY['booking_number', 'door_code_gear', 'locker_door', 'valid_from', 'valid_to'] END
FROM (VALUES
  ('door_codes_gear_only', 'Přístupový kód – výpůjčka výbavy (šatna)', 'cs', $t$Výpůjčka výbavy {{booking_number}} ({{valid_from}}–{{valid_to}}): kód šatny {{door_code_gear}}. Postup převzetí a vrácení najdeš v e-mailu s kódy. MOTO GO 24$t$),
  ('door_codes_gate_gear_only', 'Přístupové kódy – výpůjčka výbavy (brána, šatna)', 'cs', $t$Výpůjčka výbavy {{booking_number}} ({{valid_from}}–{{valid_to}}): 1) brána – horní schránka vpravo: {{gate_code}} 2) šatna (dveře č. {{locker_door}}): {{door_code_gear}}. Na displeji podepiš protokol, při vrácení tam potvrď vrácení výbavy. Zavřenou bránu po odjezdu zamkni, klíč vrať a kód přetoč. MOTO GO 24$t$),
  ('door_codes_gear_only', 'Přístupový kód – výpůjčka výbavy (šatna)', 'en', $t$Gear rental {{booking_number}} ({{valid_from}}-{{valid_to}}): locker room code {{door_code_gear}}. Pickup and return steps are in the e-mail with your codes. MOTO GO 24$t$),
  ('door_codes_gate_gear_only', 'Přístupové kódy – výpůjčka výbavy (brána, šatna)', 'en', $t$Gear rental {{booking_number}} ({{valid_from}}-{{valid_to}}): 1) gate - upper lockbox, right: {{gate_code}} 2) locker room (door {{locker_door}}): {{door_code_gear}}. Sign the handover on the display and confirm the return there too. Gate was closed? Lock it after leaving, return key, scramble code. MOTO GO 24$t$),
  ('door_codes_gear_only', 'Přístupový kód – výpůjčka výbavy (šatna)', 'de', $t$Ausrüstungsverleih {{booking_number}} ({{valid_from}}-{{valid_to}}): Code Umkleide {{door_code_gear}}. Ablauf für Abholung und Rückgabe steht in der E-Mail mit den Codes. MOTO GO 24$t$),
  ('door_codes_gate_gear_only', 'Přístupové kódy – výpůjčka výbavy (brána, šatna)', 'de', $t$Ausrüstungsverleih {{booking_number}} ({{valid_from}}-{{valid_to}}): 1) Tor - Schlüsselbox oben rechts: {{gate_code}} 2) Umkleide (Tür {{locker_door}}): {{door_code_gear}}. Protokoll am Display unterschreiben, dort auch die Rückgabe bestätigen. Tor war zu? Beim Gehen abschließen, Schlüssel zurück, Code verstellen. MOTO GO 24$t$),
  ('door_codes_gear_only', 'Přístupový kód – výpůjčka výbavy (šatna)', 'nl', $t$Huur uitrusting {{booking_number}} ({{valid_from}}-{{valid_to}}): code kleedkamer {{door_code_gear}}. Hoe ophalen en terugbrengen werkt, staat in de e-mail met de codes. MOTO GO 24$t$),
  ('door_codes_gate_gear_only', 'Přístupové kódy – výpůjčka výbavy (brána, šatna)', 'nl', $t$Huur uitrusting {{booking_number}} ({{valid_from}}-{{valid_to}}): 1) poortkastje rechtsboven: {{gate_code}} 2) kleedkamer (deur {{locker_door}}): {{door_code_gear}}. Teken het protocol op het scherm en bevestig daar ook het terugbrengen. Was de poort dicht? Bij vertrek op slot, sleutel terug, code verdraaien. MOTO GO 24$t$),
  ('door_codes_gear_only', 'Přístupový kód – výpůjčka výbavy (šatna)', 'es', $t$Alquiler de equipo {{booking_number}} ({{valid_from}}–{{valid_to}}): código del vestuario {{door_code_gear}}. Los pasos de recogida y devolución están en el e-mail con los códigos. MOTO GO 24$t$),
  ('door_codes_gate_gear_only', 'Přístupové kódy – výpůjčka výbavy (brána, šatna)', 'es', $t$Alquiler de equipo {{booking_number}} ({{valid_from}}–{{valid_to}}): 1) portón – caja sup. dcha.: {{gate_code}} 2) vestuario (puerta {{locker_door}}): {{door_code_gear}}. Firma el protocolo en la pantalla y confirma allí también la devolución. Si el portón estaba cerrado, al salir ponle el candado, devuelve la llave y gira los números. MOTO GO 24$t$),
  ('door_codes_gear_only', 'Přístupový kód – výpůjčka výbavy (šatna)', 'fr', $t$Location d'équipement {{booking_number}} ({{valid_from}}-{{valid_to}}) : code du vestiaire {{door_code_gear}}. Les étapes de retrait et de retour sont dans l'e-mail avec les codes. MOTO GO 24$t$),
  ('door_codes_gate_gear_only', 'Přístupové kódy – výpůjčka výbavy (brána, šatna)', 'fr', $t$Location d'équipement {{booking_number}} ({{valid_from}}-{{valid_to}}) : 1) portail, boîte du haut à droite : {{gate_code}} 2) vestiaire (porte {{locker_door}}) : {{door_code_gear}}. Signe le protocole sur l'écran et confirme-y aussi le retour. Portail fermé ? En partant, referme-le au cadenas, remets la clé, brouille le code. MOTO GO 24$t$),
  ('door_codes_gear_only', 'Přístupový kód – výpůjčka výbavy (šatna)', 'pl', $t$Wypożyczenie sprzętu {{booking_number}} ({{valid_from}}–{{valid_to}}): kod szatni {{door_code_gear}}. Jak odebrać i zwrócić sprzęt, znajdziesz w e-mailu z kodami. MOTO GO 24$t$),
  ('door_codes_gate_gear_only', 'Přístupové kódy – výpůjčka výbavy (brána, šatna)', 'pl', $t$Wypożyczenie sprzętu {{booking_number}} ({{valid_from}}–{{valid_to}}): 1) brama – górna skrytka z prawej: {{gate_code}} 2) szatnia (drzwi {{locker_door}}): {{door_code_gear}}. Podpisz protokół na wyświetlaczu i tam też potwierdź zwrot. Zamkniętą bramę po wyjeździe zamknij na kłódkę, klucz odłóż, szyfr przekręć. MOTO GO 24$t$),
  ('door_codes_gear_only', 'Přístupový kód – výpůjčka výbavy (šatna)', 'uk', $t$Оренда екіпірування {{booking_number}} ({{valid_from}}–{{valid_to}}): код роздягальні {{door_code_gear}}. Як отримати й повернути — у листі з кодами. MOTO GO 24$t$),
  ('door_codes_gate_gear_only', 'Přístupové kódy – výpůjčka výbavy (brána, šatna)', 'uk', $t$Оренда екіпірування {{booking_number}} ({{valid_from}}–{{valid_to}}): 1) ворота – верхня скринька справа: {{gate_code}} 2) роздягальня (двері {{locker_door}}): {{door_code_gear}}. Підпиши протокол на дисплеї й там же підтверди повернення. Зачинені ворота після відʼїзду замкни, ключ поверни, код збий. MOTO GO 24$t$),
  -- FIX-R1: obslužná pobočka bez brány (en/de/nl/fr jen GSM-7)
  ('door_codes_gear_staffed', 'Kód výpůjčky výbavy (obslužná pobočka)', 'cs', $t$Výpůjčka výbavy {{booking_number}} ({{valid_from}}–{{valid_to}}): kód výpůjčky {{door_code_gear}} — při převzetí ho nahlas obsluze na pobočce. MOTO GO 24$t$),
  ('door_codes_gear_staffed', 'Kód výpůjčky výbavy (obslužná pobočka)', 'en', $t$Gear rental {{booking_number}} ({{valid_from}}-{{valid_to}}): rental code {{door_code_gear}} - tell it to the staff at the branch when you pick up the gear. MOTO GO 24$t$),
  ('door_codes_gear_staffed', 'Kód výpůjčky výbavy (obslužná pobočka)', 'de', $t$Ausrüstungsverleih {{booking_number}} ({{valid_from}}-{{valid_to}}): Verleihcode {{door_code_gear}} - nenne ihn bei der Abholung dem Personal in der Filiale. MOTO GO 24$t$),
  ('door_codes_gear_staffed', 'Kód výpůjčky výbavy (obslužná pobočka)', 'nl', $t$Huur uitrusting {{booking_number}} ({{valid_from}}-{{valid_to}}): huurcode {{door_code_gear}} - geef hem bij het ophalen door aan het personeel van de vestiging. MOTO GO 24$t$),
  ('door_codes_gear_staffed', 'Kód výpůjčky výbavy (obslužná pobočka)', 'es', $t$Alquiler de equipo {{booking_number}} ({{valid_from}}–{{valid_to}}): código de alquiler {{door_code_gear}} — al recoger el equipo, díselo al personal de la sucursal. MOTO GO 24$t$),
  ('door_codes_gear_staffed', 'Kód výpůjčky výbavy (obslužná pobočka)', 'fr', $t$Location d'équipement {{booking_number}} ({{valid_from}}-{{valid_to}}) : code de location {{door_code_gear}} - donne-le au personnel de l'agence au retrait. MOTO GO 24$t$),
  ('door_codes_gear_staffed', 'Kód výpůjčky výbavy (obslužná pobočka)', 'pl', $t$Wypożyczenie sprzętu {{booking_number}} ({{valid_from}}–{{valid_to}}): kod wypożyczenia {{door_code_gear}} — przy odbiorze podaj go obsłudze w oddziale. MOTO GO 24$t$),
  ('door_codes_gear_staffed', 'Kód výpůjčky výbavy (obslužná pobočka)', 'uk', $t$Оренда екіпірування {{booking_number}} ({{valid_from}}–{{valid_to}}): код оренди {{door_code_gear}} — під час отримання назви його персоналу у філії. MOTO GO 24$t$)
) AS t(slug, name, lang, body)
CROSS JOIN (VALUES ('sms'), ('whatsapp')) AS c(channel)
ON CONFLICT (slug, channel, language) DO NOTHING;

NOTIFY pgrst, 'reload schema';
