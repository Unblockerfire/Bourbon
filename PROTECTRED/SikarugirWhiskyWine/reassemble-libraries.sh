#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
output_dir="$repo_root/build/SikarugirWhiskyWine"
output_archive="$output_dir/Libraries.tar.gz"

mkdir -p "$output_dir"
cat "$script_dir"/Libraries.tar.gz.part-* > "$output_archive"

if command -v shasum >/dev/null 2>&1; then
  expected="$(awk '{print $1}' "$script_dir/Libraries.tar.gz.sha256")"
  actual="$(shasum -a 256 "$output_archive" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "Checksum mismatch for $output_archive" >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    exit 1
  fi
fi

echo "Restored $output_archive"
