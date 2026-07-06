-- =============================================================================
-- MIGRACE 2026-07-17: Editovatelná Velín šablona „Nahrajte doklady" (missing_docs)
-- =============================================================================
-- Připomínka `booking_missing_docs` existovala dosud JEN jako hardcoded fallback
-- v edge fn `send-booking-email` (index.ts) → nešla editovat ve Velíně
-- (EmailTemplatesTab čte tabulku `email_templates`). Tato migrace zakládá
-- editovatelné DB šablony `booking_missing_docs` + web variantu
-- `web_booking_missing_docs`, aby text i tlačítko šly upravovat ve Velíně.
--
-- Chování beze změny: resolveSlug(type='booking_missing_docs', source) přednostně
-- načte DB řádek (web → web_booking_missing_docs, jinak booking_missing_docs);
-- když by řádek chyběl, spadne na dosavadní hardcoded fallback. Tlačítko
-- „Nahrát doklady" vede na {{docs_url}} (send-booking-email dopočítá
-- /rezervace?resume=<id>). Bez příloh (attachments=[]) — je to jen připomínka.
-- Idempotentní (ON CONFLICT DO UPDATE). POUZE připomínka; platby se netýká.
-- =============================================================================

INSERT INTO email_templates (slug, name, subject, body_html, active, attachments)
VALUES (
  'booking_missing_docs',
  'Připomínka — nahrajte doklady (po platbě)',
  'Nahrajte doklady k rezervaci č. {{booking_number}} — MotoGo24',
  '<p>Dobrý den,</p>' ||
  '<p>vaše rezervace č. <strong>#{{booking_number}}</strong> motocyklu <strong>{{motorcycle}}</strong> na <strong>{{start_date}} – {{end_date}}</strong> je zaplacená — děkujeme!</p>' ||
  '<p>Abychom vám mohli předat motorku a poslat přístupové kódy, potřebujeme ještě ověřit vaše doklady (občanku/pas + řidičský průkaz). Zabere to jen chvilku.</p>' ||
  '<div style="text-align:center;margin:24px 0"><a href="{{docs_url}}" style="display:inline-block;background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px">Nahrát doklady</a></div>' ||
  '<p>Bez ověření dokladů vám nemůžeme poslat přístupové kódy předem — doklady bychom pak museli zkontrolovat osobně až na pobočce.</p>' ||
  '<p>Tým MotoGo24</p>',
  true,
  '[]'::jsonb
)
ON CONFLICT (slug) DO UPDATE SET
  subject     = EXCLUDED.subject,
  body_html   = EXCLUDED.body_html,
  attachments = EXCLUDED.attachments,
  active      = true;

INSERT INTO email_templates (slug, name, subject, body_html, active, attachments)
VALUES (
  'web_booking_missing_docs',
  'Web — připomínka nahrajte doklady (po platbě)',
  'Nahrajte doklady k rezervaci #{{booking_number}} — MotoGo24',
  '<p>Dobrý den,</p>' ||
  '<p>vaše rezervace č. <strong>#{{booking_number}}</strong> motocyklu <strong>{{motorcycle}}</strong> na <strong>{{start_date}} – {{end_date}}</strong> je zaplacená — děkujeme!</p>' ||
  '<p>Abychom vám mohli předat motorku a poslat přístupové kódy, potřebujeme ještě ověřit vaše doklady (občanku/pas + řidičský průkaz). Zabere to jen chvilku.</p>' ||
  '<div style="text-align:center;margin:24px 0"><a href="{{docs_url}}" style="display:inline-block;background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px">Nahrát doklady</a></div>' ||
  '<p>Bez ověření dokladů vám nemůžeme poslat přístupové kódy předem — doklady bychom pak museli zkontrolovat osobně až na pobočce.</p>' ||
  '<p>Tým MotoGo24</p>',
  true,
  '[]'::jsonb
)
ON CONFLICT (slug) DO UPDATE SET
  subject     = EXCLUDED.subject,
  body_html   = EXCLUDED.body_html,
  attachments = EXCLUDED.attachments,
  active      = true;

NOTIFY pgrst, 'reload schema';
