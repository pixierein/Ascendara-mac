#!/bin/bash
set -euo pipefail
Root="$(cd "$(dirname "$0")/.." && pwd)"
Configuration="${1:-release}"
case "$Configuration" in debug|release) ;; *) printf 'Use debug or release.\n' >&2; exit 1 ;; esac
cd "$Root"
"$Root/Scripts/SetupTools.sh"
python3 "$Root/Scripts/BuildArchiveTool.py"
if [[ "$Configuration" == "release" && ! -x "$Root/BuildTools/Highball/highball" ]]; then
    python3 "$Root/Scripts/BuildHighball.py"
fi
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
Helpers=(AscendaraDownloadWorker AscendaraGameHandler AscendaraTorrentHandler AscendaraCrashReporter)
for Helper in "${Helpers[@]}"; do
    cp "$BinaryDirectory/$Helper" "$App/Contents/MacOS/$Helper"
done
cp -R "$BinaryDirectory/AscendaraMac_Ascendara.bundle" "$App/Contents/Resources/"
DuplicateIcon="$App/Contents/Resources/AscendaraMac_Ascendara.bundle/AppIcon.icns"
if [[ -f "$DuplicateIcon" ]]; then rm "$DuplicateIcon"; fi
cp "$Root/Source/Ascendara/Resources/AppIcon.icns" "$App/Contents/Resources/AppIcon.icns"
cp "$Root/../LICENSE" "$App/Contents/Resources/LICENSE"
BundledIndex="$Root/Private/ascendara_games.json"
if [[ "$Configuration" == "release" ]]; then
    IndexDownload="$App/Contents/Resources/ascendara_games.json.download"
    if curl --fail --silent --show-error --location --max-time 60 \
        'https://api.ascendara.app/json/v2/games' -o "$IndexDownload" \
        && python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); assert isinstance(data.get("games"),list) and len(data["games"]) > 0' "$IndexDownload"; then
        mv "$IndexDownload" "$App/Contents/Resources/ascendara_games.json"
        mkdir -p "$Root/Private"
        cp "$App/Contents/Resources/ascendara_games.json" "$BundledIndex"
    else
        rm -f "$IndexDownload"
        if [[ -f "$BundledIndex" ]]; then cp "$BundledIndex" "$App/Contents/Resources/ascendara_games.json"; fi
    fi
fi
mkdir -p "$App/Contents/Resources/Tools" "$App/Contents/Resources/Licenses/7zip"
cp "$Root/BuildTools/7zip/7zz" "$App/Contents/Resources/Tools/7zz"
cp "$Root/BuildTools/7zip/7zz-reclaim" "$App/Contents/Resources/Tools/7zz-reclaim"
cp "$Root/BuildTools/7zip/License.txt" "$Root/BuildTools/7zip/readme.txt" "$Root/BuildTools/7zip/History.txt" "$App/Contents/Resources/Licenses/7zip/"
cp "$Root/BuildTools/7zip/7zip-source.tar.xz" "$Root/BuildTools/7zip/ArchiveReclamation.hpp" "$Root/BuildTools/7zip/BuildArchiveTool.py" "$App/Contents/Resources/Licenses/7zip/"
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
    AppArchitectures="$(xcrun dwarfdump --uuid "$AppBinary" | sed -nE 's/^UUID:.*\(([^)]+)\).*/\1/p' | tr '\n' ' ')"
    ToolArchitectures="$(xcrun dwarfdump --uuid "$ArchiveTool" | sed -nE 's/^UUID:.*\(([^)]+)\).*/\1/p' | tr '\n' ' ')"
    if [[ -z "$AppArchitectures" ]]; then
        printf 'Could not determine the app architecture.\n' >&2
        exit 1
    fi
    ThinningArguments=()
    for Architecture in $AppArchitectures; do
        case " $ToolArchitectures " in
            *" $Architecture "*) ThinningArguments+=(--arch "$Architecture") ;;
            *) printf 'Archive helper does not support %s.\n' "$Architecture" >&2; exit 1 ;;
        esac
    done
    ditto --noclone "${ThinningArguments[@]}" "$ArchiveTool" "$ArchiveTool.Thin"
    mv "$ArchiveTool.Thin" "$ArchiveTool"
    HelperBinaries=()
    for Helper in "${Helpers[@]}"; do HelperBinaries+=("$App/Contents/MacOS/$Helper"); done
    xcrun strip -u -r "$AppBinary" "${HelperBinaries[@]}" "$ArchiveTool"
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
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>3</string>
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
codesign "${SigningArguments[@]}" "$App/Contents/Resources/Tools/7zz-reclaim"
for Helper in "${Helpers[@]}"; do
    codesign "${SigningArguments[@]}" "$App/Contents/MacOS/$Helper"
done
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
