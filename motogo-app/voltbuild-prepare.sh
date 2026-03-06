#!/usr/bin/env bash
# ===== VoltBuilder prep – sync frontend → root www/ =====
# Run this BEFORE uploading to VoltBuilder.
# Never changes UX/UI/flow – only copies + patches for Cordova.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "=== VoltBuilder prep ==="

# 1. Clean & recreate www/
rm -rf www
mkdir -p www

# 2. Copy frontend assets (skip build/config files)
echo "[1/4] Syncing frontend → www/ ..."
cd frontend
for item in *; do
  case "$item" in
    .npmrc|build.sh|capacitor.config.ts|package.json|node_modules) continue ;;
  esac
  cp -r "$item" "$ROOT/www/"
done
# Copy hidden dirs that matter (src/services etc already included)
cd "$ROOT"

# Exclude supabase infra files (not needed in www)
rm -rf www/supabase

echo "   $(find www -type f | wc -l) files copied"

# 3. Overwrite native-bridge.js with Cordova version
echo "[2/4] Patching native-bridge.js (Cordova) ..."
cp voltbuild/www/native-bridge.js www/native-bridge.js

# 4. Patch index.html – add cordova.js before native-bridge
echo "[3/4] Patching index.html (cordova.js) ..."
sed -i \
  's|<!-- Native bridge (Capacitor) – must load before app.js, no-op in browser -->|<!-- Cordova – injected by VoltBuilder at build time -->\n<script src="cordova.js"></script>\n<!-- Native bridge (Cordova) – must load before app.js -->|' \
  www/index.html

# 5. Copy res/ INSIDE www/ (VoltBuilder requires it there)
echo "[4/5] Copying res/ into www/res/ ..."
cp -rf voltbuild/res www/res

# 6. Ensure root config files exist
echo "[5/5] Copying VoltBuilder config files to root ..."
cp -f voltbuild/config.xml  config.xml
cp -f voltbuild/voltbuilder.json voltbuilder.json

echo ""
echo "=== Done ==="
echo "Root now has: config.xml  voltbuilder.json  www/ (incl. res/)"
echo "Ready for VoltBuilder upload."
