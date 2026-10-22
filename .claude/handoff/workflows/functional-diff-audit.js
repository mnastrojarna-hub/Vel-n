export const meta = {
  name: 'functional-diff-audit',
  description: 'Pre-release safety gate: list every FUNCTIONAL change (non-cosmetic) on the branch since the last release, map each to an explicit owner request, revert/flag anything unrequested, and run the full test suites',
  phases: [
    { title: 'Diff', detail: 'classify every changed file/hunk' },
    { title: 'Judge', detail: 'requested vs unrequested, risk' },
    { title: 'Act', detail: 'revert unrequested, report' },
  ],
}
const S = '/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad'
const FA = S + '/funcaudit'
const CTX = [
  'CONTEXT: Repo /home/user/Vel-n, branch claude/moto-go-mobile-conversion-gqg5qo. Owner (verbatim, 2026-10-16): "ale pozor jinak nic co se týká funkčnosti nic neměň, to bylo celkem odladěný, tak ne že to rozbiješ". The app in the field is 4.1.3 (Android) - find the commit it was built from (pubspec version history: git log -S "version: 4.1.3" -- Motogo-app-main/motogo-app-flutter/pubspec.yaml) and use it as BASE for the app; for edge/web/Velín use origin/main at the start of the owner-answer work (cabd5ccb) as BASE, plus everything already merged since then counts as already reviewed live.',
  'EXPLICIT OWNER REQUESTS that justify functional changes (anything else is unrequested): return/fuel rule texts; banner on web; FAQ app stores; home step 3; header edit-reservation button; ride rating -> Google review + "Napiš nám přímo, co máme zlepšit" into Velín tab Hodnocení; Google-only review links; meaningful error/result states + no hangs + visible back everywhere; payments D1-D6 (rounding to 15 Kč app+web, restore-and-pay fix, process-payment hardening against double charges, precise errors without contact, swap completion with retry, swap conflict refund, storno pro rata); v2 UI in Android behind the app_v2_ui kill-switch (look only); sales copy and disclosure in v2.',
  'RULES: no git write commands except that you MAY revert unrequested hunks in the working tree (git checkout -p is interactive - use patch files: git diff BASE -- <file> > x.patch, edit, git apply -R) ONLY when the change is clearly unrequested AND not needed by a requested change; otherwise report it. Run: flutter analyze + full flutter test in the Android tree and in a scratch copy of the iOS tree; deno check/test for changed edge functions; php -l + a 8-language smoke of the main web pages; Velín build. Tools: ' + S + '/sdk/flutter/bin/flutter, ' + S + '/denobin/deno (DENO_DIR=' + S + '/denocache), PHP server with ' + S + '/router.php, ' + S + '/velin-build.',
].join('\n')
phase('Diff')
const parts = ['app-android-non-v2', 'app-ios', 'edge+sql-drafts', 'web+velin']
const diffs = await parallel(parts.map(p => () => agent(CTX + `\n\nTASK diff:${p}. List every changed file in your part vs BASE (for app-android ignore lib/core/v2/**, lib/features/*/v2/**, booking_v2_* and translations_ext_5X_* except where old screens got V-seams/branches - include those seams). For each hunk classify: cosmetic (text/style/layout) vs FUNCTIONAL (logic, data, flow, validation, navigation, network, storage), and for functional ones name the owner request it serves (from the list) or "UNREQUESTED", plus a risk note. Write ${FA}/${p}.md and return it.`, { label: 'diff:' + p, phase: 'Diff' })))
phase('Judge')
const judge = await agent(CTX + '\n\nDIFF REPORTS:\n' + diffs.join('\n\n----\n\n') + `\n\nTASK judge. For every FUNCTIONAL hunk decide: KEEP (serves a request, risk acceptable - say how it is verified/tested), KEEP-BUT-RISKY (serves a request but needs an extra test - write the test now), or REVERT (unrequested and not required by a requested change). Write ${FA}/decisions.md. Return the decision list.`, { label: 'judge', phase: 'Judge' })
phase('Act')
const act = await agent(CTX + '\n\nDECISIONS:\n' + judge + `\n\nTASK act. Apply the REVERT decisions carefully (keep both app trees consistent; keep requested changes intact), add the missing tests for KEEP-BUT-RISKY, then run every check listed in RULES and report results, what was reverted and what remains for the owner to decide.`, { label: 'act', phase: 'Act' })
return { diffs, judge, act }
