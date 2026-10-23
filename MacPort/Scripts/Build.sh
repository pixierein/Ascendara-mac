#!/bin/bash
set -euo pipefail
Root="$(cd "$(dirname "$0")/.." && pwd)"
Configuration="${1:-release}"
case "$Configuration" in debug|release) ;; *) printf 'Use debug or release.\n' >&2; exit 1 ;; esac
cd "$Root"
"$Root/Scripts/SetupTools.sh"
if [[ "${ASCENDARA_SKIP_BUILD:-0}" != "1" ]]; then
    if [[ "$Configuration" == "release" ]]; then
        swift build -c release --disable-index-store -Xswiftc -Osize -Xswiftc -gnone
    else
        swift build -c debug
    fi
fi
BinaryDirectory="$(swift build -c "$Configuration" --show-bin-path)"
App="$Root/Build/Ascendara.app"
if [[ -d "$App/Contents/Resources" ]]; then rm -r "$App/Contents/Resources"; fi
mkdir -p "$App/Contents/MacOS" "$App/Contents/Resources"
cp "$BinaryDirectory/Ascendara" "$App/Contents/MacOS/Ascendara"
cp -R "$BinaryDirectory/AscendaraMac_Ascendara.bundle" "$App/Contents/Resources/"
DuplicateIcon="$App/Contents/Resources/AscendaraMac_Ascendara.bundle/AppIcon.icns"
if [[ -f "$DuplicateIcon" ]]; then rm "$DuplicateIcon"; fi
cp "$Root/Sources/Ascendara/Resources/AppIcon.icns" "$App/Contents/Resources/AppIcon.icns"
cp "$Root/../LICENSE" "$App/Contents/Resources/LICENSE"
mkdir -p "$App/Contents/Resources/Tools" "$App/Contents/Resources/Licenses/7zip"
cp "$Root/BuildTools/7zip/7zz" "$App/Contents/Resources/Tools/7zz"
cp "$Root/BuildTools/7zip/License.txt" "$Root/BuildTools/7zip/readme.txt" "$Root/BuildTools/7zip/History.txt" "$App/Contents/Resources/Licenses/7zip/"
if [[ -d "$Root/BuildTools/Highball" ]]; then
    mkdir -p "$App/Contents/Resources/Highball"
    for Resource in highball engine-manifest.json d3dmetal-license.txt LICENSE SOURCE.txt; do
        cp "$Root/BuildTools/Highball/$Resource" "$App/Contents/Resources/Highball/"
    done
fi
if [[ "$Configuration" == "release" ]]; then
    DuplicatePNG="$App/Contents/Resources/AscendaraMac_Ascendara.bundle/AppIcon.png"
    if [[ -f "$DuplicatePNG" ]]; then rm "$DuplicatePNG"; fi
    AppBinary="$App/Contents/MacOS/Ascendara"
    ArchiveTool="$App/Contents/Resources/Tools/7zz"
    read -r -a AppArchitectures <<< "$(xcrun lipo -archs "$AppBinary")"
    read -r -a ToolArchitectures <<< "$(xcrun lipo -archs "$ArchiveTool")"
    xcrun lipo "$ArchiveTool" -verify_arch "${AppArchitectures[@]}"
    if [[ "${#ToolArchitectures[@]}" -gt "${#AppArchitectures[@]}" ]]; then
        if [[ "${#AppArchitectures[@]}" == "1" ]]; then
            xcrun lipo "$ArchiveTool" -thin "${AppArchitectures[0]}" -output "$ArchiveTool.Thin"
        else
            ExtractArguments=()
            for Architecture in "${AppArchitectures[@]}"; do
                ExtractArguments+=(-extract "$Architecture")
            done
            xcrun lipo "$ArchiveTool" "${ExtractArguments[@]}" -output "$ArchiveTool.Thin"
        fi
        mv "$ArchiveTool.Thin" "$ArchiveTool"
    fi
    xcrun strip -u -r "$AppBinary" "$ArchiveTool"
    if [[ -f "$App/Contents/Resources/Highball/highball" ]]; then
        xcrun strip -u -r "$App/Contents/Resources/Highball/highball"
    fi
fi
cat > "$App/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>Ascendara</string>
    <key>CFBundleDisplayName</key><string>Ascendara</string>
    <key>CFBundleIdentifier</key><string>app.ascendara.native</string>
    <key>CFBundleExecutable</key><string>Ascendara</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>11.6.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>CFBundleURLTypes</key><array><dict>
        <key>CFBundleURLName</key><string>Ascendara Native</string>
        <key>CFBundleURLSchemes</key><array><string>ascendara-native</string><string>ascendara</string></array>
    </dict></array>
</dict></plist>
PLIST
SigningArguments=(--force --sign "${ASCENDARA_MAC_SIGN_IDENTITY:--}")
if [[ "${ASCENDARA_MAC_SIGN_IDENTITY:--}" != "-" ]]; then
    SigningArguments+=(--options runtime --timestamp)
fi
codesign "${SigningArguments[@]}" "$App/Contents/Resources/Tools/7zz"
if [[ -f "$App/Contents/Resources/Highball/highball" ]]; then
    codesign "${SigningArguments[@]}" "$App/Contents/Resources/Highball/highball"
fi
codesign "${SigningArguments[@]}" "$App"
if [[ "$Configuration" == "release" ]]; then
    CompactDirectory="$(mktemp -d "$Root/Build/.Compact.XXXXXX")"
    trap 'rm -r "$CompactDirectory"' EXIT
    ditto --noclone --hfsCompression "$App" "$CompactDirectory/Ascendara.app"
    codesign --verify --deep --strict "$CompactDirectory/Ascendara.app"
    rm -r "$App"
    mv "$CompactDirectory/Ascendara.app" "$App"
    rmdir "$CompactDirectory"
    trap - EXIT
fi
printf '\nBuilt %s\n' "$App"
du -sh "$App"
