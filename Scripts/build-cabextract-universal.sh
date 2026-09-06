#!/usr/bin/env bash
# Build the bundled Universal 2 cabextract binary from the official 1.11 source.
# Requires the macOS SDK, make, curl, and lipo.
set -euo pipefail

VERSION=1.11
SOURCE_URL="https://www.cabextract.org.uk/cabextract-${VERSION}.tar.gz"
SOURCE_SHA256="b5546db1155e4c718ff3d4b278573604f30dd64c3c5bfd4657cd089b823a3ac6"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_PATH="${1:-$REPOSITORY_ROOT/Source/Libraries/cabextract}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bourbon-cabextract.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

ARCHIVE="$WORK_DIR/cabextract-${VERSION}.tar.gz"
curl --fail --location --retry 3 --output "$ARCHIVE" "$SOURCE_URL"
printf '%s  %s\n' "$SOURCE_SHA256" "$ARCHIVE" | shasum -a 256 --check
tar -xzf "$ARCHIVE" -C "$WORK_DIR"

for ARCH in arm64 x86_64; do
  BUILD_DIR="$WORK_DIR/build-$ARCH"
  mkdir -p "$BUILD_DIR"
  (
    cd "$BUILD_DIR"
    CFLAGS="-arch $ARCH -mmacosx-version-min=14.0" \
    LDFLAGS="-arch $ARCH -mmacosx-version-min=14.0" \
      "$WORK_DIR/cabextract-${VERSION}/configure" --disable-shared
    make
  )
done

mkdir -p "$(dirname "$OUTPUT_PATH")"
lipo -create \
  "$WORK_DIR/build-arm64/cabextract" \
  "$WORK_DIR/build-x86_64/cabextract" \
  -output "$OUTPUT_PATH"
lipo -verify_arch arm64 x86_64 "$OUTPUT_PATH"
file "$OUTPUT_PATH"
shasum -a 256 "$OUTPUT_PATH"
