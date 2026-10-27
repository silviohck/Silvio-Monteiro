#!/usr/bin/env bash
# Compila o app para Apple Silicon (arm64) e monta "dist/Gerador de Documentos.app".
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Gerador de Documentos"
EXECUTAVEL="GeradorDocumentos"
VERSAO="${VERSAO:-1.0}"
APP="dist/$APP_NAME.app"

swift build -c release --arch arm64 --product "$EXECUTAVEL"
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTAVEL" "$APP/Contents/MacOS/$EXECUTAVEL"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>com.silviomonteiro.GeradorDocumentos</string>
    <key>CFBundleExecutable</key><string>$EXECUTAVEL</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSAO</string>
    <key>CFBundleVersion</key><string>$VERSAO</string>
    <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>O Gerador de Documentos usa o Microsoft Word para imprimir os documentos gerados.</string>
</dict>
</plist>
PLIST

# Assinatura local (ad-hoc), exigida para executar binários arm64.
codesign --force --sign - "$APP"

(cd dist && ditto -c -k --keepParent "$APP_NAME.app" "GeradorDocumentos-AppleSilicon.zip")
echo "Pronto: $APP"
