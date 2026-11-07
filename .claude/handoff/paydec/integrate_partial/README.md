# Rozpracované sloučení hotfixu storna (#2221) do vývojové větve — 2026-10-30 ~05:30 UTC

Pozastaveno na pokyn majitele uprostřed kroku „integrate“ (workflow payments-integrate-verify, run wf_2d8d72a7-4b3).
Stav v době zastavení: `git merge --no-commit origin/claude/hotfix-storno-refund-gqg5qo` rozpracovaný, nevyřešený konflikt
jen v `supabase/functions/process-refund/index.ts`; agent přidal `process-refund/cancel-once-pool.ts`,
`webhook-receiver/cancel-mail-amount.ts`, upravil `_shared/booking-intents.ts`, `process-refund/other-intents.ts`,
`_tests/f1_payments_test.ts` (časově závislé testy). Merge byl přerušen (`git merge --abort`), soubory v tomto stavu jsou
v `files.tgz` (cesty relativně ke kořeni repa) — jen jako podklad, NEOVĚŘENO.

Navázání: nejjednodušší je spustit znovu skript `workflows/payments-integrate-verify-wf_2d8d72a7-4b3.js`
(nový běh; v jeho kroku integrate může agent vyjít z tohoto archivu). Pokud mezitím majitel mergne PR #2221 do main,
stačí `git merge origin/main` místo hotfix větve.
