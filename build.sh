#!/bin/bash
# Builds DockPeek.app (with its System Settings pane embedded in Contents/Resources).
#
# Usage:
#   ./build.sh              build build/DockPeek.app
#   ./build.sh --install    build, copy to /Applications and relaunch (the app installs/updates its Settings pane)
#   ./build.sh --package    build dist/DockPeek-<version>.pkg to share with other people
#   ./build.sh --bump [major|minor|patch]   start the next version as test build "a" (e.g. 1.2.5 → 1.2.6a)
#   ./build.sh --bump test                  next test build of the same version (1.2.6a → 1.2.6b)
#   ./build.sh --bump final                 drop the test letter when it is approved (1.2.6b → 1.2.6)
#   ./build.sh --release    package and publish a GitHub release (the installed apps update from it)
#
# Optional signing for distribution (needs a paid Apple Developer account):
#   DEVELOPER_ID_APP="Developer ID Application: Name (TEAMID)"
#   DEVELOPER_ID_INSTALLER="Developer ID Installer: Name (TEAMID)"
#   NOTARY_PROFILE="profile"   # created with: xcrun notarytool store-credentials profile
# Without them the app is ad-hoc signed and the .pkg is unsigned.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"

if [[ "$MODE" == "--bump" ]]; then
    # Semver (patch = fixes, minor = new features, major = big changes) plus a test letter: every build
    # installed for trying out is X.Y.Z<letter>; only the approved one becomes X.Y.Z and can be released.
    PART="${2:-patch}"
    CURRENT="$(tr -d '[:space:]' < VERSION)"
    NUMBERS="${CURRENT%%[a-z]*}"
    LETTER="${CURRENT#"$NUMBERS"}"
    IFS=. read -r MAJOR MINOR PATCH < <(echo "$NUMBERS")
    case "$PART" in
        major) NEW="$((MAJOR + 1)).0.0a" ;;
        minor) NEW="$MAJOR.$((MINOR + 1)).0a" ;;
        patch) NEW="$MAJOR.$MINOR.$((PATCH + 1))a" ;;
        test)
            if [[ -z "$LETTER" ]]; then
                echo "$CURRENT is final; start a new version first: ./build.sh --bump patch" >&2; exit 1
            fi
            [[ "$LETTER" == "z" ]] && { echo "No test letters left after z." >&2; exit 1; }
            NEW="$NUMBERS$(echo "$LETTER" | tr 'a-y' 'b-z')" ;;
        final) NEW="$NUMBERS" ;;
        *) echo "Usage: ./build.sh --bump [major|minor|patch|test|final]" >&2; exit 1 ;;
    esac
    echo "$NEW" > VERSION
    echo "Version: $NEW"
    exit 0
fi

VERSION="${DOCKPEEK_VERSION:-$(tr -d '[:space:]' < VERSION)}"   # DOCKPEEK_VERSION: only for testing updates
REPO="postarek/dockpeek"

if [[ "$MODE" == "--release" ]]; then
    if [[ "$VERSION" =~ [a-z]$ ]]; then
        echo "$VERSION is a test build. When it is approved: ./build.sh --bump final" >&2; exit 1
    fi
    # Refuse to publish something that isn't committed, or a version that already exists.
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "Commit your changes first (git status is not clean)." >&2; exit 1
    fi
    if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
        echo "v$VERSION is already published. Bump the version: ./build.sh --bump" >&2; exit 1
    fi
    NOTES="$(awk -v v="$VERSION" '$0 ~ "^## "v" " {on=1; next} /^## / {on=0} on' CHANGELOG.md | sed -e '/./,$!d')"
    if [[ -z "$NOTES" ]]; then
        echo "Add a '## $VERSION — <date>' section to CHANGELOG.md first." >&2; exit 1
    fi
fi
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
OUT="build"
APP="$OUT/DockPeek.app"
PANE="$OUT/DockPeek.prefPane"
ICNS="$OUT/AppIcon.icns"
mkdir -p "$OUT"

set_version() {
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$1"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$1"
}

sign() {
    local target="$1" requirement="${2:-}"
    if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
        codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$target"
    elif [[ -n "$requirement" ]]; then
        # Ad-hoc signatures default to a cdhash requirement, which changes on every build and makes macOS
        # forget the Accessibility/Screen Recording grants. Pin the requirement to the bundle identifier.
        codesign --force --sign - --requirements "=designated => identifier \"$requirement\"" "$target"
    else
        codesign --force --sign - "$target"
    fi
}

# Icon: Resources/AppIcon.png (regenerate with `swift scripts/make-icon.swift Resources/AppIcon.png`).
ICONSET="$OUT/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICNS"

# System Settings pane (loaded by the arm64 legacy pane loader, so it must be an arm64 MH_BUNDLE)
rm -rf "$PANE"
mkdir -p "$PANE/Contents/MacOS" "$PANE/Contents/Resources"
swiftc -O -parse-as-library -module-name DockPeekPane -target arm64-apple-macos14 \
    -emit-executable -Xlinker -bundle -framework PreferencePanes \
    Sources/DockPeekShared/DockPeekSettings.swift PrefPane/DockPeekPane.swift \
    -o "$PANE/Contents/MacOS/DockPeekPane"
cp PrefPane/Info.plist "$PANE/Contents/Info.plist"
set_version "$PANE/Contents/Info.plist"
cp "$ICNS" "$PANE/Contents/Resources/AppIcon.icns"
sign "$PANE"

# App
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DockPeek" "$APP/Contents/MacOS/DockPeek"
cp Resources/Info.plist "$APP/Contents/Info.plist"
set_version "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$PANE" "$APP/Contents/Resources/"
sign "$APP" "local.dockpeek"
echo "Built: $APP ($VERSION, build $BUILD_NUMBER)"

if [[ "$MODE" == "--install" ]]; then
    # System Settings keeps loaded panes in a loader process; replacing the pane under it leaves it blank.
    SETTINGS_WAS_OPEN=false
    if pgrep -x "System Settings" >/dev/null; then
        SETTINGS_WAS_OPEN=true
        osascript -e 'quit app "System Settings"' 2>/dev/null || true
    fi
    pkill -f "legacyLoader-arm64" 2>/dev/null || true
    pkill -x DockPeek 2>/dev/null || true
    # Opening the new copy while the old one is still quitting fails (error -600).
    for _ in {1..50}; do pgrep -x DockPeek >/dev/null || break; sleep 0.1; done
    sleep 1   # LaunchServices still holds the old instance for a moment after it exits

    if [[ -e /Applications/DockPeek.app && ! -O /Applications/DockPeek.app/Contents/Info.plist ]]; then
        # Installed by the .pkg (owned by root): replacing it needs an administrator password.
        osascript -e 'do shell script "rm -rf /Applications/DockPeek.app" with administrator privileges'
    else
        rm -rf /Applications/DockPeek.app
    fi
    cp -R "$APP" /Applications/
    open /Applications/DockPeek.app || { sleep 2; open /Applications/DockPeek.app; }   # installs/updates ~/Library/PreferencePanes/DockPeek.prefPane
    echo "Installed to /Applications/DockPeek.app"

    if $SETTINGS_WAS_OPEN; then
        sleep 2
        open ~/Library/PreferencePanes/DockPeek.prefPane
    fi
fi

if [[ "$MODE" == "--package" || "$MODE" == "--release" ]]; then
    DIST="dist"
    PKG_WORK="$OUT/pkg"
    rm -rf "$PKG_WORK"
    mkdir -p "$PKG_WORK/root/Applications" "$DIST"
    cp -R "$APP" "$PKG_WORK/root/Applications/"

    # Never "upgrade" a copy of DockPeek found elsewhere on disk (e.g. a build folder): always /Applications.
    pkgbuild --analyze --root "$PKG_WORK/root" "$PKG_WORK/components.plist" >/dev/null
    /usr/libexec/PlistBuddy -c "Delete :0:BundleIsRelocatable" "$PKG_WORK/components.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$PKG_WORK/components.plist"

    pkgbuild --root "$PKG_WORK/root" \
        --component-plist "$PKG_WORK/components.plist" \
        --identifier local.dockpeek.pkg \
        --version "$VERSION" \
        --install-location / \
        --scripts Installer/scripts \
        "$PKG_WORK/DockPeek-component.pkg" >/dev/null

    sed "s/__VERSION__/$VERSION/" Installer/distribution.xml > "$PKG_WORK/distribution.xml"
    PKG="$DIST/DockPeek-$VERSION.pkg"
    SIGN_ARGS=()
    [[ -n "${DEVELOPER_ID_INSTALLER:-}" ]] && SIGN_ARGS=(--sign "$DEVELOPER_ID_INSTALLER")
    productbuild --distribution "$PKG_WORK/distribution.xml" \
        --resources Installer/resources \
        --package-path "$PKG_WORK" \
        ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
        "$PKG" >/dev/null

    if [[ -n "${NOTARY_PROFILE:-}" && -n "${DEVELOPER_ID_INSTALLER:-}" ]]; then
        xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$PKG"
    fi
    echo "Package: $PKG ($(du -h "$PKG" | cut -f1 | tr -d ' '))"

    # What the in-app updater downloads.
    ZIP="$DIST/DockPeek-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Update: $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"
fi

if [[ "$MODE" == "--release" ]]; then
    git push origin HEAD
    gh release create "v$VERSION" "$PKG" "$ZIP" --repo "$REPO" --target "$(git rev-parse HEAD)" \
        --title "DockPeek $VERSION" --notes "$NOTES"
    echo "Published: https://github.com/$REPO/releases/tag/v$VERSION"
fi
