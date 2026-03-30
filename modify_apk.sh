#!/bin/bash
set -e

echo "=== PRO VII PAD Elite: splash + version fix ==="
echo ""

# Check Java
if ! command -v java &> /dev/null; then
    echo "ERROR: Java not found. Install JDK 11+ first."
    exit 1
fi

# Detect working python command
PYTHON=""
for cmd in python python3; do
    if command -v $cmd &> /dev/null; then
        VER=$($cmd --version 2>&1 || true)
        if echo "$VER" | grep -q 'Python 3'; then
            PYTHON=$cmd
            break
        fi
    fi
done

if [ -z "$PYTHON" ]; then
    echo "ERROR: Working Python 3 not found."
    exit 1
fi
echo "Using: $PYTHON ($($PYTHON --version 2>&1))"

WORK_DIR="$(pwd)/apk_work"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

get_ya_url() {
    curl -sL "https://cloud-api.yandex.net/v1/disk/public/resources/download?public_key=$1" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin)['href'])"
}

# Download apktool
if [ ! -f apktool.jar ]; then
    echo "[1/7] Downloading apktool..."
    curl -sL -o apktool.jar "https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar"
else
    echo "[1/7] apktool.jar already exists"
fi

# Download OLD APK (reference for splash)
if [ ! -f old_app.apk ]; then
    echo "[2/7] Downloading X-431 PAD VII APK (splash source ~134MB)..."
    DL_URL=$(get_ya_url "https://disk.yandex.ru/d/bUGT4-8JBq2R_w")
    curl -L --progress-bar -o old_app.apk "$DL_URL"
else
    echo "[2/7] old_app.apk already exists"
fi

# Download CLIENT APK (to modify)
if [ ! -f client_app.apk ]; then
    echo "[3/7] Downloading PRO VII PAD Elite APK (to modify ~145MB)..."
    DL_URL=$(get_ya_url "https://disk.yandex.ru/d/eKzN4xXYBZ3GNg")
    curl -L --progress-bar -o client_app.apk "$DL_URL"
else
    echo "[3/7] client_app.apk already exists"
fi

# Decompile
echo "[4/7] Decompiling APKs..."
echo "  Decompiling old APK (for splash resources)..."
java -jar apktool.jar d old_app.apk -o old_decoded -f
echo "  Decompiling client APK (resources only, preserving code)..."
java -jar apktool.jar d client_app.apk -o client_decoded --no-src -f

# Apply modifications
echo "[5/7] Applying modifications..."

# 1) Splash screens from old APK
cp old_decoded/res/drawable/launch_page.png client_decoded/res/drawable/launch_page.png
cp old_decoded/res/drawable/launch_page_port.png client_decoded/res/drawable/launch_page_port.png
echo "   [OK] Splash screens replaced (X-431 PAD VII branding)"

# 2) Logo assets
cp old_decoded/assets/logo_h.png client_decoded/assets/logo_h.png
cp old_decoded/assets/logo_l.png client_decoded/assets/logo_l.png
echo "   [OK] Logo assets replaced"

# 3) scaleType fix
sed -i.bak 's|android:scaleType="fitCenter"|android:scaleType="fitXY"|' client_decoded/res/layout/layout_splash.xml
echo "   [OK] Layout scaleType fixed"

# 4) Version 222 -> 254
sed -i.bak 's|versionName: 8.00.222|versionName: 8.00.254|' client_decoded/apktool.yml
echo "   [OK] Version: 8.00.222 -> 8.00.254"

# 5) Make NFC optional (allows install on phones without NFC)
sed -i.bak 's|<uses-feature android:name="android.hardware.nfc.hce"/>|<uses-feature android:name="android.hardware.nfc.hce" android:required="false"/>|' client_decoded/AndroidManifest.xml
echo "   [OK] NFC set to optional"

# 6) Namespace fix
COUNT=0
for f in $(grep -rl 'http://schemas.android.com/apk/res/com\.cnlaunch' client_decoded/res/ 2>/dev/null || true); do
    sed -i.bak 's|http://schemas.android.com/apk/res/com\.cnlaunch\.[a-zA-Z0-9.]*|http://schemas.android.com/apk/res-auto|g' "$f"
    COUNT=$((COUNT+1))
done
echo "   [OK] Fixed namespaces in $COUNT files"

find client_decoded -name "*.bak" -delete 2>/dev/null || true

# Rebuild
echo "[6/7] Rebuilding APK (preserving original code)..."
if java -jar apktool.jar b client_decoded -o client_fixed.apk; then
    echo "   [OK] APK rebuilt successfully"
else
    echo "ERROR: APK build failed!"
    exit 1
fi

# Sign with CERT alias (matching original APK signature format)
# This prevents Yandex Disk from misidentifying the file as JAR
echo "[7/7] Signing APK..."
if [ ! -f cert.keystore ]; then
    keytool -genkey -v -keystore cert.keystore -alias CERT -keyalg RSA -keysize 2048 \
        -validity 10000 -storepass android -keypass android \
        -dname "CN=Launch, OU=Launch, O=Launch, L=Shenzhen, S=Guangdong, C=CN" 2>&1 | tail -1
fi

jarsigner -sigalg SHA256withRSA -digestalg SHA-256 \
    -keystore cert.keystore -storepass android -keypass android \
    client_fixed.apk CERT

# Verify
echo ""
echo "=== Verifying code integrity ==="
ORIG_MD5=$(unzip -p client_app.apk classes.dex | md5sum | cut -d' ' -f1)
MOD_MD5=$(unzip -p client_fixed.apk classes.dex | md5sum | cut -d' ' -f1)
if [ "$ORIG_MD5" = "$MOD_MD5" ]; then
    echo "   [OK] DEX code identical to original (md5: $ORIG_MD5)"
else
    echo "   [WARNING] DEX differs! Orig: $ORIG_MD5 Mod: $MOD_MD5"
fi

cp client_fixed.apk "../PRO_VII_PAD_Elite.apk"

echo ""
echo "========================================"
echo "  DONE! Modified APK is ready."
echo "========================================"
echo ""
echo "File: $(cd .. && pwd)/PRO_VII_PAD_Elite.apk"
echo "Size: $(du -h ../PRO_VII_PAD_Elite.apk | cut -f1)"
