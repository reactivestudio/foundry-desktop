#!/usr/bin/env bash
# Собирает дистрибутив релиза: Foundry-<version>.dmg в dist/.
#
# Только DMG. ZIP по канону (практики, глава 08 §4.3) нужен Sparkle-автообновлениям —
# вернуть, когда Sparkle подключат.
#
# Использование:  ./scripts/build-release.sh <version>
# Пример:         ./scripts/build-release.sh 0.1.0
#
# Подпись: ad-hoc ("Sign to Run Locally"), без Developer ID и notarization.
# Скачанное приложение блокируется Gatekeeper — см. README §Установка.
# Переход на Developer ID — практики, глава 08 §4.1–4.2.

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "usage: $0 <version>   (например: $0 0.1.0)" >&2
    exit 64
fi

cd "$(dirname "$0")/.."

# xcbeautify предустановлен на раннерах, но локально может отсутствовать —
# тогда лог идёт как есть.
format_build_log() {
    if command -v xcbeautify >/dev/null; then
        xcbeautify
    else
        cat
    fi
}

BUILD_NUMBER="$(git rev-list --count HEAD)"
ARCHIVE_PATH=".build/Foundry.xcarchive"
APP_BUNDLE="$ARCHIVE_PATH/Products/Applications/Foundry.app"
DIST_DIR="dist"

echo "==> Сборка Foundry $VERSION (build $BUILD_NUMBER)"

rm -rf "$ARCHIVE_PATH" "$DIST_DIR"
mkdir -p "$DIST_DIR"

# CURRENT_PROJECT_VERSION обязана монотонно расти между релизами (Sparkle сравнивает
# именно её) — git rev-list --count даёт это бесплатно. Практики, глава 08 §6.1.
set -o pipefail
xcodebuild archive \
    -project Foundry.xcodeproj \
    -scheme Foundry \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath .build/DerivedData \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    | format_build_log

test -d "$APP_BUNDLE" || { echo "!! archive не содержит .app: $APP_BUNDLE" >&2; exit 1; }

echo "==> DMG"
# appdmg вместо create-dmg: у него настраиваются фон, размер окна и позиции
# иконок — DMG собирается по утверждённому эскизу (design/dmg/, генератор
# generate-background.py). Пару background.png + background@2x.png appdmg
# склеивает в ретина-TIFF сам. Координаты — центры иконок в pt от левого
# верха контентной области, те же константы, что в генераторе фона.
DMG_CONFIG=".build/appdmg.json"
cat > "$DMG_CONFIG" <<JSON
{
  "title": "Foundry",
  "background": "$PWD/design/dmg/background.png",
  "icon-size": 128,
  "format": "ULFO",
  "window": { "size": { "width": 704, "height": 400 } },
  "contents": [
    { "x": 208, "y": 176, "type": "file", "path": "$PWD/$APP_BUNDLE" },
    { "x": 496, "y": 176, "type": "link", "path": "/Applications" }
  ]
}
JSON
npx --yes appdmg "$DMG_CONFIG" "$DIST_DIR/Foundry-$VERSION.dmg"

echo "==> Проверка дистрибутива"
codesign --verify --strict "$APP_BUNDLE"
hdiutil verify "$DIST_DIR/Foundry-$VERSION.dmg" >/dev/null
echo "    подпись: $(codesign -dv "$APP_BUNDLE" 2>&1 | grep -o 'Signature=.*')"
echo "    bundle:  $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
echo "    версии:  $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist") (build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist"))"
echo "    arch:    $(lipo -archs "$APP_BUNDLE/Contents/MacOS/Foundry")"

echo
echo "==> Готово:"
ls -lh "$DIST_DIR"
