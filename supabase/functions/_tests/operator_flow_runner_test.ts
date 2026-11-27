// ===== _tests/operator_flow_runner_test.ts =====
// Změna provozovatele (2026-11): flow testy celých handlerů potřebují import mapu
//   • operator_flow_test.ts        (generate-invoice, generate-document, qr-payment) → gear-flow-map.json
//   • operator_refund_flow_test.ts (process-refund — dobropis)                      → storno-flow-map.json
// Aby je pokrylo i běžné `deno test --allow-all --no-check supabase/functions/_tests/`, spustí je tenhle
// test v PODPROCESECH s příslušnou mapou. Při běhu s import mapou nebo bez oprávnění `run` se přeskočí.
const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/@supabase/supabase-js@2').startsWith('file:') } catch { return false } })()
const CAN_RUN = (() => { try { return Deno.permissions.querySync({ name: 'run' }).state === 'granted' } catch { return false } })()
const RUNS: Array<{ map: string; file: string; min: number }> = [
  { map: './gear-flow-map.json', file: './operator_flow_test.ts', min: 11 },
  { map: './storno-flow-map.json', file: './operator_refund_flow_test.ts', min: 4 },
]

for (const r of RUNS) {
  Deno.test({ name: `provozovatel: flow testy ${r.file} (podproces s import mapou ${r.map})`, ignore: MAPPED || !CAN_RUN, fn: async () => {
    const p = (f: string) => new URL(f, import.meta.url).pathname
    const out = await new Deno.Command(Deno.execPath(), {
      args: ['test', '--allow-all', '--no-check', `--import-map=${p(r.map)}`, p(r.file)],
      env: { NO_COLOR: '1' }, stdout: 'piped', stderr: 'piped',
    }).output()
    const txt = new TextDecoder().decode(out.stdout) + '\n' + new TextDecoder().decode(out.stderr)
    const m = /(\d+) passed \| (\d+) failed(?: \| (\d+) ignored)?/.exec(txt)
    if (!out.success || !m || Number(m[1]) < r.min || m[2] !== '0' || Number(m[3] || 0) > 0) {
      throw new Error(`flow testy ${r.file} neprošly (exit ${out.code}):\n${txt.slice(-6000)}`)
    }
  } })
}
