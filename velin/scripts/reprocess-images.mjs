/**
 * Jednorázové přegenerování (zmenšení + komprese) už nahraných obrázků v Supabase Storage.
 *
 * PROČ: Stávající fotky (cca 150 ks) jsou ve full-res (~3 MB/ks) → žerou egress i storage.
 * Tento skript je stáhne, zmenší na max 1600 px, překomprimuje (JPEG 80 %, PNG zachová)
 * a nahraje ZPĚT NA STEJNOU CESTU se stejným formátem → odkazy uložené v DB zůstanou platné.
 * Cache-Control nastaví na 1 rok, takže se nestahují opakovaně.
 *
 * BEZPEČNÉ: přepíše soubor jen pokud je nová verze menší. Umí dry-run (jen vypíše, nic nemění).
 *
 * SPUŠTĚNÍ (až bude služba zase živá — po upgrade plánu / resetu kvóty):
 *   cd velin
 *   npm i -D sharp                       # jednorázově, jen pro tento skript
 *   export SUPABASE_URL="https://vnwnqteskbykeucanlhk.supabase.co"
 *   export SUPABASE_SERVICE_ROLE_KEY="<service_role klíč z Dashboard → Settings → API>"
 *   node scripts/reprocess-images.mjs --dry-run     # napřed nasucho – zkontroluj výpis
 *   node scripts/reprocess-images.mjs               # ostré přegenerování
 *
 * Volitelné přepínače:
 *   --bucket=media        cílový bucket (výchozí: media)
 *   --prefix=motos        zpracovat jen podsložku (výchozí: celý bucket)
 *   --max=1600            max delší strana v px
 *   --quality=80          JPEG kvalita
 *   --dry-run             nic nezapisuje, jen vypíše co by udělal
 *
 * POZN.: service_role klíč NIKDY necommituj. Předává se jen přes env proměnnou.
 */
import { createClient } from '@supabase/supabase-js'
import sharp from 'sharp'

const args = Object.fromEntries(
  process.argv.slice(2).map(a => {
    const [k, v] = a.replace(/^--/, '').split('=')
    return [k, v === undefined ? true : v]
  })
)

const SUPABASE_URL = process.env.SUPABASE_URL
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY
const BUCKET = args.bucket || 'media'
const PREFIX = args.prefix || ''
const MAX_DIM = Number(args.max || 1600)
const QUALITY = Number(args.quality || 80)
const DRY = !!args['dry-run']

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('❌ Chybí SUPABASE_URL nebo SUPABASE_SERVICE_ROLE_KEY v env proměnných.')
  process.exit(1)
}

const supabase = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false },
})

const IMAGE_RE = /\.(jpe?g|png|webp)$/i
const PAGE = 100

// Rekurzivně projde složky bucketu a vrátí ploché pole cest k souborům.
async function listAll(prefix) {
  const out = []
  let offset = 0
  while (true) {
    const { data, error } = await supabase.storage.from(BUCKET).list(prefix, {
      limit: PAGE,
      offset,
      sortBy: { column: 'name', order: 'asc' },
    })
    if (error) throw error
    if (!data || data.length === 0) break
    for (const entry of data) {
      const full = prefix ? `${prefix}/${entry.name}` : entry.name
      // Položka bez `id` (a bez metadat) = složka → zanoř se.
      if (entry.id === null || (entry.metadata == null && !IMAGE_RE.test(entry.name))) {
        out.push(...await listAll(full))
      } else {
        out.push({ path: full, size: entry.metadata?.size ?? null })
      }
    }
    if (data.length < PAGE) break
    offset += PAGE
  }
  return out
}

function fmt(bytes) {
  if (bytes == null) return '?'
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`
}

async function reencode(buf, path) {
  const isPng = /\.png$/i.test(path)
  let img = sharp(buf, { failOn: 'none' }).rotate() // respektuje EXIF orientaci
  const meta = await img.metadata()
  if (meta.width && meta.height && Math.max(meta.width, meta.height) > MAX_DIM) {
    img = img.resize({ width: MAX_DIM, height: MAX_DIM, fit: 'inside', withoutEnlargement: true })
  }
  if (isPng) {
    return { out: await img.png({ compressionLevel: 9 }).toBuffer(), contentType: 'image/png' }
  }
  return { out: await img.jpeg({ quality: QUALITY, mozjpeg: true }).toBuffer(), contentType: 'image/jpeg' }
}

async function main() {
  console.log(`📦 Bucket: ${BUCKET}${PREFIX ? ` / prefix: ${PREFIX}` : ''}  | max ${MAX_DIM}px, JPEG q${QUALITY}${DRY ? '  (DRY-RUN)' : ''}`)
  const files = (await listAll(PREFIX)).filter(f => IMAGE_RE.test(f.path))
  console.log(`Nalezeno ${files.length} obrázků.\n`)

  let before = 0, after = 0, changed = 0, skipped = 0, failed = 0
  for (const f of files) {
    try {
      const { data, error } = await supabase.storage.from(BUCKET).download(f.path)
      if (error) throw error
      const buf = Buffer.from(await data.arrayBuffer())
      const { out, contentType } = await reencode(buf, f.path)
      before += buf.length
      if (out.length >= buf.length) {
        after += buf.length
        skipped++
        console.log(`= ${f.path}  ${fmt(buf.length)} (beze změny)`)
        continue
      }
      after += out.length
      changed++
      console.log(`↓ ${f.path}  ${fmt(buf.length)} → ${fmt(out.length)}`)
      if (!DRY) {
        const { error: upErr } = await supabase.storage.from(BUCKET).upload(f.path, out, {
          upsert: true,
          contentType,
          cacheControl: '31536000',
        })
        if (upErr) throw upErr
      }
    } catch (e) {
      failed++
      console.warn(`! ${f.path}  CHYBA: ${e.message || e}`)
    }
  }

  console.log(`\n— Hotovo —`)
  console.log(`Zpracováno:  ${changed} zmenšeno, ${skipped} beze změny, ${failed} chyb`)
  console.log(`Velikost:    ${fmt(before)} → ${fmt(after)}  (úspora ${fmt(before - after)})`)
  if (DRY) console.log(`\n(DRY-RUN — nic se nezapsalo. Spusť bez --dry-run pro ostré přegenerování.)`)
}

main().catch(e => { console.error(e); process.exit(1) })
