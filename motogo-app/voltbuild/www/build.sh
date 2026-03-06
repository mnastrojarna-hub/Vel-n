#!/usr/bin/env bash
# ===== MotoGo24 – Android APK build script =====
# Usage: bash build.sh
set -euo pipefail

echo "========================================"
echo "  MotoGo24 – Android APK Build"
echo "========================================"

# ===== 1. Install dependencies =====
echo ""
echo "[1/7] Installing npm dependencies..."
npm install

# ===== 2. Prepare www/ directory =====
echo ""
echo "[2/7] Preparing www/ directory..."
rm -rf www
mkdir -p www/css www/js www/data www/icons www/src/services

# Copy HTML entry point
cp index.html www/

# Copy root-level JS files
cp native-bridge.js www/
cp app.js www/
cp ui-controller.js www/
cp booking-logic.js www/
cp booking-detail.js www/
cp booking-detail-cal.js www/
cp booking-calendar.js www/
cp booking-edit.js www/
cp templates.js www/
for f in templates-*.js; do
  [ -f "$f" ] && cp "$f" www/
done

# Copy subdirectories
cp css/*.css www/css/
cp js/*.js www/js/
cp data/*.js www/data/
cp icons/*.png www/icons/
cp manifest.json www/
cp sw.js www/

# Copy src/services (including local Supabase SDK)
cp src/services/*.js www/src/services/

echo "   www/ ready ($(find www -type f | wc -l) files)"

# ===== 3. Add Android platform =====
echo ""
echo "[3/7] Adding Android platform..."
if [ ! -d "android" ]; then
  npx cap add android
else
  echo "   Android platform already exists – skipping"
fi

# ===== 4. Add permissions to AndroidManifest.xml =====
echo ""
echo "[4/7] Configuring Android permissions..."
MANIFEST="android/app/src/main/AndroidManifest.xml"

if [ -f "$MANIFEST" ]; then
  # Only add permissions if not already present
  if ! grep -q "android.permission.CAMERA" "$MANIFEST"; then
    sed -i '/<application/i \
    <!-- MotoGo24 permissions -->\
    <uses-permission android:name="android.permission.CAMERA" />\
    <uses-permission android:name="android.permission.RECORD_AUDIO" />\
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />\
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />\
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />\
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />\
    <uses-permission android:name="android.permission.USE_BIOMETRIC" />\
    <uses-permission android:name="android.permission.INTERNET" />\
    <uses-permission android:name="android.permission.VIBRATE" />' "$MANIFEST"
    echo "   Permissions added to AndroidManifest.xml"
  else
    echo "   Permissions already present – skipping"
  fi
else
  echo "   WARNING: AndroidManifest.xml not found at $MANIFEST"
fi

# ===== 5. Sync web assets to Android =====
echo ""
echo "[5/7] Syncing with Capacitor..."
npx cap sync android

# ===== 5b. Copy custom app icons =====
if [ -d "resources/android" ]; then
  for d in resources/android/mipmap-*; do
    folder=$(basename "$d")
    target="android/app/src/main/res/$folder"
    if [ -d "$target" ]; then
      cp -f "$d"/* "$target/"
    fi
  done
fi

# ===== 6. Build debug APK =====
echo ""
echo "[6/7] Building debug APK (this may take a few minutes)..."
cd android
chmod +x gradlew
./gradlew assembleDebug
cd ..

# ===== 7. Copy APK to project root =====
echo ""
echo "[7/7] Copying APK to project root..."
APK_PATH=$(find android/app/build/outputs/apk/debug -name "*.apk" 2>/dev/null | head -1)

if [ -n "$APK_PATH" ]; then
  cp "$APK_PATH" ./motogo24-debug.apk
  echo ""
  echo "========================================"
  echo "  BUILD COMPLETE"
  echo "========================================"
  echo "  APK: ./motogo24-debug.apk"
  echo "  Size: $(du -h ./motogo24-debug.apk | cut -f1)"
  echo ""
  echo "  Install on device:"
  echo "    adb install motogo24-debug.apk"
  echo "  Or send via email/transfer to phone."
  echo "========================================"
else
  echo "ERROR: APK not found in build outputs"
  exit 1
fi
