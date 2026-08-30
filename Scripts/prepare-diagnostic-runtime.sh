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
VULKAN_LOADER_VERSION="1.4.350"
VULKAN_LOADER_COMMIT="a9e72c66d5cb79911eb9a9063bf4016dd0a3a123"
VULKAN_HEADERS_COMMIT="8864cdc896bbc2a9b6eb36b3218fc9ef57908d77"

rm -rf "$WORK_DIRECTORY"
mkdir -p "$WORK_DIRECTORY/current" "$WORK_DIRECTORY/upstream" "$(dirname "$OUTPUT_ARCHIVE")"

RUNTIME_JSON="$WORK_DIRECTORY/current-runtime.json"
CURRENT_ARCHIVE="$WORK_DIRECTORY/current-runtime.tar.gz"
UPSTREAM_ARCHIVE="$WORK_DIRECTORY/$WINE_ASSET"
VULKAN_SOURCE_ROOT="$WORK_DIRECTORY/vulkan-source"
VULKAN_HEADERS_SOURCE="$VULKAN_SOURCE_ROOT/Vulkan-Headers"
VULKAN_HEADERS_BUILD="$VULKAN_SOURCE_ROOT/Vulkan-Headers-build"
VULKAN_HEADERS_INSTALL="$VULKAN_SOURCE_ROOT/Vulkan-Headers-install"
VULKAN_LOADER_SOURCE="$VULKAN_SOURCE_ROOT/Vulkan-Loader"
VULKAN_LOADER_BUILD="$VULKAN_SOURCE_ROOT/Vulkan-Loader-build"
VULKAN_LOADER_INSTALL="$VULKAN_SOURCE_ROOT/Vulkan-Loader-install"

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

# The upstream Wine archive currently bundles Vulkan Loader dylibs built with
# a macOS 26 deployment target. Rebuild that open-source component on the
# macOS 14 runner instead of rewriting Mach-O metadata or shimming symbols.
git init -q "$VULKAN_HEADERS_SOURCE"
git -C "$VULKAN_HEADERS_SOURCE" remote add origin https://github.com/KhronosGroup/Vulkan-Headers.git
git -C "$VULKAN_HEADERS_SOURCE" fetch --depth 1 origin "$VULKAN_HEADERS_COMMIT"
git -C "$VULKAN_HEADERS_SOURCE" checkout --detach FETCH_HEAD
test "$(git -C "$VULKAN_HEADERS_SOURCE" rev-parse HEAD)" = "$VULKAN_HEADERS_COMMIT"

cmake -S "$VULKAN_HEADERS_SOURCE" -B "$VULKAN_HEADERS_BUILD" \
  -D CMAKE_BUILD_TYPE=Release \
  -D CMAKE_INSTALL_PREFIX="$VULKAN_HEADERS_INSTALL"
cmake --build "$VULKAN_HEADERS_BUILD" --target install --parallel 2

git init -q "$VULKAN_LOADER_SOURCE"
git -C "$VULKAN_LOADER_SOURCE" remote add origin https://github.com/KhronosGroup/Vulkan-Loader.git
git -C "$VULKAN_LOADER_SOURCE" fetch --depth 1 origin "$VULKAN_LOADER_COMMIT"
git -C "$VULKAN_LOADER_SOURCE" checkout --detach FETCH_HEAD
test "$(git -C "$VULKAN_LOADER_SOURCE" rev-parse HEAD)" = "$VULKAN_LOADER_COMMIT"

cmake -S "$VULKAN_LOADER_SOURCE" -B "$VULKAN_LOADER_BUILD" \
  -D CMAKE_BUILD_TYPE=Release \
  -D CMAKE_INSTALL_PREFIX="$VULKAN_LOADER_INSTALL" \
  -D CMAKE_OSX_ARCHITECTURES=x86_64 \
  -D CMAKE_OSX_DEPLOYMENT_TARGET="$SUPPORTED_MACOS" \
  -D VULKAN_HEADERS_INSTALL_DIR="$VULKAN_HEADERS_INSTALL" \
  -D BUILD_TESTS=OFF
cmake --build "$VULKAN_LOADER_BUILD" --target install --parallel 2

WINE_LIB="$WORK_DIRECTORY/current/Libraries/Wine/lib"
rm -f "$WINE_LIB"/libvulkan*.dylib
cp -a "$VULKAN_LOADER_INSTALL/lib"/libvulkan*.dylib "$WINE_LIB/"
test -f "$WINE_LIB/libvulkan.1.dylib"
test -f "$WINE_LIB/libvulkan.dylib"

VULKAN_LICENSE_DIR="$WORK_DIRECTORY/current/Libraries/Wine/share/licenses/vulkan-loader"
mkdir -p "$VULKAN_LICENSE_DIR"
cp "$VULKAN_LOADER_SOURCE/LICENSE.txt" "$VULKAN_LICENSE_DIR/LICENSE.txt"

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
    "vulkanLoaderVersion": "$VULKAN_LOADER_VERSION",
    "vulkanLoaderCommit": "$VULKAN_LOADER_COMMIT",
    "vulkanHeadersCommit": "$VULKAN_HEADERS_COMMIT",
    "maximumMinimumMacOS": "$SUPPORTED_MACOS",
}
with (libraries / "BourbonWineRuntime.json").open("w", encoding="utf-8") as destination:
    json.dump(metadata, destination, indent=2, sort_keys=True)
    destination.write("\n")
PY

tar -czf "$OUTPUT_ARCHIVE" -C "$WORK_DIRECTORY/current" Libraries
shasum -a 256 "$OUTPUT_ARCHIVE" > "$OUTPUT_ARCHIVE.sha256"
echo "Prepared corrected BourbonWine $RUNTIME_VERSION with Wine $WINE_RELEASE at $OUTPUT_ARCHIVE"
