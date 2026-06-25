#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  Scripts/import-sikarugir-engine.sh [sikarugir-engine.tar.xz] [output-archive]

Converts a Sikarugir Wineskin-style engine archive into Whisky's
Libraries.tar.gz layout without downloading anything, invoking Homebrew, or
running the legacy GPTK source build.

Defaults:
  input archive:  /tmp/WS12WhiskyWine2.5.0_3.tar.xz
  output archive: build/SikarugirWhiskyWine/Libraries.tar.gz

Optional local sidecars, no downloads:
  SIKARUGIR_DXVK_DIR       Default: ../WhiskyBuilder/DXVK when present
  SIKARUGIR_WINETRICKS     Path to a local winetricks executable
  SIKARUGIR_VERBS_TXT      Path to a local winetricks verbs.txt
  SIKARUGIR_HOMEBREW_LIB_DIR
                           Default: /opt/homebrew/lib; used only to bundle
                           already-installed runtime dylibs for testing.

Expected Sikarugir input:
  wswine.bundle/
    bin/
    lib/
    share/
    version

Generated Whisky archive:
  Libraries/
    Wine/
      bin/
      lib/
      share/
      version
    GPTKVersion.plist
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

input_archive="${1:-/tmp/WS12WhiskyWine2.5.0_3.tar.xz}"
output_archive="${2:-$repo_root/build/SikarugirWhiskyWine/Libraries.tar.gz}"
output_root="$(dirname "$output_archive")"
staging_root="$output_root/staging"
extract_root="$output_root/extracted"
libraries_dir="$staging_root/Libraries"
wine_dir="$libraries_dir/Wine"
source_engine_dir="$extract_root/wswine.bundle"
default_dxvk_dir="$repo_root/../WhiskyBuilder/DXVK"
dxvk_dir="${SIKARUGIR_DXVK_DIR:-}"
winetricks_path="${SIKARUGIR_WINETRICKS:-}"
verbs_path="${SIKARUGIR_VERBS_TXT:-}"
homebrew_lib_dir="${SIKARUGIR_HOMEBREW_LIB_DIR:-/opt/homebrew/lib}"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
}

require_path() {
  local path="$1"
  local label="$2"
  if [[ ! -e "$path" ]]; then
    echo "Missing $label: $path" >&2
    exit 1
  fi
}

require_dir() {
  local path="$1"
  local label="$2"
  if [[ ! -d "$path" ]]; then
    echo "Missing $label directory: $path" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "$path" ]]; then
    echo "Missing $label file: $path" >&2
    exit 1
  fi
}

resolve_path() {
  local path="$1"
  local target
  while [[ -L "$path" ]]; do
    target="$(readlink "$path")"
    if [[ "$target" = /* ]]; then
      path="$target"
    else
      path="$(dirname "$path")/$target"
    fi
  done
  local dir
  dir="$(cd "$(dirname "$path")" && pwd -P)"
  echo "$dir/$(basename "$path")"
}

is_system_dylib() {
  local path="$1"
  [[ "$path" == /usr/lib/* || "$path" == /System/Library/* ]]
}

is_homebrew_dylib() {
  local path="$1"
  [[ "$path" == /opt/homebrew/* || "$path" == "$homebrew_lib_dir"/* ]]
}

copied_runtime_files=""

has_copied_runtime_file() {
  local basename="$1"
  [[ "$copied_runtime_files" == *"|$basename|"* ]]
}

copy_runtime_dylib_closure() {
  local dylib_path="$1"
  local resolved
  resolved="$(resolve_path "$dylib_path")"
  local basename
  basename="$(basename "$dylib_path")"

  if has_copied_runtime_file "$basename"; then
    return
  fi

  echo "Bundling runtime dependency: $basename"
  cp "$resolved" "$wine_dir/lib/$basename"
  chmod u+w "$wine_dir/lib/$basename"
  copied_runtime_files="${copied_runtime_files}|${basename}|"

  while IFS= read -r dependency; do
    if [[ -z "$dependency" ]] || is_system_dylib "$dependency"; then
      continue
    fi
    if is_homebrew_dylib "$dependency"; then
      copy_runtime_dylib_closure "$dependency"
    fi
  done < <(otool -L "$resolved" | awk 'NR > 1 { print $1 }')
}

rewrite_bundled_runtime_dylibs() {
  local dylib
  shopt -s nullglob
  for dylib in "$wine_dir/lib"/*.dylib; do
    local basename
    basename="$(basename "$dylib")"
    if ! has_copied_runtime_file "$basename"; then
      continue
    fi

    install_name_tool -id "@rpath/$basename" "$dylib"
    while IFS= read -r dependency; do
      if [[ -z "$dependency" ]] || is_system_dylib "$dependency"; then
        continue
      fi

      local dependency_basename
      dependency_basename="$(basename "$dependency")"
      if has_copied_runtime_file "$dependency_basename"; then
        install_name_tool -change "$dependency" "@rpath/$dependency_basename" "$dylib"
      fi
    done < <(otool -L "$dylib" | awk 'NR > 1 { print $1 }')

    if command -v codesign >/dev/null 2>&1; then
      codesign --force --sign - "$dylib" >/dev/null
    fi
  done
  shopt -u nullglob
}

bundle_required_runtime_dylibs() {
  require_command otool
  require_command install_name_tool

  local missing=0
  local dependency
  for dependency in libfreetype.6.dylib libgnutls.30.dylib; do
    local dependency_path="$homebrew_lib_dir/$dependency"
    if [[ ! -e "$dependency_path" ]]; then
      local package="${dependency#lib}"
      package="${package%%.*}"
      echo "Missing local dependency: $package. Install with brew install $package" >&2
      missing=1
      continue
    fi
    copy_runtime_dylib_closure "$dependency_path"
  done

  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi

  rewrite_bundled_runtime_dylibs
}

version_component() {
  local index="$1"
  local fallback="$2"
  local value
  value="$(printf '%s\n' "$version_string" | sed -E 's/^[^0-9]*([0-9]+)(\\.([0-9]+))?(\\.([0-9]+))?.*$/\1 \3 \5/' | awk -v index="$index" '{ print $index }')"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$value"
  else
    echo "$fallback"
  fi
}

require_command tar
require_command plutil

require_file "$input_archive" "Sikarugir engine archive"

case "$input_archive" in
  *.tar.xz|*.txz|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar)
    ;;
  *)
    echo "Unsupported input archive extension: $input_archive" >&2
    echo "Expected a tar archive such as .tar.xz or .tar.gz." >&2
    exit 1
    ;;
esac

echo "Recreating import staging directory: $output_root"
rm -rf "$staging_root" "$extract_root"
mkdir -p "$extract_root" "$libraries_dir" "$output_root"

echo "Extracting Sikarugir engine archive: $input_archive"
tar -xf "$input_archive" -C "$extract_root"

require_dir "$source_engine_dir" "Sikarugir wswine.bundle"
require_dir "$source_engine_dir/bin" "Sikarugir engine bin"
require_dir "$source_engine_dir/lib" "Sikarugir engine lib"
require_dir "$source_engine_dir/share" "Sikarugir engine share"
require_file "$source_engine_dir/version" "Sikarugir engine version"

if [[ ! -x "$source_engine_dir/bin/wineserver" ]]; then
  echo "Missing executable Wine server: $source_engine_dir/bin/wineserver" >&2
  echo "Available top-level Sikarugir engine binaries:" >&2
  find "$source_engine_dir/bin" -maxdepth 1 -mindepth 1 -print | sort >&2
  exit 1
fi

echo "Copying wswine.bundle contents into Whisky Libraries/Wine"
mkdir -p "$wine_dir"
cp -a "$source_engine_dir/." "$wine_dir/"

if [[ ! -e "$wine_dir/bin/wine64" && -e "$wine_dir/bin/wine" ]]; then
  echo "Adding compatibility symlink: Libraries/Wine/bin/wine64 -> wine"
  ln -s wine "$wine_dir/bin/wine64"
fi
if [[ ! -e "$wine_dir/bin/wine64-preloader" && -e "$wine_dir/bin/wine-preloader" ]]; then
  echo "Adding compatibility symlink: Libraries/Wine/bin/wine64-preloader -> wine-preloader"
  ln -s wine-preloader "$wine_dir/bin/wine64-preloader"
fi

if [[ -d "$wine_dir/.brew" ]]; then
  rm -rf "$wine_dir/.brew"
fi
if [[ -d "$wine_dir/include" ]]; then
  rm -rf "$wine_dir/include"
fi
if [[ -d "$wine_dir/share/man" ]]; then
  rm -rf "$wine_dir/share/man"
fi

bundle_required_runtime_dylibs

version_string="$(head -n 1 "$wine_dir/version" | tr -d '\r')"
if [[ -z "$version_string" ]]; then
  version_string="Sikarugir WhiskyWine"
fi
version_major="$(version_component 1 2)"
version_minor="$(version_component 2 5)"
version_patch="$(version_component 3 0)"

echo "Writing GPTKVersion.plist from Sikarugir version: $version_string"
cat > "$libraries_dir/GPTKVersion.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>version</key>
  <dict>
    <key>major</key>
    <integer>${version_major}</integer>
    <key>minor</key>
    <integer>${version_minor}</integer>
    <key>patch</key>
    <integer>${version_patch}</integer>
    <key>preRelease</key>
    <string></string>
    <key>build</key>
    <string></string>
  </dict>
</dict>
</plist>
PLIST
plutil -lint "$libraries_dir/GPTKVersion.plist" >/dev/null

for optional_name in winetricks verbs.txt DXVK; do
  if [[ -e "$extract_root/$optional_name" ]]; then
    echo "Copying optional sidecar: $optional_name"
    cp -a "$extract_root/$optional_name" "$libraries_dir/"
  elif [[ -e "$source_engine_dir/$optional_name" ]]; then
    echo "Copying optional engine sidecar: $optional_name"
    cp -a "$source_engine_dir/$optional_name" "$libraries_dir/"
  fi
done

if [[ ! -e "$libraries_dir/DXVK" ]]; then
  if [[ -z "$dxvk_dir" && -d "$default_dxvk_dir" ]]; then
    dxvk_dir="$default_dxvk_dir"
  fi
  if [[ -n "$dxvk_dir" ]]; then
    require_dir "$dxvk_dir" "local DXVK sidecar"
    echo "Copying local DXVK sidecar: $dxvk_dir"
    cp -a "$dxvk_dir" "$libraries_dir/DXVK"
  else
    echo "Warning: no local DXVK sidecar found; verifier will reject this archive." >&2
  fi
fi

if [[ ! -e "$libraries_dir/winetricks" ]]; then
  if [[ -n "$winetricks_path" ]]; then
    require_file "$winetricks_path" "local winetricks executable"
    echo "Copying local winetricks sidecar: $winetricks_path"
    cp -a "$winetricks_path" "$libraries_dir/winetricks"
    chmod +x "$libraries_dir/winetricks"
  else
    echo "Writing placeholder winetricks sidecar; set SIKARUGIR_WINETRICKS for full winetricks support." >&2
    cat > "$libraries_dir/winetricks" <<'WINETRICKS'
#!/usr/bin/env bash
echo "winetricks was not bundled with this Sikarugir import. Rebuild with SIKARUGIR_WINETRICKS=/path/to/winetricks for winetricks support." >&2
exit 1
WINETRICKS
    chmod +x "$libraries_dir/winetricks"
  fi
fi

if [[ ! -e "$libraries_dir/verbs.txt" ]]; then
  if [[ -n "$verbs_path" ]]; then
    require_file "$verbs_path" "local winetricks verbs list"
    echo "Copying local verbs sidecar: $verbs_path"
    cp -a "$verbs_path" "$libraries_dir/verbs.txt"
  else
    echo "Writing empty verbs.txt sidecar; set SIKARUGIR_VERBS_TXT=/path/to/verbs.txt for winetricks metadata." >&2
    : > "$libraries_dir/verbs.txt"
  fi
fi

echo "Validating generated Whisky layout"
require_dir "$wine_dir/bin" "Whisky Wine bin"
require_dir "$wine_dir/lib" "Whisky Wine lib"
require_dir "$wine_dir/share" "Whisky Wine share"
require_file "$wine_dir/version" "Whisky Wine version"
require_path "$wine_dir/bin/wine64" "Whisky Wine wine64 compatibility entry"
require_path "$wine_dir/bin/wineserver" "Whisky Wine wineserver"
require_path "$libraries_dir/GPTKVersion.plist" "Whisky GPTKVersion.plist"
require_path "$libraries_dir/winetricks" "Whisky winetricks sidecar"
require_path "$libraries_dir/verbs.txt" "Whisky verbs sidecar"
require_path "$libraries_dir/DXVK" "Whisky DXVK sidecar"

echo "Packaging Whisky archive: $output_archive"
rm -f "$output_archive"
tar -C "$staging_root" -czf "$output_archive" Libraries

echo "Archive top-level entries:"
tar -tf "$output_archive" | head -40

echo "Sikarugir WhiskyWine archive ready: $output_archive"
