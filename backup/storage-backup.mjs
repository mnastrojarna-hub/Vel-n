#!/usr/bin/env node
// Stáhne VŠECHNY objekty ze VŠECH Supabase Storage bucketů (documents, media, sos-photos, ...)
// do lokální složky. Používá service_role klíč — spouštět POUZE v CI (GitHub Actions), nikdy na klientu.
//
// Použití: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node backup/storage-backup.mjs <out_dir>

import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

const SUPABASE_URL = process.env.SUPABASE_URL?.replace(/\/$/, '');
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const OUT = process.argv[2] || 'storage-backup';

if (!SUPABASE_URL || !KEY) {
  console.error('Chybí SUPABASE_URL nebo SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

const headers = { Authorization: `Bearer ${KEY}`, apikey: KEY };

async function api(path, init = {}) {
  const res = await fetch(`${SUPABASE_URL}${path}`, { ...init, headers: { ...headers, ...(init.headers || {}) } });
  if (!res.ok) throw new Error(`${init.method || 'GET'} ${path} -> ${res.status} ${await res.text()}`);
  return res;
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

let totalFiles = 0;
let totalBytes = 0;
let failed = 0;

const buckets = await listBuckets();
console.log(`Buckety: ${buckets.map((b) => b.name).join(', ')}`);

for (const b of buckets) {
  const objects = await listObjects(b.name);
  console.log(`[${b.name}] ${objects.length} objektů`);
  for (const obj of objects) {
    try {
      const size = await downloadObject(b.name, obj, join(OUT, b.name, obj));
      totalFiles += 1;
      totalBytes += size;
    } catch (e) {
      failed += 1;
      console.error(`CHYBA ${b.name}/${obj}: ${e.message}`);
    }
  }
}

console.log(`Hotovo: ${totalFiles} souborů, ${(totalBytes / 1024 / 1024).toFixed(1)} MB, chyb: ${failed}`);
if (failed > 0) process.exit(2);
