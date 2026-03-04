#!/usr/bin/env node

import { execSync, spawn } from 'child_process'
import { existsSync } from 'fs'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const root = resolve(__dirname, 'velin')

// Ensure dependencies are installed
if (!existsSync(resolve(root, 'node_modules'))) {
  console.log('📦 Instaluji závislosti...')
  execSync('npm install', { cwd: root, stdio: 'inherit' })
}

// Pick a free port (default 5173)
const port = process.env.PORT || 5173
const url = `http://localhost:${port}`

console.log(`\n🏍️  MotoGo24 Velín`)
console.log(`   ${url}\n`)

// Launch Vite dev server
const vite = spawn('npx', ['vite', '--port', String(port), '--open'], {
  cwd: root,
  stdio: 'inherit',
  shell: true,
})

vite.on('close', (code) => process.exit(code ?? 0))

// Clean exit on Ctrl+C
process.on('SIGINT', () => { vite.kill('SIGINT'); process.exit(0) })
process.on('SIGTERM', () => { vite.kill('SIGTERM'); process.exit(0) })
