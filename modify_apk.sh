#!/bin/bash
set -e

echo "=== X-PRO5 -> X-431 PAD VII Rebranding Script ==="
echo ""

# Check Java
if ! command -v java &> /dev/null; then
    echo "ERROR: Java not found. Install JDK 11+ first."
    exit 1
fi

WORK_DIR="$(pwd)/apk_work"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download apktool if not present
if [ ! -f apktool.jar ]; then
    echo "[1/7] Downloading apktool..."
    curl -sL -o apktool.jar "https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar"
else
    echo "[1/7] apktool.jar already exists"
fi

# Download OLD APK (reference)
if [ ! -f old_app.apk ]; then
    echo "[2/7] Downloading X-431 PAD VII APK (reference)..."
    DL_URL=$(curl -sL "https://cloud-api.yandex.net/v1/disk/public/resources/download?public_key=https://disk.yandex.ru/d/bUGT4-8JBq2R_w" | python3 -c "import sys,json; print(json.load(sys.stdin)['href'])")
    curl -L -o old_app.apk "$DL_URL"
else
    echo "[2/7] old_app.apk already exists"
fi

# Download NEW APK (to modify)
if [ ! -f new_app.apk ]; then
    echo "[3/7] Downloading X-PRO5 APK (to modify)..."
    DL_URL=$(curl -sL "https://cloud-api.yandex.net/v1/disk/public/resources/download?public_key=https://disk.yandex.ru/d/5yWPLj7L_0Q9qw" | python3 -c "import sys,json; print(json.load(sys.stdin)['href'])")
    curl -L -o new_app.apk "$DL_URL"
else
    echo "[3/7] new_app.apk already exists"
fi

# Decompile both
echo "[4/7] Decompiling APKs..."
java -jar apktool.jar d old_app.apk -o old_decoded -f 2>&1 | grep -E "^I:" | tail -1
java -jar apktool.jar d new_app.apk -o new_decoded -f 2>&1 | grep -E "^I:" | tail -1

# Apply modifications
echo "[5/7] Applying modifications..."

# 1) Change app name
sed -i.bak 's|<string name="app_name">X-PRO5</string>|<string name="app_name">X-431 PAD VII</string>|' new_decoded/res/values/strings.xml

# 2) Copy splash screen images
cp old_decoded/res/drawable/launch_page.png new_decoded/res/drawable/launch_page.png
cp old_decoded/res/drawable/launch_page_port.png new_decoded/res/drawable/launch_page_port.png

# 3) Copy logo assets
cp old_decoded/assets/logo_h.png new_decoded/assets/logo_h.png
cp old_decoded/assets/logo_l.png new_decoded/assets/logo_l.png

# 4) Fix splash layout scaleType
sed -i.bak 's|android:scaleType="fitCenter"|android:scaleType="fitXY"|' new_decoded/res/layout/layout_splash.xml

# 5) Fix custom attribute namespaces for build compatibility
find new_decoded/res/ -name "*.xml" -exec grep -l "http://schemas.android.com/apk/res/com.cnlaunch.x431.padv" {} \; | while read f; do
    sed -i.bak 's|http://schemas.android.com/apk/res/com.cnlaunch.x431.padv|http://schemas.android.com/apk/res-auto|g' "$f"
done

echo "   - App name: X-PRO5 -> X-431 PAD VII"
echo "   - Splash screens replaced"
echo "   - Logo assets replaced"
echo "   - Layout scaleType fixed"

# Rebuild
echo "[6/7] Rebuilding APK..."
java -jar apktool.jar b new_decoded -o X-PRO5_modified_unsigned.apk 2>&1 | grep -E "^I:" | tail -1

# Sign
echo "[7/7] Signing APK..."
keytool -genkey -v -keystore release.keystore -alias release -keyalg RSA -keysize 2048 \
    -validity 10000 -storepass android -keypass android \
    -dname "CN=Launch, OU=Launch, O=Launch, L=Shenzhen, S=Guangdong, C=CN" 2>/dev/null || true

jarsigner -verbose -sigalg SHA256withRSA -digestalg SHA-256 \
    -keystore release.keystore -storepass android -keypass android \
    X-PRO5_modified_unsigned.apk release 2>/dev/null

# Rename final file
cp X-PRO5_modified_unsigned.apk "../X-PRO5_8.00.222_sign_rebranded.apk"

echo ""
echo "=== DONE ==="
echo "Modified APK: $(pwd)/../X-PRO5_8.00.222_sign_rebranded.apk"
echo "Size: $(du -h ../X-PRO5_8.00.222_sign_rebranded.apk | cut -f1)"
echo ""
echo "Install on Android device:"
echo "  adb install X-PRO5_8.00.222_sign_rebranded.apk"
