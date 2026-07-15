#!/usr/bin/env bash
# Собирает релизные артефакты: FoundryDesktop-<version>.zip и FoundryDesktop-<version>.dmg в dist/.
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

BUILD_NUMBER="$(git rev-list --count HEAD)"
ARCHIVE=".build/FoundryDesktop.xcarchive"
APP="$ARCHIVE/Products/Applications/FoundryDesktop.app"
DIST="dist"

echo "==> Сборка FoundryDesktop $VERSION (build $BUILD_NUMBER)"

rm -rf "$ARCHIVE" "$DIST"
mkdir -p "$DIST"

# CURRENT_PROJECT_VERSION обязана монотонно расти между релизами (Sparkle сравнивает
# именно её) — git rev-list --count даёт это бесплатно. Практики, глава 08 §6.1.
set -o pipefail
xcodebuild archive \
    -project FoundryDesktop.xcodeproj \
    -scheme FoundryDesktop \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -derivedDataPath .build/DerivedData \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    | { command -v xcbeautify >/dev/null && xcbeautify || cat; }

test -d "$APP" || { echo "!! archive не содержит .app: $APP" >&2; exit 1; }

echo "==> ZIP"
# ditto, не zip: сохраняет ресурс-форки и подпись бандла нетронутыми.
ditto -c -k --keepParent "$APP" "$DIST/FoundryDesktop-$VERSION.zip"

echo "==> DMG"
# create-dmg выходит с кодом 2, когда не нашёл identity для подписи DMG — у нас его
# нет никогда, и это ожидаемо: сам DMG при этом создаётся валидным. Любой другой
# ненулевой код — настоящая ошибка.
dmg_exit=0
npx --yes create-dmg "$APP" "$DIST" || dmg_exit=$?
if [[ "$dmg_exit" -ne 0 && "$dmg_exit" -ne 2 ]]; then
    echo "!! create-dmg упал с кодом $dmg_exit" >&2
    exit "$dmg_exit"
fi

# create-dmg именует файл "FoundryDesktop 0.1.0.dmg" — пробел в имени ассета релиза
# ломает ссылки для скачивания, переименовываем.
produced_dmg="$(find "$DIST" -maxdepth 1 -name '*.dmg' -print -quit)"
test -n "$produced_dmg" || { echo "!! DMG не создан" >&2; exit 1; }
if [[ "$produced_dmg" != "$DIST/FoundryDesktop-$VERSION.dmg" ]]; then
    mv "$produced_dmg" "$DIST/FoundryDesktop-$VERSION.dmg"
fi

echo "==> Проверка артефактов"
codesign --verify --strict "$APP"
hdiutil verify "$DIST/FoundryDesktop-$VERSION.dmg" >/dev/null
echo "    подпись: $(codesign -dv "$APP" 2>&1 | grep -o 'Signature=.*')"
echo "    версии:  $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") (build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist"))"
echo "    arch:    $(lipo -archs "$APP/Contents/MacOS/FoundryDesktop")"

echo
echo "==> Готово:"
ls -lh "$DIST"
