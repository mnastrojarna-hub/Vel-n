#!/usr/bin/env node
// Stáhne VŠECHNY objekty ze VŠECH Supabase Storage bucketů (documents, media, sos-photos, ...)
// do lokální složky. Používá service_role klíč — spouštět POUZE v CI (GitHub Actions), nikdy na klientu.
//
// Použití: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node backup/storage-backup.mjs <out_dir>
//
// FIX 2026-09-21: stahování běželo STRIKTNĚ SEKVENČNĚ (jeden soubor po druhém,
// ~0,9 s/soubor) — bucket `documents` (2003 objektů) trval 29 minut a `media`
// (39 471 objektů) by trval ~9,5 hodiny, takže job vždy spadl na 120min timeoutu
// (běhy 207/208, 20. 9. 2026: konec s conclusion=cancelled, Storage krok 2 h bez
// jediného řádku v logu). Nově:
//   * paralelní stahování (pool, výchozí 16 souběžných),
//   * retry s exponenciálním odstupem na síťové chyby / 429 / 5xx — jeden výpadek
//     mezi 40 tisíci soubory dřív rovnou shodil celou zálohu (exit 2),
//   * průběh do logu každou minutu (i seznam bucketů se vypisuje průběžně),
//     aby bylo z logu poznat, jestli to jede, nebo visí.
// Ladění přes env: STORAGE_BACKUP_CONCURRENCY, STORAGE_BACKUP_RETRIES.

import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

const SUPABASE_URL = process.env.SUPABASE_URL?.replace(/\/$/, '');
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const OUT = process.argv[2] || 'storage-backup';
const CONCURRENCY = Math.max(1, Number(process.env.STORAGE_BACKUP_CONCURRENCY) || 16);
const RETRIES = Math.max(0, Number(process.env.STORAGE_BACKUP_RETRIES ?? 3));

if (!SUPABASE_URL || !KEY) {
  console.error('Chybí SUPABASE_URL nebo SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

const headers = { Authorization: `Bearer ${KEY}`, apikey: KEY };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Opakovat má smysl jen u dočasných chyb: síť spadla, rate-limit, chyba serveru.
// 401/403/404 se opakováním nespraví — ty vyhodíme hned.
function retriable(status) {
  return status === null || status === 408 || status === 429 || status >= 500;
}

async function api(path, init = {}) {
  let lastErr;
  for (let attempt = 0; attempt <= RETRIES; attempt += 1) {
    let status = null;
    try {
      const res = await fetch(`${SUPABASE_URL}${path}`, { ...init, headers: { ...headers, ...(init.headers || {}) } });
      if (res.ok) return res;
      status = res.status;
      lastErr = new Error(`${init.method || 'GET'} ${path} -> ${res.status} ${await res.text()}`);
    } catch (e) {
      lastErr = new Error(`${init.method || 'GET'} ${path} -> ${e.message}`);
    }
    if (!retriable(status) || attempt === RETRIES) break;
    await sleep(Math.min(8000, 500 * 2 ** attempt) + Math.floor(Math.random() * 250));
  }
  throw lastErr;
}

async function listBuckets() {
  return (await api('/storage/v1/bucket')).json();
}

// Rekurzivní výpis objektů (Storage API vrací "složky" jako položky s id=null)
async function listObjects(bucket, prefix = '') {
  const out = [];
  let offset = 0;
  const limit = 1000;
  for (;;) {
    const res = await api(`/storage/v1/object/list/${bucket}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefix, limit, offset, sortBy: { column: 'name', order: 'asc' } }),
    });
    const items = await res.json();
    for (const it of items) {
      const full = prefix ? `${prefix}/${it.name}` : it.name;
      if (it.id === null) {
        out.push(...(await listObjects(bucket, full)));
      } else {
        out.push(full);
      }
    }
    if (items.length < limit) break;
    offset += limit;
  }
  return out;
}

async function downloadObject(bucket, path, dest) {
  const res = await api(`/storage/v1/object/${bucket}/${encodeURIComponent(path).replace(/%2F/g, '/')}`);
  const buf = Buffer.from(await res.arrayBuffer());
  await mkdir(dirname(dest), { recursive: true });
  await writeFile(dest, buf);
  return buf.length;
}

// Pool N souběžných workerů nad jedním seznamem položek.
async function runPool(items, worker, concurrency) {
  let next = 0;
  const workers = Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    for (;;) {
      const i = next;
      next += 1;
      if (i >= items.length) return;
      await worker(items[i]);
    }
  });
  await Promise.all(workers);
}

let totalFiles = 0;
let totalBytes = 0;
let failed = 0;
const failures = [];

const buckets = await listBuckets();
console.log(`Buckety: ${buckets.map((b) => b.name).join(', ')} (souběžně ${CONCURRENCY}, retry ${RETRIES}×)`);

for (const b of buckets) {
  const t0 = Date.now();
  const objects = await listObjects(b.name);
  console.log(`[${b.name}] ${objects.length} objektů (výpis ${((Date.now() - t0) / 1000).toFixed(0)} s) — stahuji…`);

  let done = 0;
  // Heartbeat: bez něj byl log u velkého bucketu desítky minut němý a nešlo
  // poznat rozdíl mezi „jede pomalu" a „visí".
  const beat = setInterval(() => {
    const min = ((Date.now() - t0) / 60000).toFixed(1);
    console.log(`[${b.name}] ${done}/${objects.length} souborů, ${(totalBytes / 1024 / 1024).toFixed(0)} MB, ${min} min`);
  }, 60000);

  try {
    await runPool(objects, async (obj) => {
      try {
        const size = await downloadObject(b.name, obj, join(OUT, b.name, obj));
        totalFiles += 1;
        totalBytes += size;
      } catch (e) {
        failed += 1;
        if (failures.length < 20) failures.push(`${b.name}/${obj}: ${e.message}`);
      } finally {
        done += 1;
      }
    }, CONCURRENCY);
  } finally {
    clearInterval(beat);
  }

  console.log(`[${b.name}] hotovo: ${done} souborů za ${((Date.now() - t0) / 60000).toFixed(1)} min`);
}

console.log(`Hotovo: ${totalFiles} souborů, ${(totalBytes / 1024 / 1024).toFixed(1)} MB, chyb: ${failed}`);
if (failed > 0) {
  console.error(`Neuložené objekty (prvních ${failures.length} z ${failed}):`);
  for (const f of failures) console.error(`  ${f}`);
  process.exit(2);
}
