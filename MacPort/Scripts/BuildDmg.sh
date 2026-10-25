#!/bin/bash
set -euo pipefail
Root="$(cd "$(dirname "$0")/.." && pwd)"
SkipBuild=0
Notarize=0
for Argument in "$@"; do
    case "$Argument" in
        --skip-build) SkipBuild=1 ;;
        --notarize) Notarize=1 ;;
        --help|-h)
            printf 'Usage: %s [--skip-build] [--notarize]\n' "$0"
            printf 'Build a release DMG in MacPort/Build. --skip-build uses the existing app.\n'
            printf 'Signing: ASCENDARA_MAC_SIGN_IDENTITY\nNotarization: ASCENDARA_MAC_NOTARY_PROFILE and --notarize\n'
            exit 0 ;;
        *) printf 'Unknown option: %s\n' "$Argument" >&2; exit 1 ;;
    esac
done
Identity="${ASCENDARA_MAC_SIGN_IDENTITY:--}"
Profile="${ASCENDARA_MAC_NOTARY_PROFILE:-}"
if [[ "$Notarize" == "1" && ( "$Identity" == "-" || -z "$Profile" ) ]]; then
    printf 'Notarization needs ASCENDARA_MAC_SIGN_IDENTITY and ASCENDARA_MAC_NOTARY_PROFILE.\n' >&2
    exit 1
fi
if [[ "$SkipBuild" == "0" ]]; then
    "$Root/Scripts/Build.sh" release
fi
App="$Root/Build/Ascendara.app"
if [[ ! -d "$App" ]]; then
    printf 'Build/Ascendara.app is missing. Run this script without --skip-build.\n' >&2
    exit 1
fi
codesign --verify --deep --strict "$App"
if [[ "$Notarize" == "1" ]]; then
    Executables=("$App" "$App/Contents/Resources/Tools/7zz" "$App/Contents/Resources/Tools/7zz-reclaim")
    if [[ -f "$App/Contents/Resources/Highball/highball" ]]; then
        Executables+=("$App/Contents/Resources/Highball/highball")
    fi
    for Executable in "${Executables[@]}"; do
        Signature="$(codesign --display --verbose=4 "$Executable" 2>&1)"
        if [[ "$Signature" != *"Authority=Developer ID Application:"* || "$Signature" != *"(runtime)"* || "$Signature" != *"Timestamp="* ]]; then
            printf 'Rebuild with a Developer ID Application identity, hardened runtime, and timestamp before notarizing: %s\n' "$Executable" >&2
            exit 1
        fi
    done
fi
Version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$App/Contents/Info.plist")"
if [[ ! "$Version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    printf 'Invalid app version: %s\n' "$Version" >&2
    exit 1
fi
Architecture="$(xcrun lipo -archs "$App/Contents/MacOS/Ascendara" | tr ' ' '-')"
Name="Ascendara-Mac-$Version-$Architecture"
Temporary="$(mktemp -d "$Root/Build/.Dmg.XXXXXX")"
trap 'rm -rf "$Temporary"' EXIT
Staging="$Temporary/Contents"
mkdir -p "$Staging"
ditto "$App" "$Staging/Ascendara.app"
ln -s /Applications "$Staging/Applications"
Image="$Temporary/$Name.dmg"
hdiutil create -volname 'Ascendara' -srcfolder "$Staging" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$Image"
if [[ "$Identity" != "-" ]]; then
    codesign --force --sign "$Identity" --timestamp --identifier app.ascendara.native.dmg "$Image"
    codesign --verify --strict "$Image"
fi
if [[ "$Notarize" == "1" ]]; then
    Report="$Root/Build/$Name.notarization.plist"
    SubmitStatus=0
    xcrun notarytool submit "$Image" --keychain-profile "$Profile" --wait --output-format plist > "$Report" || SubmitStatus=$?
    Status="$(/usr/libexec/PlistBuddy -c 'Print :status' "$Report" 2>/dev/null || true)"
    Submission="$(/usr/libexec/PlistBuddy -c 'Print :id' "$Report" 2>/dev/null || true)"
    if [[ -n "$Submission" ]]; then
        if ! xcrun notarytool log "$Submission" --keychain-profile "$Profile" "$Root/Build/$Name.notarization.json"; then
            printf 'Could not download the notarization log for submission %s.\n' "$Submission" >&2
        fi
    fi
    if [[ "$SubmitStatus" != "0" || "$Status" != "Accepted" ]]; then
        printf 'Notarization failed (%s). See %s.\n' "${Status:-submission error}" "$Report" >&2
        exit 1
    fi
    xcrun stapler staple "$Image"
    xcrun stapler validate "$Image"
fi
hdiutil verify "$Image"
cd "$Temporary"
shasum -a 256 "$Name.dmg" > "$Name.dmg.sha256"
mv "$Image" "$Name.dmg.sha256" "$Root/Build/"
printf '\nBuilt %s/Build/%s.dmg\n' "$Root" "$Name"
if [[ "$Notarize" == "0" ]]; then
    printf 'Notarization was not requested.\n'
fi
du -h "$Root/Build/$Name.dmg"
