#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 OUTPUT_ARCHIVE WORK_DIRECTORY" >&2
  exit 64
fi

OUTPUT_ARCHIVE="$1"
WORK_DIRECTORY="$2"
SUPPORTED_MACOS="${BOURBON_MINIMUM_MACOS:?Set BOURBON_MINIMUM_MACOS from the Xcode project}"
RUNTIME_VERSION="1.0.2"
WINE_RELEASE="11.16"
WINE_ASSET="wine-devel-11.16-osx64.tar.xz"
WINE_ASSET_SHA256="6f9af818b7af6001aeed7818cb32bf0155598c5ea4e3b33380a03cf814e033cd"
WINE_ASSET_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/${WINE_RELEASE}/${WINE_ASSET}"

rm -rf "$WORK_DIRECTORY"
mkdir -p "$WORK_DIRECTORY/current" "$WORK_DIRECTORY/upstream" "$(dirname "$OUTPUT_ARCHIVE")"

RUNTIME_JSON="$WORK_DIRECTORY/current-runtime.json"
CURRENT_ARCHIVE="$WORK_DIRECTORY/current-runtime.tar.gz"
UPSTREAM_ARCHIVE="$WORK_DIRECTORY/$WINE_ASSET"

curl --fail --silent --show-error https://api.getbourbon.app/runtime/latest --output "$RUNTIME_JSON"
CURRENT_URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["archiveUrl"])' "$RUNTIME_JSON")"
CURRENT_SHA="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"])' "$RUNTIME_JSON")"
curl --fail --location --silent --show-error "$CURRENT_URL" --output "$CURRENT_ARCHIVE"
printf '%s  %s\n' "$CURRENT_SHA" "$CURRENT_ARCHIVE" | shasum -a 256 --check
tar -xzf "$CURRENT_ARCHIVE" -C "$WORK_DIRECTORY/current"

curl --fail --location --silent --show-error "$WINE_ASSET_URL" --output "$UPSTREAM_ARCHIVE"
printf '%s  %s\n' "$WINE_ASSET_SHA256" "$UPSTREAM_ARCHIVE" | shasum -a 256 --check
tar -xJf "$UPSTREAM_ARCHIVE" -C "$WORK_DIRECTORY/upstream"

UPSTREAM_WINE="$WORK_DIRECTORY/upstream/Wine Devel.app/Contents/Resources/wine"
test -x "$UPSTREAM_WINE/bin/wine"
test -x "$UPSTREAM_WINE/bin/wineserver"
test -f "$UPSTREAM_WINE/lib/wine/x86_64-unix/ntdll.so"

rm -rf "$WORK_DIRECTORY/current/Libraries/Wine"
ditto "$UPSTREAM_WINE" "$WORK_DIRECTORY/current/Libraries/Wine"

python3 - "$WORK_DIRECTORY/current/Libraries" <<PY
import json
import plistlib
import sys
from pathlib import Path

libraries = Path(sys.argv[1])
version = {"version": "$RUNTIME_VERSION"}
with (libraries / "BourbonWineVersion.plist").open("wb") as destination:
    plistlib.dump(version, destination, fmt=plistlib.FMT_XML, sort_keys=True)

metadata = {
    "runtimeVersion": "$RUNTIME_VERSION",
    "wineVersion": "wine-$WINE_RELEASE",
    "sourceRepository": "Gcenx/macOS_Wine_builds",
    "sourceRelease": "$WINE_RELEASE",
    "sourceAsset": "$WINE_ASSET",
    "sourceAssetSHA256": "$WINE_ASSET_SHA256",
    "maximumMinimumMacOS": "$SUPPORTED_MACOS",
}
with (libraries / "BourbonWineRuntime.json").open("w", encoding="utf-8") as destination:
    json.dump(metadata, destination, indent=2, sort_keys=True)
    destination.write("\n")
PY

tar -czf "$OUTPUT_ARCHIVE" -C "$WORK_DIRECTORY/current" Libraries
shasum -a 256 "$OUTPUT_ARCHIVE" > "$OUTPUT_ARCHIVE.sha256"
echo "Prepared corrected BourbonWine $RUNTIME_VERSION with Wine $WINE_RELEASE at $OUTPUT_ARCHIVE"
