# owner-ai-app-mail (2026-10-11): return rule in AI agents, MCP, booking e-mail, app, kiosk

Rule: Mezná (obslužná, also return elsewhere / pick-up from address) = no wash, no refuel.
Velké Němčice (samoobslužná) = full tank not needed, but WASHED + fuel reserve light NOT on.
Wording aligned with the web workstream (lang/*.php rez.return.stateText, data/pobocky.php).

## Files changed
- supabase/functions/_shared/agent-knowledge/owner-facts.ts — VRÁCENÍ fact (+ header comment)
- supabase/functions/_shared/agent-knowledge/hard-rules.ts — bod 32 (VN return; staffed return + "nemusí mýt ani tankovat"), bod 33
- supabase/functions/_shared/agent-knowledge/branch-facts.ts — BRANCHES_TOOL_NOTICE_CS tail + branchModeCs (both modes carry the return condition; also used by mcp-server mode_cs, ai-moto-agent context)
- supabase/functions/_shared/agent-knowledge/company-brain.ts — pointer line ("tankování, mytí a kontrolka rezervy")
- supabase/functions/ai-moto-agent/booking-context.ts — self-service step 6 (staffed step 5 already correct)
- supabase/functions/mcp-server/facts.ts — "Return conditions?" (EN by design)
- supabase/functions/send-booking-email/i18n.ts — booking_reserved: CS paragraph replaced; same "return" h3+p added to en/de/nl/es/fr/pl/uk (they had none)
- supabase/functions/translate-pages-master/master_cs.ts — only the 5 rule leaves, values = output of build_master_json.php from current web sources (full regen would churn unrelated stale keys)
- Motogo-app-main/motogo-app-flutter{,-ios}/lib/features/branches/branches_info_provider.dart — branches.0/1.steps = data/pobocky.php (byte-equal)
- NOT changed: ai-public-agent/index.ts, ai-moto-agent/public-tools.ts (no rule statement), app i18n (no rule), kiosk UI (return flow doesn't state rule → no version bump)

## Verification
- deno check error counts before→after: ai-public-agent 1→1, ai-moto-agent 1→1, ai-customer-messages-suggest 1→1, mcp-server 0→0, public-api 0→0, send-booking-email 0→0, translate-pages-master 2→2
- renderEmail all slugs × 8 langs HEAD vs now: only booking_reserved differs (rule paragraph); rule regexes pass in all 8 langs
- flutter analyze: Android 193 / iOS 184 issues, 0 errors (= baseline); diff -rq lib = whitelist only

## Left for others
- DB email_templates (booking_reserved / web_booking_reserved) — draft sql/owner_return_rule_email_templates.sql (diagnostic + idempotent replace)
- DB faq_items e6df7d9f / 02b6cfc8, cms_variables, pages_overlay — see owner-webtexts.md
- velin/src/pages/cms/webTextsPobocky.js mirror of pobocky steps (Velín workstream)

## Open questions for owner
1. Mezná: must the reserve light be off? (VOP čl. 5 l) + nájemní smlouva: reserve must not be on at ALL branches)
2. Old CS mail sentence "Při vrácení s prázdnou nádrží účtujeme dotankování + servisní poplatek dle VOP" dropped (no such fee in VOP, contradicts Mezná). Any fee for VN return unwashed / reserve on?
3. VOP čl. 5 l) "nemusí předmět nájmu předávat umytý" contradicts VN washing duty.

## QA review (adversarial, 2026-10-11)
Fixed:
- master_cs.ts: missed 6th rule leaf jak_pujcit_vraceni_pujcovna.cta.text ("Bez kauce, bez mytí, bez tankování." → web's "Bez kauce, bez tankování, v Mezné i bez mytí."); scratch regen of build_master_json.php now has 0 rule-leaf diffs (122 unrelated stale leaves remain by design).
- send-booking-email/i18n.ts booking_reserved: de "volltanken" → "Volltanken"; fr "restitution à un autre lieu" → "dans un autre lieu"; pl "oddaj go umytego" (ungrammatical) → "oddaj motocykl umyty".
- owner-facts.ts VRÁCENÍ: + "answer from this point even though VOP čl. 5 l) / contract are still generic" (get_legal_document returns VOP 5 l) "nemusí předávat umytý" which would contradict VN washing; LEGAL_SOURCE_RULES gives VOP top priority otherwise).
- sql/owner_return_rule_email_templates.sql: diagnostic substring used a capturing group → returned only the matched word; now (?:…) shows context. Tested on local PG stub (formal+informal rows, 2 runs idempotent).
- NEW sql/owner_return_rule_pobocky_steps.sql: live cms_variables web.pobocky.branches.0/1.steps (old text, translations {}) override data/pobocky.php AND the app defaults → without it the app (all langs) and CS /pobocky never show the rule; m3a does not cover them. Tested on live rows: 2 rows changed, byte-equal to data/pobocky.php, 2nd run no-op.
Verified: deno check TS counts 1/1/1/0/0/0/2 (= baseline); renderEmail all 12 slugs × 8 langs × 2 var modes vs cabd5ccb → only booking_reserved differs; flutter analyze Android 193 / iOS 184, 0 errors; diff -rq lib = whitelist; reviews untouched; kiosk UI states no wash/fuel rule.
Residual: app Pobočky screen has CS-only defaults and empty DB translations → non-CS app users see Czech (pre-existing); velin webTextsPobocky.js drift; DB FAQ/email templates/cms rows until SQL applied; owner questions 1–3 (Mezná reserve light, VOP 5 l), fee).
