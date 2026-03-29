#!/bin/bash
set -e

echo "=== X-PRO5 -> X-431 PAD VII Rebranding Script ==="
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
    echo "Install Python 3 from https://www.python.org/downloads/"
    exit 1
fi
echo "Using: $PYTHON ($($PYTHON --version 2>&1))"

WORK_DIR="$(pwd)/apk_work"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Helper: extract download URL from Yandex Disk
get_ya_url() {
    curl -sL "https://cloud-api.yandex.net/v1/disk/public/resources/download?public_key=$1" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin)['href'])"
}

# Download apktool if not present
if [ ! -f apktool.jar ]; then
    echo "[1/7] Downloading apktool..."
    curl -sL -o apktool.jar "https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar"
else
    echo "[1/7] apktool.jar already exists"
fi

# Download OLD APK (reference)
if [ ! -f old_app.apk ]; then
    echo "[2/7] Downloading X-431 PAD VII APK (reference ~134MB)..."
    DL_URL=$(get_ya_url "https://disk.yandex.ru/d/bUGT4-8JBq2R_w")
    curl -L --progress-bar -o old_app.apk "$DL_URL"
else
    echo "[2/7] old_app.apk already exists"
fi

# Download NEW APK (to modify)
if [ ! -f new_app.apk ]; then
    echo "[3/7] Downloading X-PRO5 APK (to modify ~144MB)..."
    DL_URL=$(get_ya_url "https://disk.yandex.ru/d/5yWPLj7L_0Q9qw")
    curl -L --progress-bar -o new_app.apk "$DL_URL"
else
    echo "[3/7] new_app.apk already exists"
fi

# Decompile OLD (full, to extract resources)
echo "[4/7] Decompiling APKs..."
echo "  Decompiling old APK (full)..."
java -jar apktool.jar d old_app.apk -o old_decoded -f

# Decompile NEW with --no-src to PRESERVE original dex/code
echo "  Decompiling new APK (resources only, preserving code)..."
java -jar apktool.jar d new_app.apk -o new_decoded --no-src -f

# Apply modifications
echo "[5/7] Applying modifications..."

# 1) Change app name
sed -i.bak 's|<string name="app_name">X-PRO5</string>|<string name="app_name">X-431 PAD VII</string>|' new_decoded/res/values/strings.xml
echo "   [OK] App name: X-PRO5 -> X-431 PAD VII"

# 2) Copy splash screen images from old to new
cp old_decoded/res/drawable/launch_page.png new_decoded/res/drawable/launch_page.png
cp old_decoded/res/drawable/launch_page_port.png new_decoded/res/drawable/launch_page_port.png
echo "   [OK] Splash screens replaced"

# 3) Copy logo assets
cp old_decoded/assets/logo_h.png new_decoded/assets/logo_h.png
cp old_decoded/assets/logo_l.png new_decoded/assets/logo_l.png
echo "   [OK] Logo assets replaced"

# 4) Fix splash layout scaleType
sed -i.bak 's|android:scaleType="fitCenter"|android:scaleType="fitXY"|' new_decoded/res/layout/layout_splash.xml
echo "   [OK] Layout scaleType fixed (fitCenter -> fitXY)"

# 5) Make NFC optional (allows install on phones without NFC for testing)
sed -i.bak 's|<uses-feature android:name="android.hardware.nfc.hce"/>|<uses-feature android:name="android.hardware.nfc.hce" android:required="false"/>|' new_decoded/AndroidManifest.xml
echo "   [OK] NFC set to optional (allows install on any phone)"

# 6) Fix custom attribute namespaces for build compatibility
echo "   Fixing custom attribute namespaces..."
COUNT=0
for f in $(grep -rl 'http://schemas.android.com/apk/res/com\.cnlaunch' new_decoded/res/ 2>/dev/null || true); do
    sed -i.bak 's|http://schemas.android.com/apk/res/com\.cnlaunch\.[a-zA-Z0-9.]*|http://schemas.android.com/apk/res-auto|g' "$f"
    COUNT=$((COUNT+1))
done
echo "   [OK] Fixed namespaces in $COUNT files"

# Clean up .bak files
find new_decoded -name "*.bak" -delete 2>/dev/null || true

# Rebuild (dex files are copied as-is, not recompiled)
echo "[6/7] Rebuilding APK (preserving original code)..."
if java -jar apktool.jar b new_decoded -o X-PRO5_modified.apk; then
    echo "   [OK] APK rebuilt successfully"
else
    echo "ERROR: APK build failed!"
    exit 1
fi

# Sign
echo "[7/7] Signing APK..."
if [ ! -f release.keystore ]; then
    keytool -genkey -v -keystore release.keystore -alias release -keyalg RSA -keysize 2048 \
        -validity 10000 -storepass android -keypass android \
        -dname "CN=Launch, OU=Launch, O=Launch, L=Shenzhen, S=Guangdong, C=CN" 2>&1 | tail -1
fi

jarsigner -sigalg SHA256withRSA -digestalg SHA-256 \
    -keystore release.keystore -storepass android -keypass android \
    X-PRO5_modified.apk release

# Verify dex integrity
echo ""
echo "=== Verifying code integrity ==="
ORIG_MD5=$(unzip -p new_app.apk classes.dex | md5sum | cut -d' ' -f1)
MOD_MD5=$(unzip -p X-PRO5_modified.apk classes.dex | md5sum | cut -d' ' -f1)
if [ "$ORIG_MD5" = "$MOD_MD5" ]; then
    echo "   [OK] DEX code is identical to original (md5: $ORIG_MD5)"
else
    echo "   [WARNING] DEX code differs! Original: $ORIG_MD5, Modified: $MOD_MD5"
fi

# Copy final file
cp X-PRO5_modified.apk "../X-PRO5_8.00.222_sign.apk"

echo ""
echo "========================================"
echo "  DONE! Modified APK is ready."
echo "========================================"
echo ""
echo "File: $(cd .. && pwd)/X-PRO5_8.00.222_sign.apk"
echo "Size: $(du -h ../X-PRO5_8.00.222_sign.apk | cut -f1)"
echo ""
echo "To install on device:  adb install X-PRO5_8.00.222_sign.apk"
