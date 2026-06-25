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
  SIKARUGIR_RUNTIME_LIB_DIR
                           Path to an extracted x86_64 runtime lib directory.
                           The importer looks in this directory, or its lib/
                           child, for FreeType/GnuTLS and their dylib closure.

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
runtime_lib_dir="${SIKARUGIR_RUNTIME_LIB_DIR:-}"

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

binary_archs() {
  local path="$1"
  local archs
  archs="$(lipo -archs "$path" 2>/dev/null || true)"
  if [[ -n "$archs" ]]; then
    echo "$archs"
    return
  fi

  file "$path" | sed -E 's/.*Mach-O [^ ]+ ([^ ]+) .*/\1/'
}

has_arch() {
  local archs="$1"
  local arch="$2"
  [[ " $archs " == *" $arch "* ]]
}

is_arch_compatible() {
  local dependency_archs="$1"
  local engine_arch
  for engine_arch in $wine_binary_archs; do
    if has_arch "$dependency_archs" "$engine_arch"; then
      return 0
    fi
  done
  return 1
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

copied_runtime_files=""
visiting_runtime_files=""
required_runtime_dylibs=(
  libfreetype.6.dylib
  libgnutls.30.dylib
)
optional_runtime_dylibs=(
  libgmp.10.dylib
)
managed_runtime_dylibs=(
  libfreetype.6.dylib
  libgnutls.30.dylib
  libasprintf.0.dylib
  libcharset.1.dylib
  libffi.8.dylib
  libgmp.10.dylib
  libhogweed.6.dylib
  libhogweed.6.6.dylib
  libhogweed.7.dylib
  libhogweed.7.0.dylib
  libiconv.2.dylib
  libidn2.0.dylib
  libintl.8.dylib
  libnettle.8.dylib
  libnettle.8.6.dylib
  libnettle.9.dylib
  libnettle.9.0.dylib
  libp11-kit.0.dylib
  libpng16.16.dylib
  libtasn1.6.dylib
  libtextstyle.0.dylib
  libunistring.2.dylib
  libunistring.5.dylib
  libz.1.dylib
  libz.1.2.12.dylib
  libzlib.dylib
)

has_copied_runtime_file() {
  local basename="$1"
  [[ "$copied_runtime_files" == *"|$basename|"* ]]
}

is_visiting_runtime_file() {
  local basename="$1"
  [[ "$visiting_runtime_files" == *"|$basename|"* ]]
}

remove_managed_runtime_dylibs() {
  local dylib
  for dylib in "${managed_runtime_dylibs[@]}"; do
    rm -f "$wine_dir/lib/$dylib"
  done
}

configured_runtime_lib_dir() {
  if [[ -z "$runtime_lib_dir" ]]; then
    return 1
  fi
  if [[ -d "$runtime_lib_dir/lib" ]]; then
    echo "$runtime_lib_dir/lib"
  elif [[ -d "$runtime_lib_dir" ]]; then
    echo "$runtime_lib_dir"
  else
    return 1
  fi
}

dependency_basename() {
  local dependency="$1"
  case "$dependency" in
    @rpath/*|@loader_path/*|@executable_path/*)
      basename "$dependency"
      ;;
    *)
      basename "$dependency"
      ;;
  esac
}

runtime_dependency_path() {
  local dependency="$1"
  local basename
  basename="$(dependency_basename "$dependency")"
  if [[ -n "$runtime_source_lib_dir" && -f "$runtime_source_lib_dir/$basename" ]]; then
    echo "$runtime_source_lib_dir/$basename"
    return 0
  fi
  return 1
}

has_rpath() {
  local binary="$1"
  local rpath="$2"
  otool -l "$binary" | grep -A2 LC_RPATH | grep -Fq "path $rpath "
}

ensure_rpath() {
  local binary="$1"
  local rpath="$2"
  if ! has_rpath "$binary" "$rpath"; then
    install_name_tool -add_rpath "$rpath" "$binary"
  fi
}

sign_binary_if_possible() {
  local binary="$1"
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$binary" >/dev/null
  fi
}

copy_runtime_dylib_closure() {
  local dylib_path="$1"
  local resolved
  resolved="$(resolve_path "$dylib_path")"
  local basename
  basename="$(basename "$dylib_path")"
  local dependency_archs
  dependency_archs="$(binary_archs "$resolved")"

  if has_copied_runtime_file "$basename"; then
    return
  fi
  if is_visiting_runtime_file "$basename"; then
    return
  fi

  if ! is_arch_compatible "$dependency_archs"; then
    echo "Warning: not bundling incompatible runtime dependency: $basename" >&2
    echo "  Wine binary architectures: $wine_binary_archs" >&2
    echo "  Dependency architectures: $dependency_archs" >&2
    return 1
  fi

  visiting_runtime_files="${visiting_runtime_files}|${basename}|"

  while IFS= read -r dependency; do
    if [[ -z "$dependency" ]] || is_system_dylib "$dependency"; then
      continue
    fi
    local dependency_path
    if dependency_path="$(runtime_dependency_path "$dependency")"; then
      copy_runtime_dylib_closure "$dependency_path" || return 1
    else
      echo "Warning: missing runtime dependency for $basename: $(dependency_basename "$dependency")" >&2
      echo "  Looked in: $runtime_source_lib_dir" >&2
      return 1
    fi
  done < <(otool -L "$resolved" | awk 'NR > 1 { print $1 }')

  echo "Bundling runtime dependency: $basename"
  cp "$resolved" "$wine_dir/lib/$basename"
  chmod u+w "$wine_dir/lib/$basename"
  copied_runtime_files="${copied_runtime_files}|${basename}|"
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
    ensure_rpath "$dylib" "@loader_path/"
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

    sign_binary_if_possible "$dylib"
  done
  shopt -u nullglob
}

add_runtime_rpath_to_wine_binaries() {
  local binary
  local touched_binaries=""
  for binary in "$wine_dir/bin/wine" "$wine_dir/bin/wine64" "$wine_dir/bin/wineserver"; do
    if [[ ! -e "$binary" ]]; then
      continue
    fi

    local resolved
    resolved="$(resolve_path "$binary")"
    if [[ "$touched_binaries" == *"|$resolved|"* ]]; then
      continue
    fi

    ensure_rpath "$resolved" "@loader_path/../lib"
    sign_binary_if_possible "$resolved"
    touched_binaries="${touched_binaries}|${resolved}|"
  done
}

bundle_required_runtime_dylibs() {
  require_command file
  require_command lipo
  require_command otool
  require_command install_name_tool

  remove_managed_runtime_dylibs

  runtime_source_lib_dir="$(configured_runtime_lib_dir || true)"
  if [[ -z "$runtime_source_lib_dir" ]]; then
    echo "Missing Sikarugir runtime lib source." >&2
    echo "  Set SIKARUGIR_RUNTIME_LIB_DIR to an extracted x86_64 runtime directory to bundle FreeType/GnuTLS." >&2
    return 0
  fi
  echo "Using Sikarugir runtime lib source: $runtime_source_lib_dir"

  local dependency
  for dependency in "${required_runtime_dylibs[@]}"; do
    local dependency_path="$runtime_source_lib_dir/$dependency"
    if [[ ! -e "$dependency_path" ]]; then
      local package="${dependency#lib}"
      package="${package%%.*}"
      echo "Missing local x86_64 dependency: $package." >&2
      echo "  Expected: $dependency_path" >&2
      continue
    fi
    if ! copy_runtime_dylib_closure "$dependency_path"; then
      local package="${dependency#lib}"
      package="${package%%.*}"
      echo "Missing local x86_64 dependency: $package." >&2
      echo "  Found $dependency, but it or one of its dependencies is not compatible with Wine architectures: $wine_binary_archs" >&2
    fi
  done

  for dependency in "${optional_runtime_dylibs[@]}"; do
    local dependency_path="$runtime_source_lib_dir/$dependency"
    if [[ ! -e "$dependency_path" ]]; then
      local package="${dependency#lib}"
      package="${package%%.*}"
      echo "Optional local x86_64 runtime dependency missing: $package." >&2
      echo "  Expected: $dependency_path" >&2
      echo "  GnuTLS may keep reporting reduced DH support until it is present." >&2
      continue
    fi
    if ! copy_runtime_dylib_closure "$dependency_path"; then
      local package="${dependency#lib}"
      package="${package%%.*}"
      echo "Optional local x86_64 runtime dependency not bundled: $package." >&2
      echo "  Found $dependency, but it or one of its dependencies is not compatible with Wine architectures: $wine_binary_archs" >&2
    fi
  done

  rewrite_bundled_runtime_dylibs
  if [[ -n "$copied_runtime_files" ]]; then
    add_runtime_rpath_to_wine_binaries
  fi
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

wine_binary_archs="$(binary_archs "$wine_dir/bin/wine64")"
if [[ -z "$wine_binary_archs" ]]; then
  echo "Unable to detect Wine binary architecture: $wine_dir/bin/wine64" >&2
  exit 1
fi
echo "Detected Wine binary architectures: $wine_binary_archs"

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
