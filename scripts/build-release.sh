#!/usr/bin/env bash
# Собирает дистрибутивы релиза: FoundryDesktop-<version>.zip и FoundryDesktop-<version>.dmg в dist/.
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
ARCHIVE_PATH=".build/FoundryDesktop.xcarchive"
APP_BUNDLE="$ARCHIVE_PATH/Products/Applications/FoundryDesktop.app"
DIST_DIR="dist"

echo "==> Сборка FoundryDesktop $VERSION (build $BUILD_NUMBER)"

rm -rf "$ARCHIVE_PATH" "$DIST_DIR"
mkdir -p "$DIST_DIR"

# CURRENT_PROJECT_VERSION обязана монотонно расти между релизами (Sparkle сравнивает
# именно её) — git rev-list --count даёт это бесплатно. Практики, глава 08 §6.1.
set -o pipefail
xcodebuild archive \
    -project FoundryDesktop.xcodeproj \
    -scheme FoundryDesktop \
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

echo "==> ZIP"
# ditto, не zip: сохраняет ресурс-форки и подпись бандла нетронутыми.
ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_DIR/FoundryDesktop-$VERSION.zip"

echo "==> DMG"
# create-dmg выходит с кодом 2, когда не нашёл identity для подписи DMG — у нас его
# нет никогда, и это ожидаемо: сам DMG при этом создаётся валидным. Любой другой
# ненулевой код — настоящая ошибка.
dmg_exit=0
npx --yes create-dmg "$APP_BUNDLE" "$DIST_DIR" || dmg_exit=$?
if [[ "$dmg_exit" -ne 0 && "$dmg_exit" -ne 2 ]]; then
    echo "!! create-dmg упал с кодом $dmg_exit" >&2
    exit "$dmg_exit"
fi

# create-dmg именует файл "FoundryDesktop 0.1.0.dmg" — пробел в имени ассета релиза
# ломает ссылки для скачивания, переименовываем.
produced_dmg="$(find "$DIST_DIR" -maxdepth 1 -name '*.dmg' -print -quit)"
test -n "$produced_dmg" || { echo "!! DMG не создан" >&2; exit 1; }
if [[ "$produced_dmg" != "$DIST_DIR/FoundryDesktop-$VERSION.dmg" ]]; then
    mv "$produced_dmg" "$DIST_DIR/FoundryDesktop-$VERSION.dmg"
fi

echo "==> Проверка дистрибутивов"
codesign --verify --strict "$APP_BUNDLE"
hdiutil verify "$DIST_DIR/FoundryDesktop-$VERSION.dmg" >/dev/null
echo "    подпись: $(codesign -dv "$APP_BUNDLE" 2>&1 | grep -o 'Signature=.*')"
echo "    версии:  $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist") (build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist"))"
echo "    arch:    $(lipo -archs "$APP_BUNDLE/Contents/MacOS/FoundryDesktop")"

echo
echo "==> Готово:"
ls -lh "$DIST_DIR"
