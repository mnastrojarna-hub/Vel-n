-- Syntetické šablony e-mailů (živé nejsou čitelné anon klíčem) – jen pro test skupiny t.
INSERT INTO public.email_templates (id, slug, name, subject, body_html, body_translations) VALUES
('a1000000-0000-0000-0000-0000000000a1','booking_reserved','T1','Rezervace',
 '<p>Dobrý den,</p><h3 style="x">Vrácení motorky</h3><p>Motorku stačí vrátit s palivem nad rezervou (kontrolka rezervy nesvítí). Mytí&nbsp;ani úklid neřešte &mdash; to je naše práce. Při vrácení s prázdnou nádrží účtujeme dotankování + servisní poplatek dle VOP.</p>',
 '{"en":{"x":1}}'),
('a2000000-0000-0000-0000-0000000000a2','web_booking_reserved','T2','Rezervace web',
 E'<h3>Vrácení motorky</h3><p>Motorku stačí vrátit s palivem nad rezervou (kontrolka rezervy nesvítí).\nMytí ani úklid neřeš. Text. Motorku stačí vrátit s palivem nad rezervou (kontrolka rezervy nesvítí). Mytí ani úklid neřeš – to je naše práce.</p>',
 '{}'),
('a3000000-0000-0000-0000-0000000000a3','booking_completed','T3','Hotovo',
 '<p>Na obslužné pobočce v Mezné (i při vrácení na jiném sjednaném místě) motorku nemusíte tankovat ani mýt &ndash; to je naše práce. Na samoobslužné pobočce ve Velkých Němčicích ji prosím vraťte umytou a tak, aby nesvítila kontrolka rezervy; plná nádrž není potřeba.</p>',
 '{}'),
('a4000000-0000-0000-0000-0000000000a4','other_template','T4','Jiná','<p>Nic o palivu. Aplikace na Google Play.</p>','{}'),
('a5000000-0000-0000-0000-0000000000a5','reminder','T5','Připomínka','<p>Vraťte motorku natankovanou.</p>','{}')
ON CONFLICT (slug) DO NOTHING;
