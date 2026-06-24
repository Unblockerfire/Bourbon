#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  Scripts/verify-whiskywine-archive.sh /path/to/Libraries.tar.gz

Verifies that a WhiskyWine archive is a readable tar.gz with the top-level
Libraries/ folder and the files Whisky expects after extraction.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
  usage
  exit $([[ $# -eq 1 ]] && [[ "${1:-}" =~ ^-h|--help$ ]] && echo 0 || echo 2)
fi

archive_path="$1"

if [[ ! -f "$archive_path" ]]; then
  echo "Archive does not exist: $archive_path" >&2
  exit 1
fi

if ! gzip -t "$archive_path"; then
  echo "Archive is not a valid gzip stream: $archive_path" >&2
  exit 1
fi

entries="$(tar -tzf "$archive_path")"

contains_entry() {
  local entry="$1"
  grep -Fxq "$entry" <<< "$entries"
}

contains_prefix() {
  local prefix="$1"
  grep -q "^${prefix}" <<< "$entries"
}

if ! contains_entry "Libraries" && ! contains_entry "Libraries/" && ! contains_prefix "Libraries/"; then
  echo "Archive must contain a top-level Libraries/ folder." >&2
  exit 1
fi

required_entries=(
  "Libraries/Wine/bin/wine64"
  "Libraries/Wine/bin/wineserver"
  "Libraries/Wine/lib"
  "Libraries/winetricks"
  "Libraries/verbs.txt"
)

for entry in "${required_entries[@]}"; do
  if ! contains_entry "$entry" && ! contains_entry "${entry}/" && ! contains_prefix "${entry}/"; then
    echo "Archive is missing expected entry: $entry" >&2
    exit 1
  fi
done

if ! contains_entry "Libraries/GPTKVersion.plist" && ! contains_entry "Libraries/WhiskyWineVersion.plist"; then
  echo "Archive is missing GPTKVersion.plist or WhiskyWineVersion.plist." >&2
  exit 1
fi

if ! contains_entry "Libraries/DXVK" && ! contains_entry "Libraries/DXVK/" && ! contains_prefix "Libraries/DXVK/"; then
  echo "Archive is missing Libraries/DXVK." >&2
  exit 1
fi

if ! contains_entry "Libraries/Wine/lib/D3DMetal.framework" \
  && ! contains_entry "Libraries/Wine/lib/D3DMetal.framework/" \
  && ! contains_prefix "Libraries/Wine/lib/D3DMetal.framework/"; then
  echo "Warning: D3DMetal.framework was not found in the archive." >&2
fi

if ! contains_entry "Libraries/Wine/lib/libd3dshared.dylib"; then
  echo "Warning: libd3dshared.dylib was not found in the archive." >&2
fi

echo "Archive looks like a WhiskyWine Libraries.tar.gz: $archive_path"
