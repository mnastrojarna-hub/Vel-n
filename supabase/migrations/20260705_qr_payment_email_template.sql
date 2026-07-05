-- =============================================================================
-- MIGRACE 2026-07-05: E-mailová šablona pro platbu QR / bankovním převodem
--
-- Když zákazník na webu (krok 2 rezervace) zvolí „Platba QR kódem / převodem na
-- účet", edge fn `qr-payment` mu pošle platební údaje (QR + účet + IBAN + VS) a
-- ZF v příloze. Dosud se HTML skládalo NAPEVNO v edge funkci (mimo šablony Velína).
--
-- Tato migrace zavádí editovatelnou šablonu `booking_qr_payment` (Velín →
-- Dokumenty → E-mailové šablony). Obsah je 1:1 s mailem, který dosud chodil.
-- Edge fn `qr-payment` volá send-email s `template_slug='booking_qr_payment'`
-- a placeholdery; při chybějící/vypnuté šabloně má fallback na stejné inline HTML,
-- takže mail vždy odejde. Zálohová faktura (ZF) v příloze zůstává beze změny.
--
-- Placeholdery:
--   {{lead}}          — „Jméno, děkujeme" nebo „Děkujeme" (skládá edge fn)
--   {{booking_number}}— krátká reference rezervace (#XXXXXXXX)
--   {{qr_url}}        — URL QR kódu (SPD)
--   {{amount}}        — částka vč. „Kč"
--   {{account}} {{iban}} {{bank}} {{vs}} — platební údaje
--   {{invoice_suffix}}— „ (č. ZF)" nebo prázdné
--
-- Idempotentní (ON CONFLICT (slug) DO NOTHING) — neuvádí ručně upravený text
-- ve Velíně zpět na default.
-- =============================================================================

INSERT INTO email_templates (slug, name, subject, body_html, active, attachments)
VALUES (
  'booking_qr_payment',
  'Platba QR / bankovní převod',
  'Platební údaje k rezervaci #{{booking_number}} — QR / bankovní převod',
  '<h2 style="margin:0 0 6px;font-size:20px;color:#0f1a14">Platební údaje — QR / bankovní převod</h2>' ||
  '<p style="margin:0 0 16px;color:#374151;font-size:14px">{{lead}} za rezervaci <strong>#{{booking_number}}</strong>. Uhraďte prosím částku bankovním převodem nebo naskenováním QR kódu v mobilní bankovní aplikaci.</p>' ||
  '<div style="text-align:center;margin:0 0 16px"><img src="{{qr_url}}" alt="QR Platba" style="width:240px;height:240px;border:1px solid #e5e7eb;border-radius:12px"></div>' ||
  '<table style="width:100%;border-collapse:collapse;margin:0 0 14px">' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Částka</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:18px;font-variant-numeric:tabular-nums">{{amount}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Číslo účtu</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{account}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">IBAN</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{iban}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Banka</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{bank}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Variabilní symbol</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{vs}}</td></tr>' ||
  '</table>' ||
  '<p style="margin:0 0 10px;padding:12px 14px;background:#fef2f2;border-radius:10px;color:#b91c1c;font-weight:700;font-size:14px">⏱ Platbu prosím proveďte do 4 hodin. Pokud se do té doby nepřipíše, rezervace se automaticky zruší a termín se uvolní.</p>' ||
  '<p style="margin:0 0 6px;color:#374151;font-size:13px">Po připsání platby vám rezervaci potvrdíme a pošleme potvrzení s přístupovými údaji. Zálohovou fakturu najdete v příloze.{{invoice_suffix}}</p>' ||
  '<p style="margin:0;color:#6b7280;font-size:12px">Platíte-li raději kartou (okamžité potvrzení), můžete rezervaci dokončit online platbou v rezervačním formuláři.</p>',
  true,
  '[]'::jsonb
)
ON CONFLICT (slug) DO NOTHING;
