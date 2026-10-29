// ===== _tests/gear_flow_runner_test.ts =====
// EDGE-B (2026-10-23): flow testy celých handlerů (gear_flow_test.ts + gear_payment_flow_test.ts +
// gear_refund_flow_test.ts — platby a vratky na kódu main po hotfixu #2213) potřebují import mapu
// (gear-flow-map.json: serve zachytí handler, supabase-js = LooseDb). Aby je pokrylo i běžné
// `deno test --allow-all --no-check supabase/functions/_tests/`, spustí je tenhle test v PODPROCESU
// s import mapou — podproces má i vlastní env (SUPABASE_URL flow testů neprosákne do ostatních).
// Při běhu s import mapou (flow testy běží přímo) nebo bez oprávnění `run` se přeskočí.
const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/@supabase/supabase-js@2').startsWith('file:') } catch { return false } })()
const CAN_RUN = (() => { try { return Deno.permissions.querySync({ name: 'run' }).state === 'granted' } catch { return false } })()
const FLOW_FILES = ['./gear_flow_test.ts', './gear_payment_flow_test.ts', './gear_refund_flow_test.ts']
const FLOW_MIN = 8 + 9 + 5 // počet flow testů v FLOW_FILES (ubyl-li by některý, runner selže)

Deno.test({ name: 'gear flow testy celých handlerů (podproces s import mapou gear-flow-map.json)', ignore: MAPPED || !CAN_RUN, fn: async () => {
  const p = (f: string) => new URL(f, import.meta.url).pathname
  const out = await new Deno.Command(Deno.execPath(), {
    args: ['test', '--allow-all', '--no-check', `--import-map=${p('./gear-flow-map.json')}`, ...FLOW_FILES.map(p)],
    env: { NO_COLOR: '1' }, stdout: 'piped', stderr: 'piped',
  }).output()
  const txt = new TextDecoder().decode(out.stdout) + '\n' + new TextDecoder().decode(out.stderr)
  const m = /(\d+) passed \| (\d+) failed(?: \| (\d+) ignored)?/.exec(txt)
  if (!out.success || !m || Number(m[1]) < FLOW_MIN || m[2] !== '0' || Number(m[3] || 0) > 0) {
    throw new Error(`gear flow testy neprošly (exit ${out.code}):\n${txt.slice(-6000)}`)
  }
} })
