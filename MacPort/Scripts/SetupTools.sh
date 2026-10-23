#!/bin/bash
set -euo pipefail
Root="$(cd "$(dirname "$0")/.." && pwd)"
Destination="$Root/BuildTools/7zip"
if [[ -x "$Destination/7zz" && -f "$Destination/License.txt" ]]; then exit 0; fi
Temporary="$(mktemp -d)"
trap 'rm -rf "$Temporary"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 --output "$Temporary/7zip.tar.xz" \
    'https://github.com/ip7z/7zip/releases/download/26.03/7z2603-mac.tar.xz'
Digest="$(shasum -a 256 "$Temporary/7zip.tar.xz" | cut -d ' ' -f 1)"
if [[ "$Digest" != '5ca87677072c59f5602e5c49baa27d4694bacd2259b4e507f0094249d4281480' ]]; then
    printf '7-Zip checksum mismatch.\n' >&2
    exit 1
fi
tar -xJf "$Temporary/7zip.tar.xz" -C "$Temporary" 7zz License.txt readme.txt History.txt
chmod +x "$Temporary/7zz"
lipo "$Temporary/7zz" -verify_arch arm64 x86_64
mkdir -p "$Destination"
cp "$Temporary/7zz" "$Temporary/License.txt" "$Temporary/readme.txt" "$Temporary/History.txt" "$Destination/"
printf 'Installed verified 7-Zip 26.03.\n'
