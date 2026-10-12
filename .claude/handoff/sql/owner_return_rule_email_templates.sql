-- DRAFT (NOT applied, NOT in git) — workstream ai-app-mail, 2026-10-11
-- Owner rule: Mezná (staffed, incl. return elsewhere) = no wash, no refuel;
-- Velké Němčice (self-service) = no full tank needed, but WASHED + reserve light NOT on.
-- The hardcoded fallback in send-booking-email/i18n.ts was fixed in code; the Velín DB templates
-- (email_templates booking_reserved / web_booking_reserved) take priority and are not readable
-- with the anon key — run the diagnostic first, then the targeted replace (idempotent, no-op
-- when the old paragraph is not there). Changed rows get body_translations = '{}' (re-translate,
-- same convention as 20261004g/20261005a).

-- 1) Diagnostic (read-only)
SELECT slug,
       substring(body_html from '[^<>]{0,80}(?:nad rezervou|kontrolka rezervy|tankov|[Mm]ytí|úklid)[^<>]{0,200}') AS hit
FROM public.email_templates
WHERE body_html ~* '(nad rezervou|kontrolka rezervy|tankov|mytí|úklid)';

-- 2) Targeted replace — formal variant (vykání, as in the code fallback)
UPDATE public.email_templates
SET body_html = regexp_replace(body_html,
      'Motorku stačí vrátit s palivem nad rezervou \(kontrolka rezervy nesvítí\)\. Mytí ani úklid neřešte — to je naše práce\.( Při vrácení s prázdnou nádrží účtujeme dotankování \+ servisní poplatek dle VOP\.)?',
      'Na obslužné pobočce v Mezné (i při vrácení na jiném sjednaném místě) motorku nemusíte tankovat ani mýt — to je naše práce. Na samoobslužné pobočce ve Velkých Němčicích ji prosím vraťte umytou a tak, aby nesvítila kontrolka rezervy; plná nádrž není potřeba.'),
    body_translations = '{}'::jsonb
WHERE body_html ~ 'Motorku stačí vrátit s palivem nad rezervou \(kontrolka rezervy nesvítí\)\. Mytí ani úklid neřešte';

-- 3) Targeted replace — informal variant (tykání)
UPDATE public.email_templates
SET body_html = regexp_replace(body_html,
      'Motorku stačí vrátit s palivem nad rezervou \(kontrolka rezervy nesvítí\)\. Mytí ani úklid neřeš( — to je naše práce)?\.( Při vrácení s prázdnou nádrží účtujeme dotankování \+ servisní poplatek dle VOP\.)?',
      'Na obslužné pobočce v Mezné (i při vrácení na jiném sjednaném místě) motorku nemusíš tankovat ani mýt — to je naše práce. Na samoobslužné pobočce ve Velkých Němčicích ji prosím vrať umytou a tak, aby nesvítila kontrolka rezervy; plná nádrž není potřeba.'),
    body_translations = '{}'::jsonb
WHERE body_html ~ 'Motorku stačí vrátit s palivem nad rezervou \(kontrolka rezervy nesvítí\)\. Mytí ani úklid neřeš[ .—]';
-- Any other wording found by (1) → edit by hand in Velín (Šablony e-mailů); STATE_1 email_templates note.
