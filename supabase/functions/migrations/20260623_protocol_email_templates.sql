-- =============================================================================
-- MIGRACE 2026-06-23: E-mailové šablony pro odeslání předávacího protokolu
--                     a protokolu o poškození zákazníkovi z Velína.
--
-- Po uložení elektronického protokolu (BookingDocumentsTab → ElectronicProtocolModal)
-- nabídne Velín odeslat protokol zákazníkovi e-mailem. Edge fn `send-email` vyzvedne
-- tuto šablonu podle slugu, vyrenderuje {{placeholdery}} a samotný protokol přiloží
-- v příloze (PDF/HTML přes `attachment_paths`). Sloupec `attachments` zde zůstává
-- prázdný — přílohu řídí volání send-email, ne synth attach z send-booking-email.
--
-- Šablony jsou editovatelné ve Velíně → Dokumenty → E-mailové šablony.
-- Idempotentní (ON CONFLICT (slug) DO NOTHING) — neuvádí existující ručně upravené
-- texty zpět na default.
-- =============================================================================

INSERT INTO email_templates (slug, name, subject, body_html, active, attachments)
VALUES
(
  'handover_protocol_sent',
  'Předávací protokol',
  'Předávací protokol — MOTO GO 24',
  '<h2 style="color:#1a8a18;font-size:18px;margin-top:0">Předávací protokol</h2>' ||
  '<p>Dobrý den {{customer_name}},</p>' ||
  '<p>v příloze Vám zasíláme předávací protokol k rezervaci <strong>č. {{booking_number}}</strong>.</p>' ||
  '<div style="background:#f1faf7;border:1px solid #d4e8e0;border-radius:12px;padding:16px;margin:20px 0">' ||
  '<table style="width:100%;border-collapse:collapse;font-size:14px;color:#374151">' ||
  '<tr><td style="padding:4px 0;font-weight:700">Motocykl:</td><td>{{moto}}</td></tr>' ||
  '<tr><td style="padding:4px 0;font-weight:700">Období pronájmu:</td><td>{{rental_period}}</td></tr>' ||
  '</table></div>' ||
  '<p>Protokol je elektronicky podepsán. V případě jakýchkoliv dotazů nás neváhejte kontaktovat.</p>',
  true,
  '[]'::jsonb
),
(
  'damage_protocol_sent',
  'Protokol o poškození',
  'Protokol o poškození — MOTO GO 24',
  '<h2 style="color:#dc2626;font-size:18px;margin-top:0">Protokol o poškození</h2>' ||
  '<p>Dobrý den {{customer_name}},</p>' ||
  '<p>v příloze Vám zasíláme protokol o poškození k rezervaci <strong>č. {{booking_number}}</strong>.</p>' ||
  '<div style="background:#fef2f2;border:1px solid #fca5a5;border-radius:12px;padding:16px;margin:20px 0">' ||
  '<table style="width:100%;border-collapse:collapse;font-size:14px;color:#374151">' ||
  '<tr><td style="padding:4px 0;font-weight:700">Motocykl:</td><td>{{moto}}</td></tr>' ||
  '<tr><td style="padding:4px 0;font-weight:700">Období pronájmu:</td><td>{{rental_period}}</td></tr>' ||
  '</table></div>' ||
  '<p>Protokol je elektronicky podepsán. V případě jakýchkoliv dotazů nás neváhejte kontaktovat.</p>',
  true,
  '[]'::jsonb
)
ON CONFLICT (slug) DO NOTHING;
