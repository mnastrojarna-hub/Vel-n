-- =============================================================================
-- NÁVRH (DRAFT, není v repu) 2026-11-30e: e-mailové šablony výzvy k platbě QR / převodem
-- pro DÁRKOVÝ POUKAZ (objednávku e-shopu) a DOPLATEK úpravy rezervace z webu.
--
-- Vzhled a placeholdery 1:1 se šablonou `booking_qr_payment` (20260705) — {{lead}}, {{qr_url}},
-- {{amount}}, {{account}}, {{iban}}, {{bank}}, {{vs}}, {{invoice_suffix}} + nově {{order_number}},
-- {{booking_number}}, {{deadline}} (text lhůty skládá edge funkce v jazyce zákazníka).
-- Účet, IBAN a název banky dosazuje edge funkce VŽDY z app_settings.company_info
-- (_shared/company.ts) — v šabloně žádné číslo účtu není.
-- Texty jsou česky; ostatních 7 jazyků přeloží send-email při prvním odeslání a uloží
-- (stejně jako u booking_qr_payment). Editovatelné ve Velínu (Dokumenty → E-mailové šablony).
-- Idempotentní (ON CONFLICT (slug) DO NOTHING — ručně upravený text se nepřepíše).
-- STATE soubory: 6 (changelog); seznam šablon ve STATE_5, pokud tam je veden.
-- =============================================================================

INSERT INTO email_templates (slug, name, subject, body_html, active, attachments)
VALUES (
  'shop_qr_payment',
  'Platba QR / převod — dárkový poukaz a e-shop',
  'Platební údaje k objednávce {{order_number}} — QR / bankovní převod',
  '<h2 style="margin:0 0 6px;font-size:20px;color:#0f1a14">Platební údaje — QR / bankovní převod</h2>' ||
  '<p style="margin:0 0 16px;color:#374151;font-size:14px">{{lead}} za objednávku <strong>{{order_number}}</strong>. Uhraďte prosím částku bankovním převodem nebo naskenováním QR kódu v mobilní bankovní aplikaci.</p>' ||
  '<div style="text-align:center;margin:0 0 16px"><img src="{{qr_url}}" alt="QR Platba" style="width:240px;height:240px;border:1px solid #e5e7eb;border-radius:12px"></div>' ||
  '<table style="width:100%;border-collapse:collapse;margin:0 0 14px">' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Částka</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:18px;font-variant-numeric:tabular-nums">{{amount}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Číslo účtu</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{account}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">IBAN</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{iban}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Banka</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{bank}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Variabilní symbol</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{vs}}</td></tr>' ||
  '</table>' ||
  '<p style="margin:0 0 10px;padding:12px 14px;background:#fef2f2;border-radius:10px;color:#b91c1c;font-weight:700;font-size:14px">⏱ {{deadline}}</p>' ||
  '<p style="margin:0 0 6px;color:#374151;font-size:13px">Jakmile platbu připíšeme (obvykle do několika minut), pošleme vám e-mailem potvrzení s dokladem — u dárkového poukazu i samotný poukaz. Zálohovou fakturu najdete v příloze.{{invoice_suffix}}</p>' ||
  '<p style="margin:0;color:#6b7280;font-size:12px">Platíte-li raději kartou, stačí objednávku na webu odeslat znovu a zvolit platbu kartou.</p>',
  true,
  '[]'::jsonb
)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO email_templates (slug, name, subject, body_html, active, attachments)
VALUES (
  'booking_change_qr_payment',
  'Platba QR / převod — doplatek za úpravu rezervace (web)',
  'Doplatek k rezervaci #{{booking_number}} — QR / bankovní převod',
  '<h2 style="margin:0 0 6px;font-size:20px;color:#0f1a14">Doplatek za úpravu rezervace — QR / bankovní převod</h2>' ||
  '<p style="margin:0 0 16px;color:#374151;font-size:14px">{{lead}} <strong>#{{booking_number}}</strong> se váže doplatek. Uhraďte ho prosím bankovním převodem nebo naskenováním QR kódu v mobilní bankovní aplikaci. <strong>Úpravu provedeme, jakmile platbu připíšeme</strong> — do té doby platí rezervace beze změny.</p>' ||
  '<div style="text-align:center;margin:0 0 16px"><img src="{{qr_url}}" alt="QR Platba" style="width:240px;height:240px;border:1px solid #e5e7eb;border-radius:12px"></div>' ||
  '<table style="width:100%;border-collapse:collapse;margin:0 0 14px">' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Částka</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:18px;font-variant-numeric:tabular-nums">{{amount}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Číslo účtu</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{account}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">IBAN</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{iban}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Banka</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{bank}}</td></tr>' ||
  '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">Variabilní symbol</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700;font-size:14px;font-variant-numeric:tabular-nums">{{vs}}</td></tr>' ||
  '</table>' ||
  '<p style="margin:0 0 10px;padding:12px 14px;background:#fef2f2;border-radius:10px;color:#b91c1c;font-weight:700;font-size:14px">⏱ {{deadline}}</p>' ||
  '<p style="margin:0;color:#374151;font-size:13px">Po připsání platby vám úpravu potvrdíme e-mailem spolu s dokladem o platbě a aktualizovanou smlouvou. Kdyby úpravu mezitím nešlo provést (například termín obsadila jiná rezervace), doplatek vám vrátíme a rezervace zůstane beze změny.</p>',
  true,
  '[]'::jsonb
)
ON CONFLICT (slug) DO NOTHING;
