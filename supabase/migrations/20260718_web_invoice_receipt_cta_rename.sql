-- =============================================================================
-- MIGRACE 2026-07-18: web_invoice_payment_receipt — CTA „Nahrát doklady" → „Doplnit údaje"
-- =============================================================================
-- V novém web flow (platba PŘED doklady) je v kroku dokladů POVINNÉ vyplnit ČÍSLA
-- dokladů/ŘP (jdou do smlouvy), zatímco SCANY (fotky) jsou NEPOVINNÉ. Tlačítko
-- „Nahrát doklady" tedy neodpovídá skutečné akci — přesnější je „Doplnit údaje".
-- Mění se JEN text tlačítka v šabloně `web_invoice_payment_receipt`, zbytek beze změny.
--
-- Šablonu seedovala migrace 20260713_web_reserved_complete_for_verified.sql; tato
-- migrace jen přejmenuje CTA na živé DB řádce (targeted replace). Musí se aplikovat
-- AŽ PO 20260713 (proto pozdější název souboru), aby ji seed nepřepsal zpět.
-- Idempotentní: opakované spuštění nic nezmění (replace na už přejmenovaném textu = no-op).
-- POUZE WEB. Edge fn fallback (send-booking-email) přejmenován v témže commitu.
-- =============================================================================

-- 1) Tlačítko v těle šablony: „Nahrát doklady" → „Doplnit údaje"
UPDATE email_templates
   SET body_html = replace(body_html, '>Nahrát doklady</a>', '>Doplnit údaje</a>')
 WHERE slug = 'web_invoice_payment_receipt'
   AND body_html LIKE '%>Nahrát doklady</a>%';

-- 2) Zneplatnit cache přeložených verzí těla → send-booking-email si CTA znovu
--    přeloží do ostatních jazyků při nejbližším odeslání (jinak by zůstal starý překlad).
UPDATE email_templates
   SET body_translations = '{}'::jsonb
 WHERE slug = 'web_invoice_payment_receipt';

NOTIFY pgrst, 'reload schema';
