#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  WHISKYWINE_ACK_GPTK_LOCAL_TESTING=1 Scripts/build-whiskywine-libraries.sh

Rebuilds a WhiskyWine Libraries.tar.gz using the same package shape as the
old WhiskyBuilder build-gptk.yml workflow.

Important:
  Apple GPTK/D3DMetal redistribution rights must be verified before publishing
  the output. This script requires WHISKYWINE_ACK_GPTK_LOCAL_TESTING=1 so it is
  not run accidentally.

Common environment variables:
  WHISKYWINE_BUILDER_DIR             Default: ../WhiskyBuilder
  WHISKYWINE_OUTPUT_ROOT             Default: build/WhiskyWine
  WHISKYWINE_ARCHIVE_PATH            Default: build/WhiskyWine/Libraries.tar.gz
  WHISKYWINE_HOMEBREW_TAP            Default: whisky/apple
  WHISKYWINE_HOMEBREW_TAP_URL        Default: https://github.com/Whisky-App/homebrew-apple
  WHISKYWINE_GPTK_COMPILER_FORMULA   Default: whisky/apple/game-porting-toolkit-compiler
  WHISKYWINE_GPTK_FORMULA            Default: whisky/apple/game-porting-toolkit
  WHISKYWINE_WINETRICKS_FORMULA      Default: winetricks
  WHISKYWINE_OPENSSL_FORMULA          Default: openssl@3 if available, else openssl
  WHISKYWINE_CMAKE_STRATEGY          Default: cmake@3
                                      Options: cmake@3, policy, none
  WHISKYWINE_CMAKE3_FORMULA          Default: cmake@3
  WHISKYWINE_CMAKE_POLICY_VERSION_MINIMUM
                                      Default: 3.5
  WHISKYWINE_PATCH_TAP_PREFIX         Default: whisky-rebuild/whiskywine
  WHISKYWINE_GPTK_PREFIX             Default: brew --prefix game-porting-toolkit
  WHISKYWINE_WINETRICKS_PREFIX       Default: brew --prefix winetricks
  WHISKYWINE_LIBS_DIR                Default: $WHISKYWINE_BUILDER_DIR/libs
  WHISKYWINE_DXVK_DIR                Default: $WHISKYWINE_BUILDER_DIR/DXVK
  WHISKYWINE_GPTK_REDIST_LIB_DIR     Default: $WHISKYWINE_BUILDER_DIR/GPTK/redist/lib
  WHISKYWINE_VERSION_PLIST           Default: $WHISKYWINE_BUILDER_DIR/GPTKVersion.plist
  WHISKYWINE_VERBS_URL               Default: winetricks all.txt from upstream
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${WHISKYWINE_ACK_GPTK_LOCAL_TESTING:-}" != "1" ]]; then
  cat >&2 <<'ERROR'
Refusing to build without WHISKYWINE_ACK_GPTK_LOCAL_TESTING=1.

This package can include Apple GPTK/D3DMetal files. Treat the output as
local-testing-only until redistribution rights are verified.
ERROR
  exit 1
fi

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
}

require_dir() {
  local dir_path="$1"
  local label="$2"
  if [[ ! -d "$dir_path" ]]; then
    echo "Missing $label directory: $dir_path" >&2
    exit 1
  fi
}

require_file() {
  local file_path="$1"
  local label="$2"
  if [[ ! -f "$file_path" ]]; then
    echo "Missing $label file: $file_path" >&2
    exit 1
  fi
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

builder_dir="${WHISKYWINE_BUILDER_DIR:-$repo_root/../WhiskyBuilder}"
output_root="${WHISKYWINE_OUTPUT_ROOT:-$repo_root/build/WhiskyWine}"
staging_root="${WHISKYWINE_STAGING_ROOT:-$output_root/staging}"
libraries_dir="$staging_root/Libraries"
archive_path="${WHISKYWINE_ARCHIVE_PATH:-$output_root/Libraries.tar.gz}"

tap_name="${WHISKYWINE_HOMEBREW_TAP:-whisky/apple}"
tap_url="${WHISKYWINE_HOMEBREW_TAP_URL:-https://github.com/Whisky-App/homebrew-apple}"
gptk_compiler_formula="${WHISKYWINE_GPTK_COMPILER_FORMULA:-}"
if [[ -z "$gptk_compiler_formula" ]]; then
  gptk_compiler_formula="whisky/apple/game-porting-toolkit-compiler"
fi
gptk_formula="${WHISKYWINE_GPTK_FORMULA:-whisky/apple/game-porting-toolkit}"
winetricks_formula="${WHISKYWINE_WINETRICKS_FORMULA:-winetricks}"
openssl_formula="${WHISKYWINE_OPENSSL_FORMULA:-}"
verbs_url="${WHISKYWINE_VERBS_URL:-}"
if [[ -z "$verbs_url" ]]; then
  verbs_url="https://raw.githubusercontent.com/Winetricks/winetricks/master/files/verbs/all.txt"
fi
cmake_strategy="${WHISKYWINE_CMAKE_STRATEGY:-cmake@3}"
cmake3_formula="${WHISKYWINE_CMAKE3_FORMULA:-cmake@3}"
cmake_policy_version_minimum="${WHISKYWINE_CMAKE_POLICY_VERSION_MINIMUM:-3.5}"
patch_tap_prefix="${WHISKYWINE_PATCH_TAP_PREFIX:-whisky-rebuild/whiskywine}"

libs_dir="${WHISKYWINE_LIBS_DIR:-$builder_dir/libs}"
dxvk_dir="${WHISKYWINE_DXVK_DIR:-$builder_dir/DXVK}"
gptk_redist_lib_dir="${WHISKYWINE_GPTK_REDIST_LIB_DIR:-$builder_dir/GPTK/redist/lib}"
version_plist="${WHISKYWINE_VERSION_PLIST:-$builder_dir/GPTKVersion.plist}"

formula_patch_tap=""
gptk_compiler_install_done=0
cleanup_formula_patch_tap() {
  if [[ -n "$formula_patch_tap" ]]; then
    echo "Removing temporary Homebrew tap: $formula_patch_tap" >&2
    brew untap --force "$formula_patch_tap" >/dev/null 2>&1 || true

    if brew tap | grep -Fxq "$formula_patch_tap"; then
      echo "Failed to remove temporary Homebrew tap: $formula_patch_tap" >&2
      exit 1
    fi

    formula_patch_tap=""
  fi
}

cleanup() {
  cleanup_formula_patch_tap
}
trap cleanup EXIT

cleanup_stale_patch_taps() {
  local existing_tap

  while IFS= read -r existing_tap; do
    if [[ "$existing_tap" == "$patch_tap_prefix"-* ]]; then
      echo "Removing stale temporary Homebrew tap: $existing_tap" >&2
      brew untap --force "$existing_tap" >/dev/null 2>&1 || true
    fi
  done < <(brew tap)
}

gptk_compiler_keg_path() {
  printf "%s/Cellar/game-porting-toolkit-compiler/0.1\n" "$(brew --prefix)"
}

gptk_compiler_installed() {
  local compiler_keg

  compiler_keg="$(gptk_compiler_keg_path)"
  [[ -d "$compiler_keg" ]] &&
    [[ -x "$compiler_keg/bin/clang" ]] &&
    [[ -x "$compiler_keg/bin/clang++" ]]
}

require_gptk_compiler_installed() {
  local compiler_keg

  compiler_keg="$(gptk_compiler_keg_path)"
  if gptk_compiler_installed; then
    gptk_compiler_install_done=1
    return 0
  fi

  echo "game-porting-toolkit-compiler was not installed correctly." >&2
  echo "Expected compiler keg at: $compiler_keg" >&2
  exit 1
}

install_gptk_compiler_formula() {
  local formula_name="$1"
  local install_log
  local install_status
  local compiler_keg

  install_log="$(mktemp "${TMPDIR:-/tmp}/whisky-gptk-compiler-install.XXXXXX")"

  set +e
  brew install "$formula_name" > >(tee "$install_log") 2>&1
  install_status=$?
  set -e

  if [[ "$install_status" -eq 0 ]]; then
    require_gptk_compiler_installed
    rm -f "$install_log"
    return 0
  fi

  compiler_keg="$(gptk_compiler_keg_path)"
  if gptk_compiler_installed &&
    grep -q "Failed to fix install linkage" "$install_log"; then
    gptk_compiler_install_done=1
    echo "Ignoring Homebrew linkage-fix failure after compiler install." >&2
    echo "Found installed compiler keg: $compiler_keg" >&2
    echo "Continuing with rebuild. Homebrew log: $install_log" >&2
    return 0
  fi

  echo "Homebrew compiler install failed. Log: $install_log" >&2
  return "$install_status"
}

patch_gptk_compiler_formula_environment() {
  local formula_path="$1"
  local environment_patch
  local formula_flag_keys

  formula_flag_keys="CFLAGS CXXFLAGS OBJCFLAGS OBJCXXFLAGS HOMEBREW_OPTFLAGS"

  environment_patch=$'    # Xcode 27 clang defaults to arm64 on Apple Silicon,\n'
  environment_patch+=$'    # even when invoked from a Rosetta x86_64 shell.\n'
  environment_patch+=$'    ENV.append_to_cccfg "K"\n'
  environment_patch+=$'    ENV["HOMEBREW_ARCHFLAGS"] = "-arch x86_64"\n'
  environment_patch+=$'    ENV["CC"] = "clang -arch x86_64"\n'
  environment_patch+=$'    ENV["CXX"] = "clang++ -arch x86_64"\n\n'
  environment_patch+=$'    # Xcode 27 clang rejects Homebrew\'s Rosetta x86_64 -march=westmere.\n'
  environment_patch+=$'    %w['"$formula_flag_keys"$'].each do |key|\n'
  environment_patch+=$'      flags = ENV.fetch(key, "").split\n'
  environment_patch+=$'                 .reject { |flag| flag == "-march=westmere" }\n'
  environment_patch+=$'      if flags.empty?\n'
  environment_patch+=$'        ENV.delete(key)\n'
  environment_patch+=$'      else\n'
  environment_patch+=$'        ENV[key] = flags.join(" ")\n'
  environment_patch+=$'      end\n'
  environment_patch+=$'    end\n\n'

  WHISKYWINE_FORMULA_ENVIRONMENT_PATCH="$environment_patch" \
    /usr/bin/perl -0pi -e \
    's/(  def install\n)/$1$ENV{WHISKYWINE_FORMULA_ENVIRONMENT_PATCH}/' \
    "$formula_path"

  if ! grep -q "HOMEBREW_ARCHFLAGS" "$formula_path"; then
    echo "Failed to patch compiler formula to force x86_64 clang." >&2
    exit 1
  fi

  if ! grep -q "HOMEBREW_OPTFLAGS" "$formula_path"; then
    echo "Failed to patch compiler formula to scrub -march=westmere." >&2
    exit 1
  fi
}

patch_gptk_compiler_formula_cmake_target() {
  local formula_path="$1"
  local cmake_target_patch

  cmake_target_patch='                      "-DCMAKE_C_COMPILER_TARGET=x86_64-apple-darwin",'
  cmake_target_patch+=$'\n'
  cmake_target_patch+='                      "-DCMAKE_CXX_COMPILER_TARGET=x86_64-apple-darwin",'
  cmake_target_patch+=$'\n'

  WHISKYWINE_CMAKE_TARGET_PATCH="$cmake_target_patch" \
    /usr/bin/perl -0pi -e \
    's/(system "cmake", "-G", "Ninja",\n)/$1$ENV{WHISKYWINE_CMAKE_TARGET_PATCH}/' \
    "$formula_path"

  if ! grep -q "CMAKE_C_COMPILER_TARGET=x86_64" "$formula_path"; then
    echo "Failed to patch compiler formula CMake target." >&2
    exit 1
  fi
}

patch_gptk_compiler_formula_sancov() {
  local formula_path="$1"
  local source_patch
  local source_patch_format
  local source_patch_expression
  local sancov_old
  local sancov_new

  sancov_old="return SpecialCaseList::createOrDie({{ClBlacklist}});"
  sancov_new="return SpecialCaseList::createOrDie("
  sancov_new+="std::vector<std::string>{ClBlacklist});"

  source_patch_format=$'    inreplace "llvm/tools/sancov/sancov.cpp",\n'
  source_patch_format+=$'              "%s",\n'
  source_patch_format+=$'              "%s"\n\n'
  source_patch="$(printf "$source_patch_format" "$sancov_old" "$sancov_new")"

  source_patch_expression='s/(    system "tar", "-xf", '
  source_patch_expression+='"crossover-sources-22\.1\.1\.tar\.gz",[^\n]+\n)/'
  source_patch_expression+='$1$ENV{WHISKYWINE_SANCOV_SOURCE_PATCH}/'

  WHISKYWINE_SANCOV_SOURCE_PATCH="$source_patch" \
    /usr/bin/perl -0pi -e "$source_patch_expression" "$formula_path"

  if ! grep -q "std::vector<std::string>{ClBlacklist}" "$formula_path"; then
    echo "Failed to patch compiler formula sancov source edit." >&2
    exit 1
  fi
}

prepare_gptk_compiler_formula() {
  local mode="$1"
  local tap_suffix

  cleanup_stale_patch_taps

  tap_suffix="$(date +%s)-$$"
  formula_patch_tap="${patch_tap_prefix}-${tap_suffix}"

  echo "Creating temporary Homebrew tap: $formula_patch_tap" >&2
  brew tap-new --no-git "$formula_patch_tap" >/dev/null

  local tap_path
  tap_path="$(brew --repository "$formula_patch_tap")"
  local formula_path="$tap_path/Formula/game-porting-toolkit-compiler.rb"

  brew cat "$gptk_compiler_formula" > "$formula_path"
  patch_gptk_compiler_formula_environment "$formula_path"
  patch_gptk_compiler_formula_cmake_target "$formula_path"
  patch_gptk_compiler_formula_sancov "$formula_path"

  case "$mode" in
    cmake@3)
      /usr/bin/perl -0pi -e \
        's/depends_on "cmake"( => :build)?/depends_on "cmake@3"$1/g' \
        "$formula_path"
      if ! grep -q 'depends_on "cmake@3"' "$formula_path"; then
        echo "Failed to patch compiler formula to depend on cmake@3." >&2
        exit 1
      fi
      ;;
    policy)
      local cmake_policy_arg
      local cmake_policy_patch
      cmake_policy_arg="-DCMAKE_POLICY_VERSION_MINIMUM=$cmake_policy_version_minimum"
      cmake_policy_patch="                      \"$cmake_policy_arg\","
      cmake_policy_patch+=$'\n'

      WHISKYWINE_CMAKE_POLICY_PATCH="$cmake_policy_patch" \
        /usr/bin/perl -0pi -e \
        's/(system "cmake", "-G", "Ninja",\n)/$1$ENV{WHISKYWINE_CMAKE_POLICY_PATCH}/' \
        "$formula_path"
      if ! grep -q "CMAKE_POLICY_VERSION_MINIMUM" "$formula_path"; then
        echo "Failed to add CMAKE_POLICY_VERSION_MINIMUM to compiler formula." >&2
        exit 1
      fi
      ;;
    *)
      echo "Unknown compiler formula patch mode: $mode" >&2
      exit 1
      ;;
  esac

  echo "$formula_patch_tap/game-porting-toolkit-compiler"
}

select_supported_openssl_formula() {
  local candidate

  if [[ -n "$openssl_formula" ]]; then
    if ! brew cat "$openssl_formula" >/dev/null 2>&1; then
      echo "Configured OpenSSL formula is unavailable: $openssl_formula" >&2
      exit 1
    fi
    return
  fi

  for candidate in openssl@3 openssl; do
    if brew cat "$candidate" >/dev/null 2>&1; then
      openssl_formula="$candidate"
      return
    fi
  done

  echo "No supported Homebrew OpenSSL formula found." >&2
  echo "Set WHISKYWINE_OPENSSL_FORMULA to a supported formula name." >&2
  exit 1
}

patch_gptk_formula_openssl() {
  local formula_path="$1"

  select_supported_openssl_formula

  if ! grep -q '"openssl@1.1"' "$formula_path"; then
    echo "No openssl@1.1 dependency found in $gptk_formula." >&2
    return
  fi

  WHISKYWINE_PATCH_OPENSSL_FORMULA="$openssl_formula" \
    /usr/bin/perl -0pi -e \
    's/"openssl\@1\.1"/"$ENV{WHISKYWINE_PATCH_OPENSSL_FORMULA}"/g' \
    "$formula_path"

  if grep -q '"openssl@1.1"' "$formula_path"; then
    echo "Failed to patch game-porting-toolkit OpenSSL dependency." >&2
    exit 1
  fi

  echo "Patched game-porting-toolkit to depend on $openssl_formula." >&2
}

patch_gptk_formula_sdkroot() {
  local formula_path="$1"
  local compiler_old
  local compiler_new
  local compiler_patch_expression

  compiler_old=$'    compiler_options = ["CC=#{compiler.bin}/clang",\n'
  compiler_old+=$'                        "CXX=#{compiler.bin}/clang++"]'

  compiler_new=$'    sdk_path = MacOS.sdk_path\n'
  compiler_new+=$'    ENV["SDKROOT"] = sdk_path.to_s\n'
  compiler_new+=$'    clang_wrapper = buildpath/"whisky-gptk-clang"\n'
  compiler_new+=$'    clangxx_wrapper = buildpath/"whisky-gptk-clang++"\n'
  compiler_new+=$'    clang_wrapper.write <<~EOS\n'
  compiler_new+=$'      #!/bin/sh\n'
  compiler_new+=$'      exec "#{compiler.bin}/clang" \\\n'
  compiler_new+=$'        -arch x86_64 \\\n'
  compiler_new+=$'        -isysroot "#{sdk_path}" \\\n'
  compiler_new+=$'        \'-D__is_target_environment(x)=0\' \\\n'
  compiler_new+=$'        -Wno-builtin-macro-redefined \\\n'
  compiler_new+=$'        "$@"\n'
  compiler_new+=$'    EOS\n'
  compiler_new+=$'    clangxx_wrapper.write <<~EOS\n'
  compiler_new+=$'      #!/bin/sh\n'
  compiler_new+=$'      exec "#{compiler.bin}/clang++" \\\n'
  compiler_new+=$'        -arch x86_64 \\\n'
  compiler_new+=$'        -isysroot "#{sdk_path}" \\\n'
  compiler_new+=$'        \'-D__is_target_environment(x)=0\' \\\n'
  compiler_new+=$'        -Wno-builtin-macro-redefined \\\n'
  compiler_new+=$'        "$@"\n'
  compiler_new+=$'    EOS\n'
  compiler_new+=$'    chmod 0755, clang_wrapper\n'
  compiler_new+=$'    chmod 0755, clangxx_wrapper\n'
  compiler_new+=$'    compiler_options = [\n'
  compiler_new+=$'      "CC=#{clang_wrapper}",\n'
  compiler_new+=$'      "CXX=#{clangxx_wrapper}"\n'
  compiler_new+=$'    ]'

  compiler_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_COMPILER_OPTIONS_OLD}\E/'
  compiler_patch_expression+='$ENV{WHISKYWINE_GPTK_COMPILER_OPTIONS_PATCH}/'

  WHISKYWINE_GPTK_COMPILER_OPTIONS_OLD="$compiler_old" \
  WHISKYWINE_GPTK_COMPILER_OPTIONS_PATCH="$compiler_new" \
    /usr/bin/perl -0pi -e "$compiler_patch_expression" "$formula_path"

  if ! grep -q "SDKROOT" "$formula_path"; then
    echo "Failed to patch game-porting-toolkit SDKROOT." >&2
    exit 1
  fi

  if ! grep -q -- "-isysroot" "$formula_path"; then
    echo "Failed to patch game-porting-toolkit compiler sysroot." >&2
    exit 1
  fi

  if ! grep -q "__is_target_environment" "$formula_path"; then
    echo "Failed to patch game-porting-toolkit TargetConditionals flag." >&2
    exit 1
  fi
}

patch_gptk_formula_cross_cflags() {
  local formula_path="$1"
  local cflags_line
  local cflags_patch
  local cflags_patch_expression

  cflags_line=$'    ENV.append_to_cflags "-O3 -Wno-implicit-function-declaration '
  cflags_line+=$'-Wno-format -Wno-deprecated-declarations '
  cflags_line+=$'-Wno-incompatible-pointer-types"'

  cflags_patch="$cflags_line"
  cflags_patch+=$'\n'
  cflags_patch+=$'    # Wine PE builds use CROSSCFLAGS, not Homebrew CFLAGS.\n'
  cflags_patch+=$'    ENV.append "CROSSCFLAGS", "-D_NO_CRT_STDIO_INLINE"\n'
  cflags_patch+=$'    ENV.append "CROSSCFLAGS", '
  cflags_patch+=$'"-Wno-implicit-function-declaration"\n'
  cflags_patch+=$'    ENV.append "CROSSCFLAGS", '
  cflags_patch+=$'"-Wno-error=implicit-function-declaration"'

  cflags_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_CFLAGS_OLD}\E/'
  cflags_patch_expression+='$ENV{WHISKYWINE_GPTK_CROSS_CFLAGS_PATCH}/'

  WHISKYWINE_GPTK_CFLAGS_OLD="$cflags_line" \
  WHISKYWINE_GPTK_CROSS_CFLAGS_PATCH="$cflags_patch" \
    /usr/bin/perl -0pi -e "$cflags_patch_expression" \
    "$formula_path"

  if ! grep -q "CROSSCFLAGS" "$formula_path"; then
    echo "Failed to patch game-porting-toolkit CROSSCFLAGS." >&2
    exit 1
  fi

  if ! grep -q -- "-D_NO_CRT_STDIO_INLINE" "$formula_path"; then
    echo "Failed to patch game-porting-toolkit CRT stdio inlines." >&2
    exit 1
  fi

  if ! grep -q -- "-Wno-error=implicit-function-declaration" "$formula_path"; then
    echo "Failed to patch game-porting-toolkit cross compiler warnings." >&2
    exit 1
  fi
}

patch_gptk_formula_wcstring() {
  local formula_path="$1"
  local build_marker
  local wcstring_patch
  local wcstring_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  wcstring_patch=$'    inreplace "wine/dlls/ntdll/wcstring.c" do |s|\n'
  wcstring_patch+=$'      old = "#include <stdlib.h>\\n#include <string.h>\\n"\n'
  wcstring_patch+=$'      new = "#include <stdlib.h>\\n" \\\n'
  wcstring_patch+=$'            "#define wcstok __wine_hidden_wcstok\\n" \\\n'
  wcstring_patch+=$'            "#include <string.h>\\n" \\\n'
  wcstring_patch+=$'            "#undef wcstok\\n"\n'
  wcstring_patch+=$'      raise "failed to patch wcstring wcstok" unless '
  wcstring_patch+=$'s.gsub!(old, new)\n'
  wcstring_patch+=$'    end\n\n'
  wcstring_patch+="$build_marker"

  wcstring_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_WCSTRING_MARKER}\E/'
  wcstring_patch_expression+='$ENV{WHISKYWINE_GPTK_WCSTRING_PATCH}/'

  WHISKYWINE_GPTK_WCSTRING_MARKER="$build_marker" \
  WHISKYWINE_GPTK_WCSTRING_PATCH="$wcstring_patch" \
    /usr/bin/perl -0pi -e "$wcstring_patch_expression" \
    "$formula_path"

  if ! grep -q "__wine_hidden_wcstok" "$formula_path"; then
    echo "Failed to patch game-porting-toolkit wcstring source edit." >&2
    exit 1
  fi
}

patch_gptk_formula_msvcrt_wcs() {
  local formula_path="$1"
  local build_marker
  local wcs_patch
  local wcs_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  wcs_patch=$'    wcs_path = buildpath/"wine/dlls/msvcrt/wcs.c"\n'
  wcs_patch+=$'    wcs_source = File.read(wcs_path)\n'
  wcs_patch+=$'    wcs_pattern = /^#include <wchar\\.h>\\n/\n'
  wcs_patch+=$'    unless wcs_source.sub!(wcs_pattern) do\n'
  wcs_patch+=$'      "#define wcstok __wine_hidden_wcstok\\n" \\\n'
  wcs_patch+=$'        "#include <wchar.h>\\n" \\\n'
  wcs_patch+=$'        "#undef wcstok\\n"\n'
  wcs_patch+=$'    end\n'
  wcs_patch+=$'      wcs_lines = wcs_source.lines\n'
  wcs_patch+=$'      wcs_index = wcs_lines.find_index do |line|\n'
  wcs_patch+=$'        line.include?("#include <wchar.h>")\n'
  wcs_patch+=$'      end\n'
  wcs_patch+=$'      wcs_index ||= wcs_lines.find_index do |line|\n'
  wcs_patch+=$'        line.include?("wcstok")\n'
  wcs_patch+=$'      end\n'
  wcs_patch+=$'      if wcs_index\n'
  wcs_patch+=$'        first = [wcs_index - 5, 0].max\n'
  wcs_patch+=$'        last = [wcs_index + 5, wcs_lines.length - 1].min\n'
  wcs_patch+=$'        $stderr.puts "Failed to patch msvcrt wcs wcstok."\n'
  wcs_patch+=$'        $stderr.puts "Nearby wcs.c context:"\n'
  wcs_patch+=$'        (first..last).each do |line_number|\n'
  wcs_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, '
  wcs_patch+=$'wcs_lines[line_number])\n'
  wcs_patch+=$'        end\n'
  wcs_patch+=$'      else\n'
  wcs_patch+=$'        $stderr.puts "wchar.h include and wcstok not found."\n'
  wcs_patch+=$'      end\n'
  wcs_patch+=$'      raise "failed to patch msvcrt wcs wcstok"\n'
  wcs_patch+=$'    end\n'
  wcs_patch+=$'    File.write(wcs_path, wcs_source)\n\n'
  wcs_patch+="$build_marker"

  wcs_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_WCS_MARKER}\E/'
  wcs_patch_expression+='$ENV{WHISKYWINE_GPTK_WCS_PATCH}/'

  WHISKYWINE_GPTK_WCS_MARKER="$build_marker" \
  WHISKYWINE_GPTK_WCS_PATCH="$wcs_patch" \
    /usr/bin/perl -0pi -e "$wcs_patch_expression" \
    "$formula_path"

  if ! grep -q "__wine_hidden_wcstok" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit msvcrt wcs patch." >&2
    exit 1
  fi
}

patch_gptk_formula_http_sys() {
  local formula_path="$1"
  local build_marker
  local http_patch
  local http_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  http_patch=$'    http_path = buildpath/"wine/dlls/http.sys/http.c"\n'
  http_patch+=$'    http_source = File.read(http_path)\n'
  http_patch+=$'    http_source.gsub!(/\\bULONG\\s+true\\s*=\\s*1\\s*;/, '
  http_patch+=$'"ULONG nonblocking = 1;")\n'
  http_patch+=$'    http_source.gsub!(/&\\s*true\\b/, "&nonblocking")\n'
  http_patch+=$'    http_has_old_flag = '
  http_patch+=$'http_source.match?(/\\bULONG\\s+true\\s*=\\s*1\\s*;/)\n'
  http_patch+=$'    http_has_old_ref = http_source.match?(/&\\s*true\\b/)\n'
  http_patch+=$'    http_has_new_flag = '
  http_patch+=$'http_source.match?(/\\bULONG\\s+nonblocking\\s*=\\s*1\\s*;/)\n'
  http_patch+=$'    http_has_new_ref = http_source.include?("&nonblocking")\n'
  http_patch+=$'    unless !http_has_old_flag && !http_has_old_ref && '
  http_patch+=$'http_has_new_flag && http_has_new_ref\n'
  http_patch+=$'      http_lines = http_source.lines\n'
  http_patch+=$'      http_printed_context = false\n'
  http_patch+=$'      ["http_add_url", "ULONG true", "ioctlsocket"].each do |target|\n'
  http_patch+=$'        http_index = http_lines.find_index do |line|\n'
  http_patch+=$'          line.include?(target)\n'
  http_patch+=$'        end\n'
  http_patch+=$'        next unless http_index\n'
  http_patch+=$'        http_printed_context = true\n'
  http_patch+=$'        first = [http_index - 5, 0].max\n'
  http_patch+=$'        last = [http_index + 5, http_lines.length - 1].min\n'
  http_patch+=$'        $stderr.puts "Failed to patch http.sys nonblocking flag."\n'
  http_patch+=$'        $stderr.puts "Nearby http.c context around #{target}:"\n'
  http_patch+=$'        (first..last).each do |line_number|\n'
  http_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, '
  http_patch+=$'http_lines[line_number])\n'
  http_patch+=$'        end\n'
  http_patch+=$'      end\n'
  http_patch+=$'      unless http_printed_context\n'
  http_patch+=$'        $stderr.puts "http_add_url/ULONG true/ioctlsocket not found."\n'
  http_patch+=$'      end\n'
  http_patch+=$'      raise "failed to patch http.sys nonblocking flag"\n'
  http_patch+=$'    end\n'
  http_patch+=$'    File.write(http_path, http_source)\n\n'
  http_patch+="$build_marker"

  http_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_HTTP_MARKER}\E/'
  http_patch_expression+='$ENV{WHISKYWINE_GPTK_HTTP_PATCH}/'

  WHISKYWINE_GPTK_HTTP_MARKER="$build_marker" \
  WHISKYWINE_GPTK_HTTP_PATCH="$http_patch" \
    /usr/bin/perl -0pi -e "$http_patch_expression" \
    "$formula_path"

  if ! grep -q "http.sys nonblocking" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit http.sys patch." >&2
    exit 1
  fi
}

patch_gptk_formula_jscript_bool() {
  local formula_path="$1"
  local build_marker
  local bool_patch
  local bool_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  bool_patch=$'    bool_path = buildpath/"wine/dlls/jscript/bool.c"\n'
  bool_patch+=$'    bool_source = File.read(bool_path)\n'
  bool_patch+=$'    bool_had_target = bool_source.match?(/\\*\\s*bool\\b/)\n'
  bool_patch+=$'    bool_source.gsub!(/\\bbool\\b/, "bool_obj")\n'
  bool_patch+=$'    bool_has_old_decl = bool_source.match?(/\\*\\s*bool\\b/)\n'
  bool_patch+=$'    unless bool_had_target && !bool_has_old_decl\n'
  bool_patch+=$'      bool_lines = bool_source.lines\n'
  bool_patch+=$'      bool_index = bool_lines.find_index do |line|\n'
  bool_patch+=$'        line.match?(/\\*\\s*bool\\b/) || '
  bool_patch+=$'line.include?("BoolInstance") || line.include?("jsdisp_t")\n'
  bool_patch+=$'      end\n'
  bool_patch+=$'      if bool_index\n'
  bool_patch+=$'        first = [bool_index - 5, 0].max\n'
  bool_patch+=$'        last = [bool_index + 5, bool_lines.length - 1].min\n'
  bool_patch+=$'        $stderr.puts "Failed to patch jscript bool locals."\n'
  bool_patch+=$'        $stderr.puts "Nearby bool.c context:"\n'
  bool_patch+=$'        (first..last).each do |line_number|\n'
  bool_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, '
  bool_patch+=$'bool_lines[line_number])\n'
  bool_patch+=$'        end\n'
  bool_patch+=$'      else\n'
  bool_patch+=$'        $stderr.puts "jscript bool local declarations not found."\n'
  bool_patch+=$'      end\n'
  bool_patch+=$'      raise "failed to patch jscript bool locals"\n'
  bool_patch+=$'    end\n'
  bool_patch+=$'    File.write(bool_path, bool_source)\n\n'
  bool_patch+="$build_marker"

  bool_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_BOOL_MARKER}\E/'
  bool_patch_expression+='$ENV{WHISKYWINE_GPTK_BOOL_PATCH}/'

  WHISKYWINE_GPTK_BOOL_MARKER="$build_marker" \
  WHISKYWINE_GPTK_BOOL_PATCH="$bool_patch" \
    /usr/bin/perl -0pi -e "$bool_patch_expression" \
    "$formula_path"

  if ! grep -q "jscript bool locals" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit jscript bool patch." >&2
    exit 1
  fi
}

patch_gptk_formula_msi_cond_bool() {
  local formula_path="$1"
  local build_marker
  local cond_patch
  local cond_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  cond_patch=$'    cond_path = buildpath/"wine/dlls/msi/cond.y"\n'
  cond_patch+=$'    cond_source = File.read(cond_path)\n'
  cond_patch+=$'    cond_source.gsub!(/\\bBOOL\\s+bool\\s*;/, "BOOL bool_value;")\n'
  cond_patch+=$'    cond_source.gsub!(/<\\s*bool\\s*>/, "<bool_value>")\n'
  cond_patch+=$'    cond_source.gsub!(/\\.bool\\b/, ".bool_value")\n'
  cond_patch+=$'    cond_has_new_field = '
  cond_patch+=$'cond_source.match?(/\\bBOOL\\s+bool_value\\s*;/)\n'
  cond_patch+=$'    cond_has_new_refs = cond_source.include?("<bool_value>")\n'
  cond_patch+=$'    cond_has_old_field = cond_source.match?(/\\bBOOL\\s+bool\\s*;/)\n'
  cond_patch+=$'    cond_has_old_refs = '
  cond_patch+=$'cond_source.match?(/<\\s*bool\\s*>|\\.bool\\b/)\n'
  cond_patch+=$'    unless cond_has_new_field && cond_has_new_refs && '
  cond_patch+=$'!cond_has_old_field && !cond_has_old_refs\n'
  cond_patch+=$'      cond_lines = cond_source.lines\n'
  cond_patch+=$'      cond_printed_context = false\n'
  cond_patch+=$'      ["BOOL bool", "bool_value", "<bool", ".bool"].each do |target|\n'
  cond_patch+=$'        cond_index = cond_lines.find_index do |line|\n'
  cond_patch+=$'          line.include?(target)\n'
  cond_patch+=$'        end\n'
  cond_patch+=$'        next unless cond_index\n'
  cond_patch+=$'        cond_printed_context = true\n'
  cond_patch+=$'        first = [cond_index - 8, 0].max\n'
  cond_patch+=$'        last = [cond_index + 14, cond_lines.length - 1].min\n'
  cond_patch+=$'        $stderr.puts "Failed to patch msi cond bool semantic field."\n'
  cond_patch+=$'        $stderr.puts "Nearby cond.y context around #{target}:"\n'
  cond_patch+=$'        (first..last).each do |line_number|\n'
  cond_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, '
  cond_patch+=$'cond_lines[line_number])\n'
  cond_patch+=$'        end\n'
  cond_patch+=$'      end\n'
  cond_patch+=$'      unless cond_printed_context\n'
  cond_patch+=$'        $stderr.puts "msi cond bool targets not found."\n'
  cond_patch+=$'      end\n'
  cond_patch+=$'      raise "failed to patch msi cond bool semantic field"\n'
  cond_patch+=$'    end\n'
  cond_patch+=$'    File.write(cond_path, cond_source)\n\n'
  cond_patch+="$build_marker"

  cond_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_MSI_COND_MARKER}\E/'
  cond_patch_expression+='$ENV{WHISKYWINE_GPTK_MSI_COND_PATCH}/'

  WHISKYWINE_GPTK_MSI_COND_MARKER="$build_marker" \
  WHISKYWINE_GPTK_MSI_COND_PATCH="$cond_patch" \
    /usr/bin/perl -0pi -e "$cond_patch_expression" \
    "$formula_path"

  if ! grep -q "msi cond bool semantic field" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit msi cond patch." >&2
    exit 1
  fi
}

patch_gptk_formula_winecrt0_debug() {
  local formula_path="$1"
  local build_marker
  local debug_patch
  local debug_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  debug_patch=$'    debug_path = buildpath/"wine/dlls/winecrt0/debug.c"\n'
  debug_patch+=$'    debug_source = File.read(debug_path)\n'
  debug_patch+=$'    debug_source.gsub!('
  debug_patch+=$'/snprintf\\(\\s*pos\\s*,\\s*sizeof\\s*\\(\\s*buffer\\s*\\)\\s*-\\s*'
  debug_patch+=$'\\(\\s*pos\\s*-\\s*buffer\\s*\\)\\s*,\\s*"%s:%s:%s "\\s*,/m, '
  debug_patch+=$'"sprintf( pos, \\"%s:%s:%s \\"," )\n'
  debug_patch+=$'    debug_has_new_call = '
  debug_patch+=$'debug_source.match?(/sprintf\\(\\s*pos\\s*,\\s*"%s:%s:%s "\\s*,/)\n'
  debug_patch+=$'    debug_has_old_call = '
  debug_patch+=$'debug_source.match?(/snprintf\\(\\s*pos\\s*,\\s*sizeof\\s*\\(\\s*buffer\\s*\\)\\s*-\\s*'
  debug_patch+=$'\\(\\s*pos\\s*-\\s*buffer\\s*\\)\\s*,\\s*"%s:%s:%s "\\s*,/m)\n'
  debug_patch+=$'    unless debug_has_new_call && !debug_has_old_call\n'
  debug_patch+=$'      debug_lines = debug_source.lines\n'
  debug_patch+=$'      debug_index = debug_lines.find_index do |line|\n'
  debug_patch+=$'        line.include?("snprintf") || '
  debug_patch+=$'line.include?("fallback__wine_dbg_header") || '
  debug_patch+=$'line.include?("%s:%s:%s")\n'
  debug_patch+=$'      end\n'
  debug_patch+=$'      if debug_index\n'
  debug_patch+=$'        first = [debug_index - 8, 0].max\n'
  debug_patch+=$'        last = [debug_index + 14, debug_lines.length - 1].min\n'
  debug_patch+=$'        $stderr.puts "Failed to patch winecrt0 debug snprintf."\n'
  debug_patch+=$'        $stderr.puts "Nearby debug.c context:"\n'
  debug_patch+=$'        (first..last).each do |line_number|\n'
  debug_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, '
  debug_patch+=$'debug_lines[line_number])\n'
  debug_patch+=$'        end\n'
  debug_patch+=$'      else\n'
  debug_patch+=$'        $stderr.puts "winecrt0 debug snprintf target not found."\n'
  debug_patch+=$'      end\n'
  debug_patch+=$'      raise "failed to patch winecrt0 debug snprintf"\n'
  debug_patch+=$'    end\n'
  debug_patch+=$'    File.write(debug_path, debug_source)\n\n'
  debug_patch+="$build_marker"

  debug_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_WINECRT0_DEBUG_MARKER}\E/'
  debug_patch_expression+='$ENV{WHISKYWINE_GPTK_WINECRT0_DEBUG_PATCH}/'

  WHISKYWINE_GPTK_WINECRT0_DEBUG_MARKER="$build_marker" \
  WHISKYWINE_GPTK_WINECRT0_DEBUG_PATCH="$debug_patch" \
    /usr/bin/perl -0pi -e "$debug_patch_expression" \
    "$formula_path"

  if ! grep -q "winecrt0 debug snprintf" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit winecrt0 debug patch." >&2
    exit 1
  fi
}

patch_gptk_formula_dbghelp_msc() {
  local formula_path="$1"
  local build_marker
  local msc_patch
  local msc_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  msc_patch=$'    msc_path = buildpath/"wine/dlls/dbghelp/msc.c"\n'
  msc_patch+=$'    msc_source = File.read(msc_path)\n'
  msc_patch+=$'    msc_source.gsub!('
  msc_patch+=$'/snprintf\\(\\s*\\(pev\\)->error\\s*,\\s*sizeof\\s*\\(\\s*'
  msc_patch+=$'\\(pev\\)->error\\s*\\)\\s*,/m, '
  msc_patch+=$'"sprintf((pev)->error,")\n'
  msc_patch+=$'    msc_source.gsub!('
  msc_patch+=$'/snprintf\\(\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*,\\s*sizeof\\s*'
  msc_patch+=$'\\(\\s*\\1\\s*\\)\\s*,/m, '
  msc_patch+=$'"sprintf(\\\\1,")\n'
  msc_patch+=$'    msc_has_old_call = msc_source.include?("snprintf(")\n'
  msc_patch+=$'    msc_has_expected_calls = '
  msc_patch+=$'msc_source.include?("sprintf(buf,") && '
  msc_patch+=$'msc_source.include?("sprintf((pev)->error,") && '
  msc_patch+=$'msc_source.include?("sprintf(res,")\n'
  msc_patch+=$'    unless !msc_has_old_call && msc_has_expected_calls\n'
  msc_patch+=$'      msc_lines = msc_source.lines\n'
  msc_patch+=$'      msc_printed_context = false\n'
  msc_patch+=$'      ["snprintf", "sprintf(buf", "PEV_ERROR", "sprintf(res"].each do |target|\n'
  msc_patch+=$'        msc_index = msc_lines.find_index { |line| line.include?(target) }\n'
  msc_patch+=$'        next unless msc_index\n'
  msc_patch+=$'        msc_printed_context = true\n'
  msc_patch+=$'        first = [msc_index - 8, 0].max\n'
  msc_patch+=$'        last = [msc_index + 14, msc_lines.length - 1].min\n'
  msc_patch+=$'        $stderr.puts "Failed to patch dbghelp msc snprintf compatibility."\n'
  msc_patch+=$'        $stderr.puts "Nearby msc.c context around #{target}:"\n'
  msc_patch+=$'        (first..last).each do |line_number|\n'
  msc_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, msc_lines[line_number])\n'
  msc_patch+=$'        end\n'
  msc_patch+=$'      end\n'
  msc_patch+=$'      unless msc_printed_context\n'
  msc_patch+=$'        $stderr.puts "dbghelp msc snprintf targets not found."\n'
  msc_patch+=$'      end\n'
  msc_patch+=$'      raise "failed to patch dbghelp msc snprintf compatibility"\n'
  msc_patch+=$'    end\n'
  msc_patch+=$'    File.write(msc_path, msc_source)\n\n'
  msc_patch+=$'    pe_module_path = buildpath/"wine/dlls/dbghelp/pe_module.c"\n'
  msc_patch+=$'    pe_module_source = File.read(pe_module_path)\n'
  msc_patch+=$'    pe_module_source.gsub!('
  msc_patch+=$'/snprintf\\(\\s*buffer\\s*,\\s*sizeof\\s*\\(\\s*buffer\\s*\\)\\s*,\\s*'
  msc_patch+=$'"%ld"\\s*,\\s*i\\s*\\+\\s*exports->Base\\s*\\)/, '
  msc_patch+=$'"sprintf(buffer, \\"%ld\\", i + exports->Base)")\n'
  msc_patch+=$'    pe_module_has_new_call = '
  msc_patch+=$'pe_module_source.match?(/sprintf\\(\\s*buffer\\s*,\\s*"%ld"\\s*,\\s*i\\s*\\+\\s*exports->Base\\s*\\)/)\n'
  msc_patch+=$'    pe_module_has_old_call = pe_module_source.include?("snprintf(")\n'
  msc_patch+=$'    unless pe_module_has_new_call && !pe_module_has_old_call\n'
  msc_patch+=$'      pe_module_lines = pe_module_source.lines\n'
  msc_patch+=$'      pe_module_printed_context = false\n'
  msc_patch+=$'      ["snprintf", "sprintf(buffer", "symt_new_public", "exports->Base"].each do |target|\n'
  msc_patch+=$'        pe_module_index = pe_module_lines.find_index { |line| line.include?(target) }\n'
  msc_patch+=$'        next unless pe_module_index\n'
  msc_patch+=$'        pe_module_printed_context = true\n'
  msc_patch+=$'        first = [pe_module_index - 8, 0].max\n'
  msc_patch+=$'        last = [pe_module_index + 14, pe_module_lines.length - 1].min\n'
  msc_patch+=$'        $stderr.puts "Failed to patch dbghelp pe_module snprintf compatibility."\n'
  msc_patch+=$'        $stderr.puts "Nearby pe_module.c context around #{target}:"\n'
  msc_patch+=$'        (first..last).each do |line_number|\n'
  msc_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, pe_module_lines[line_number])\n'
  msc_patch+=$'        end\n'
  msc_patch+=$'      end\n'
  msc_patch+=$'      unless pe_module_printed_context\n'
  msc_patch+=$'        $stderr.puts "dbghelp pe_module snprintf target not found."\n'
  msc_patch+=$'      end\n'
  msc_patch+=$'      raise "failed to patch dbghelp pe_module snprintf compatibility"\n'
  msc_patch+=$'    end\n'
  msc_patch+=$'    File.write(pe_module_path, pe_module_source)\n\n'
  msc_patch+="$build_marker"

  msc_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_DBGHELP_MSC_MARKER}\E/'
  msc_patch_expression+='$ENV{WHISKYWINE_GPTK_DBGHELP_MSC_PATCH}/'

  WHISKYWINE_GPTK_DBGHELP_MSC_MARKER="$build_marker" \
  WHISKYWINE_GPTK_DBGHELP_MSC_PATCH="$msc_patch" \
    /usr/bin/perl -0pi -e "$msc_patch_expression" \
    "$formula_path"

  if ! grep -q "dbghelp msc snprintf compatibility" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit dbghelp msc patch." >&2
    exit 1
  fi
}

patch_gptk_formula_cryptnet_snprintf() {
  local formula_path="$1"
  local build_marker
  local cryptnet_patch
  local cryptnet_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  cryptnet_patch=$'    cryptnet_path = buildpath/"wine/dlls/cryptnet/cryptnet_main.c"\n'
  cryptnet_patch+=$'    cryptnet_source = File.read(cryptnet_path)\n'
  cryptnet_patch+=$'    cryptnet_source.gsub!('
  cryptnet_patch+=$'/snprintf\\(\\s*buf\\s*,\\s*sizeof\\s*\\(\\s*buf\\s*\\)\\s*,\\s*'
  cryptnet_patch+=$'"%d"\\s*,\\s*LOWORD\\(\\s*oid\\s*\\)\\s*\\)/, '
  cryptnet_patch+=$'"sprintf(buf, \\"%d\\", LOWORD(oid))")\n'
  cryptnet_patch+=$'    cryptnet_has_new_call = '
  cryptnet_patch+=$'cryptnet_source.match?(/sprintf\\(\\s*buf\\s*,\\s*"%d"\\s*,\\s*LOWORD\\(\\s*oid\\s*\\)\\s*\\)/)\n'
  cryptnet_patch+=$'    cryptnet_has_old_call = cryptnet_source.include?("snprintf(")\n'
  cryptnet_patch+=$'    unless cryptnet_has_new_call && !cryptnet_has_old_call\n'
  cryptnet_patch+=$'      cryptnet_lines = cryptnet_source.lines\n'
  cryptnet_patch+=$'      cryptnet_printed_context = false\n'
  cryptnet_patch+=$'      ["snprintf", "sprintf(buf", "url_oid_to_str", "LOWORD(oid)"].each do |target|\n'
  cryptnet_patch+=$'        cryptnet_index = cryptnet_lines.find_index { |line| line.include?(target) }\n'
  cryptnet_patch+=$'        next unless cryptnet_index\n'
  cryptnet_patch+=$'        cryptnet_printed_context = true\n'
  cryptnet_patch+=$'        first = [cryptnet_index - 8, 0].max\n'
  cryptnet_patch+=$'        last = [cryptnet_index + 14, cryptnet_lines.length - 1].min\n'
  cryptnet_patch+=$'        $stderr.puts "Failed to patch cryptnet snprintf compatibility."\n'
  cryptnet_patch+=$'        $stderr.puts "Nearby cryptnet_main.c context around #{target}:"\n'
  cryptnet_patch+=$'        (first..last).each do |line_number|\n'
  cryptnet_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, cryptnet_lines[line_number])\n'
  cryptnet_patch+=$'        end\n'
  cryptnet_patch+=$'      end\n'
  cryptnet_patch+=$'      unless cryptnet_printed_context\n'
  cryptnet_patch+=$'        $stderr.puts "cryptnet snprintf target not found."\n'
  cryptnet_patch+=$'      end\n'
  cryptnet_patch+=$'      raise "failed to patch cryptnet snprintf compatibility"\n'
  cryptnet_patch+=$'    end\n'
  cryptnet_patch+=$'    File.write(cryptnet_path, cryptnet_source)\n\n'
  cryptnet_patch+="$build_marker"

  cryptnet_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_CRYPTNET_MARKER}\E/'
  cryptnet_patch_expression+='$ENV{WHISKYWINE_GPTK_CRYPTNET_PATCH}/'

  WHISKYWINE_GPTK_CRYPTNET_MARKER="$build_marker" \
  WHISKYWINE_GPTK_CRYPTNET_PATCH="$cryptnet_patch" \
    /usr/bin/perl -0pi -e "$cryptnet_patch_expression" \
    "$formula_path"

  if ! grep -q "cryptnet snprintf compatibility" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit cryptnet patch." >&2
    exit 1
  fi
}

patch_gptk_formula_dmusic_snprintf() {
  local formula_path="$1"
  local build_marker
  local dmusic_patch
  local dmusic_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  dmusic_patch=$'    dmusic_path = buildpath/"wine/dlls/dmusic/dmusic_main.c"\n'
  dmusic_patch+=$'    dmusic_source = File.read(dmusic_path)\n'
  dmusic_patch+=$'    dmusic_source.gsub!('
  dmusic_patch+=$'/int\\s+cnt\\s*=\\s*snprintf\\(\\s*ptr\\s*,\\s*size\\s*,\\s*"%s "\\s*,\\s*'
  dmusic_patch+=$'names\\[i\\]\\.name\\s*\\);\\s*\\n\\s*'
  dmusic_patch+=$'if\\s*\\(\\s*cnt\\s*<\\s*0\\s*\\|\\|\\s*cnt\\s*>=\\s*size\\s*\\)\\s*break;\\s*\\n\\s*'
  dmusic_patch+=$'size\\s*-=\\s*cnt;\\s*\\n\\s*ptr\\s*\\+=\\s*cnt;/m, '
  dmusic_patch+=$'"const char *name = names[i].name;\\n'
  dmusic_patch+=$'                while (*name && size > 1) { *ptr++ = *name++; size--; }\\n'
  dmusic_patch+=$'                if (*name || size <= 1) break;\\n'
  dmusic_patch+=$'                *ptr++ = \\" \\"[0];\\n'
  dmusic_patch+=$'                size--;\\n'
  dmusic_patch+=$'                *ptr = 0;")\n'
  dmusic_patch+=$'    dmusic_has_old_call = dmusic_source.include?("snprintf(")\n'
  dmusic_patch+=$'    dmusic_has_new_copy = '
  dmusic_patch+=$'dmusic_source.include?("const char *name = names[i].name;") && '
  dmusic_patch+=$'dmusic_source.include?("while (*name && size > 1)")\n'
  dmusic_patch+=$'    unless dmusic_has_new_copy && !dmusic_has_old_call\n'
  dmusic_patch+=$'      dmusic_lines = dmusic_source.lines\n'
  dmusic_patch+=$'      dmusic_printed_context = false\n'
  dmusic_patch+=$'      ["snprintf", "names[i].name", "size -= cnt", "ptr += cnt"].each do |target|\n'
  dmusic_patch+=$'        dmusic_index = dmusic_lines.find_index { |line| line.include?(target) }\n'
  dmusic_patch+=$'        next unless dmusic_index\n'
  dmusic_patch+=$'        dmusic_printed_context = true\n'
  dmusic_patch+=$'        first = [dmusic_index - 8, 0].max\n'
  dmusic_patch+=$'        last = [dmusic_index + 14, dmusic_lines.length - 1].min\n'
  dmusic_patch+=$'        $stderr.puts "Failed to patch dmusic snprintf compatibility."\n'
  dmusic_patch+=$'        $stderr.puts "Nearby dmusic_main.c context around #{target}:"\n'
  dmusic_patch+=$'        (first..last).each do |line_number|\n'
  dmusic_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, dmusic_lines[line_number])\n'
  dmusic_patch+=$'        end\n'
  dmusic_patch+=$'      end\n'
  dmusic_patch+=$'      unless dmusic_printed_context\n'
  dmusic_patch+=$'        $stderr.puts "dmusic snprintf target not found."\n'
  dmusic_patch+=$'      end\n'
  dmusic_patch+=$'      raise "failed to patch dmusic snprintf compatibility"\n'
  dmusic_patch+=$'    end\n'
  dmusic_patch+=$'    File.write(dmusic_path, dmusic_source)\n\n'
  dmusic_patch+="$build_marker"

  dmusic_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_DMUSIC_MARKER}\E/'
  dmusic_patch_expression+='$ENV{WHISKYWINE_GPTK_DMUSIC_PATCH}/'

  WHISKYWINE_GPTK_DMUSIC_MARKER="$build_marker" \
  WHISKYWINE_GPTK_DMUSIC_PATCH="$dmusic_patch" \
    /usr/bin/perl -0pi -e "$dmusic_patch_expression" \
    "$formula_path"

  if ! grep -q "dmusic snprintf compatibility" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit dmusic patch." >&2
    exit 1
  fi
}

patch_gptk_formula_jpeg_fprintf() {
  local formula_path="$1"
  local build_marker
  local jpeg_patch
  local jpeg_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  jpeg_patch=$'    jpeg_error_path = buildpath/"wine/libs/jpeg/jerror.c"\n'
  jpeg_patch+=$'    jpeg_error_source = File.read(jpeg_error_path)\n'
  jpeg_patch+=$'    jpeg_error_source.gsub!(/fprintf\\s*\\(\\s*stderr\\s*,[^;]*\\)\\s*;/m, '
  jpeg_patch+=$'"(void)buffer; /* jpeg fprintf compatibility */")\n'
  jpeg_patch+=$'    jpeg_error_source.gsub!(/fflush\\s*\\(\\s*stderr\\s*\\)\\s*;/, '
  jpeg_patch+=$'"/* jpeg stderr flush compatibility */")\n'
  jpeg_patch+=$'    jpeg_has_marker = '
  jpeg_patch+=$'jpeg_error_source.include?("jpeg fprintf compatibility")\n'
  jpeg_patch+=$'    jpeg_has_old_fprintf = '
  jpeg_patch+=$'jpeg_error_source.match?(/^[^*\\n]*\\bfprintf\\s*\\(/)\n'
  jpeg_patch+=$'    unless jpeg_has_marker && !jpeg_has_old_fprintf\n'
  jpeg_patch+=$'      jpeg_lines = jpeg_error_source.lines\n'
  jpeg_patch+=$'      jpeg_printed_context = false\n'
  jpeg_patch+=$'      ["fprintf", "fflush", "output_message", "buffer"].each do |target|\n'
  jpeg_patch+=$'        jpeg_index = jpeg_lines.find_index { |line| line.include?(target) }\n'
  jpeg_patch+=$'        next unless jpeg_index\n'
  jpeg_patch+=$'        jpeg_printed_context = true\n'
  jpeg_patch+=$'        first = [jpeg_index - 8, 0].max\n'
  jpeg_patch+=$'        last = [jpeg_index + 18, jpeg_lines.length - 1].min\n'
  jpeg_patch+=$'        $stderr.puts "Failed to patch bundled jpeg fprintf compatibility."\n'
  jpeg_patch+=$'        $stderr.puts "Nearby jerror.c context around #{target}:"\n'
  jpeg_patch+=$'        (first..last).each do |line_number|\n'
  jpeg_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, jpeg_lines[line_number])\n'
  jpeg_patch+=$'        end\n'
  jpeg_patch+=$'      end\n'
  jpeg_patch+=$'      unless jpeg_printed_context\n'
  jpeg_patch+=$'        $stderr.puts "bundled jpeg fprintf target not found."\n'
  jpeg_patch+=$'      end\n'
  jpeg_patch+=$'      raise "failed to patch bundled jpeg fprintf compatibility"\n'
  jpeg_patch+=$'    end\n'
  jpeg_patch+=$'    File.write(jpeg_error_path, jpeg_error_source)\n\n'
  jpeg_patch+="$build_marker"

  jpeg_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_JPEG_MARKER}\E/'
  jpeg_patch_expression+='$ENV{WHISKYWINE_GPTK_JPEG_PATCH}/'

  WHISKYWINE_GPTK_JPEG_MARKER="$build_marker" \
  WHISKYWINE_GPTK_JPEG_PATCH="$jpeg_patch" \
    /usr/bin/perl -0pi -e "$jpeg_patch_expression" \
    "$formula_path"

  if ! grep -q "bundled jpeg fprintf compatibility" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit bundled jpeg patch." >&2
    exit 1
  fi
}


patch_gptk_formula_hnetcfg_snprintf() {
  local formula_path="$1"
  local build_marker
  local hnetcfg_patch
  local hnetcfg_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  hnetcfg_patch=$'    hnetcfg_port_path = buildpath/"wine/dlls/hnetcfg/port.c"\n'
  hnetcfg_patch+=$'    hnetcfg_port_source = File.read(hnetcfg_port_path)\n'
  hnetcfg_patch+=$'    hnetcfg_port_source.gsub!(/snprintf\s*\(\s*ptr\s*,\s*request_data_size\s*,/m, "sprintf( ptr,")\n'
  hnetcfg_patch+=$'    hnetcfg_has_old_snprintf = hnetcfg_port_source.match?(/snprintf\s*\(/)\n'
  hnetcfg_patch+=$'    hnetcfg_has_new_sprintf = hnetcfg_port_source.scan(/sprintf\s*\(\s*ptr\s*,/).length >= 3\n'
  hnetcfg_patch+=$'    unless hnetcfg_has_new_sprintf && !hnetcfg_has_old_snprintf\n'
  hnetcfg_patch+=$'      hnetcfg_lines = hnetcfg_port_source.lines\n'
  hnetcfg_patch+=$'      hnetcfg_printed_context = false\n'
  hnetcfg_patch+=$'      ["snprintf", "sprintf", "request_data_size", "request_template_header"].each do |target|\n'
  hnetcfg_patch+=$'        hnetcfg_index = hnetcfg_lines.find_index { |line| line.include?(target) }\n'
  hnetcfg_patch+=$'        next unless hnetcfg_index\n'
  hnetcfg_patch+=$'        hnetcfg_printed_context = true\n'
  hnetcfg_patch+=$'        first = [hnetcfg_index - 8, 0].max\n'
  hnetcfg_patch+=$'        last = [hnetcfg_index + 18, hnetcfg_lines.length - 1].min\n'
  hnetcfg_patch+=$'        $stderr.puts "Failed to patch hnetcfg snprintf compatibility."\n'
  hnetcfg_patch+=$'        $stderr.puts "Nearby port.c context around #{target}:"\n'
  hnetcfg_patch+=$'        (first..last).each do |line_number|\n'
  hnetcfg_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, hnetcfg_lines[line_number])\n'
  hnetcfg_patch+=$'        end\n'
  hnetcfg_patch+=$'      end\n'
  hnetcfg_patch+=$'      unless hnetcfg_printed_context\n'
  hnetcfg_patch+=$'        $stderr.puts "hnetcfg snprintf target not found."\n'
  hnetcfg_patch+=$'      end\n'
  hnetcfg_patch+=$'      raise "failed to patch hnetcfg snprintf compatibility"\n'
  hnetcfg_patch+=$'    end\n'
  hnetcfg_patch+=$'    File.write(hnetcfg_port_path, hnetcfg_port_source)\n\n'
  hnetcfg_patch+="$build_marker"

  hnetcfg_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_HNETCFG_MARKER}\E/'
  hnetcfg_patch_expression+='$ENV{WHISKYWINE_GPTK_HNETCFG_PATCH}/'

  WHISKYWINE_GPTK_HNETCFG_MARKER="$build_marker" \
  WHISKYWINE_GPTK_HNETCFG_PATCH="$hnetcfg_patch" \
    /usr/bin/perl -0pi -e "$hnetcfg_patch_expression" \
    "$formula_path"

  if ! grep -q "hnetcfg snprintf compatibility" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit hnetcfg patch." >&2
    exit 1
  fi
}

patch_gptk_formula_inetcomm_snprintf() {
  local formula_path="$1"
  local build_marker
  local inetcomm_patch
  local inetcomm_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  inetcomm_patch=$'    inetcomm_path = buildpath/"wine/dlls/inetcomm/internettransport.c"\n'
  inetcomm_patch+=$'    inetcomm_source = File.read(inetcomm_path)\n'
  inetcomm_patch+=$'    inetcomm_source.gsub!('
  inetcomm_patch+=$'/snprintf\\(\\s*szPort\\s*,\\s*sizeof\\s*\\(\\s*szPort\\s*\\)\\s*,\\s*'
  inetcomm_patch+=$'"%d"\\s*,\\s*\\(\\s*unsigned\\s+short\\s*\\)\\s*pInetServer->dwPort\\s*\\)/, '
  inetcomm_patch+=$'"sprintf(szPort, \\"%d\\", (unsigned short)pInetServer->dwPort) /* inetcomm snprintf compatibility */")\n'
  inetcomm_patch+=$'    inetcomm_has_marker = inetcomm_source.include?("inetcomm snprintf compatibility")\n'
  inetcomm_patch+=$'    inetcomm_has_new_call = '
  inetcomm_patch+=$'inetcomm_source.match?(/sprintf\\(\\s*szPort\\s*,\\s*"%d"\\s*,\\s*\\(\\s*unsigned\\s+short\\s*\\)\\s*pInetServer->dwPort\\s*\\)/)\n'
  inetcomm_patch+=$'    inetcomm_has_old_call = inetcomm_source.match?(/\\bsnprintf\\s*\\(/)\n'
  inetcomm_patch+=$'    unless inetcomm_has_marker && inetcomm_has_new_call && !inetcomm_has_old_call\n'
  inetcomm_patch+=$'      inetcomm_lines = inetcomm_source.lines\n'
  inetcomm_patch+=$'      inetcomm_printed_context = false\n'
  inetcomm_patch+=$'      ["snprintf", "sprintf(szPort", "szPort", "getaddrinfo"].each do |target|\n'
  inetcomm_patch+=$'        inetcomm_index = inetcomm_lines.find_index { |line| line.include?(target) }\n'
  inetcomm_patch+=$'        next unless inetcomm_index\n'
  inetcomm_patch+=$'        inetcomm_printed_context = true\n'
  inetcomm_patch+=$'        first = [inetcomm_index - 8, 0].max\n'
  inetcomm_patch+=$'        last = [inetcomm_index + 18, inetcomm_lines.length - 1].min\n'
  inetcomm_patch+=$'        $stderr.puts "Failed to patch inetcomm snprintf compatibility."\n'
  inetcomm_patch+=$'        $stderr.puts "Nearby internettransport.c context around #{target}:"\n'
  inetcomm_patch+=$'        (first..last).each do |line_number|\n'
  inetcomm_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, inetcomm_lines[line_number])\n'
  inetcomm_patch+=$'        end\n'
  inetcomm_patch+=$'      end\n'
  inetcomm_patch+=$'      unless inetcomm_printed_context\n'
  inetcomm_patch+=$'        $stderr.puts "inetcomm snprintf target not found."\n'
  inetcomm_patch+=$'      end\n'
  inetcomm_patch+=$'      raise "failed to patch inetcomm snprintf compatibility"\n'
  inetcomm_patch+=$'    end\n'
  inetcomm_patch+=$'    File.write(inetcomm_path, inetcomm_source)\n\n'
  inetcomm_patch+="$build_marker"

  inetcomm_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_INETCOMM_MARKER}\E/'
  inetcomm_patch_expression+='$ENV{WHISKYWINE_GPTK_INETCOMM_PATCH}/'

  WHISKYWINE_GPTK_INETCOMM_MARKER="$build_marker" \
  WHISKYWINE_GPTK_INETCOMM_PATCH="$inetcomm_patch" \
    /usr/bin/perl -0pi -e "$inetcomm_patch_expression" \
    "$formula_path"

  if ! grep -q "inetcomm snprintf compatibility" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit inetcomm patch." >&2
    exit 1
  fi
}

patch_gptk_formula_rpcrt4_snprintf() {
  local formula_path="$1"
  local build_marker
  local rpcrt4_patch
  local rpcrt4_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  rpcrt4_patch=$'    rpcrt4_transport_path = buildpath/"wine/dlls/rpcrt4/rpc_transport.c"\n'
  rpcrt4_patch+=$'    rpcrt4_transport_source = File.read(rpcrt4_transport_path)\n'
  rpcrt4_patch+=$'    unless rpcrt4_transport_source.include?("rpcrt4 snprintf compatibility")\n'
  rpcrt4_patch+=$'      rpcrt4_transport_source.sub!(/WINE_DEFAULT_DEBUG_CHANNEL\\([^\\n]+\\);/, "\\\\0\\n\\n#ifndef snprintf\\n#define snprintf(buffer, size, ...) sprintf(buffer, __VA_ARGS__) /* rpcrt4 snprintf compatibility */\\n#endif")\n'
  rpcrt4_patch+=$'    end\n'
  rpcrt4_patch+=$'    rpcrt4_has_marker = rpcrt4_transport_source.include?("rpcrt4 snprintf compatibility")\n'
  rpcrt4_patch+=$'    rpcrt4_has_macro = '
  rpcrt4_patch+=$'rpcrt4_transport_source.include?("#define snprintf(buffer, size, ...) sprintf(buffer, __VA_ARGS__)")\n'
  rpcrt4_patch+=$'    unless rpcrt4_has_marker && rpcrt4_has_macro\n'
  rpcrt4_patch+=$'      rpcrt4_lines = rpcrt4_transport_source.lines\n'
  rpcrt4_patch+=$'      rpcrt4_printed_context = false\n'
  rpcrt4_patch+=$'      ["snprintf", "WINE_DEFAULT_DEBUG_CHANNEL", "rpc_transport", "ncacn"].each do |target|\n'
  rpcrt4_patch+=$'        rpcrt4_index = rpcrt4_lines.find_index { |line| line.include?(target) }\n'
  rpcrt4_patch+=$'        next unless rpcrt4_index\n'
  rpcrt4_patch+=$'        rpcrt4_printed_context = true\n'
  rpcrt4_patch+=$'        first = [rpcrt4_index - 8, 0].max\n'
  rpcrt4_patch+=$'        last = [rpcrt4_index + 18, rpcrt4_lines.length - 1].min\n'
  rpcrt4_patch+=$'        $stderr.puts "Failed to patch rpcrt4 snprintf compatibility."\n'
  rpcrt4_patch+=$'        $stderr.puts "Nearby rpc_transport.c context around #{target}:"\n'
  rpcrt4_patch+=$'        (first..last).each do |line_number|\n'
  rpcrt4_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, rpcrt4_lines[line_number])\n'
  rpcrt4_patch+=$'        end\n'
  rpcrt4_patch+=$'      end\n'
  rpcrt4_patch+=$'      unless rpcrt4_printed_context\n'
  rpcrt4_patch+=$'        $stderr.puts "rpcrt4 snprintf target not found."\n'
  rpcrt4_patch+=$'      end\n'
  rpcrt4_patch+=$'      raise "failed to patch rpcrt4 snprintf compatibility"\n'
  rpcrt4_patch+=$'    end\n'
  rpcrt4_patch+=$'    File.write(rpcrt4_transport_path, rpcrt4_transport_source)\n\n'
  rpcrt4_patch+="$build_marker"

  rpcrt4_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_RPCRT4_MARKER}\E/'
  rpcrt4_patch_expression+='$ENV{WHISKYWINE_GPTK_RPCRT4_PATCH}/'

  WHISKYWINE_GPTK_RPCRT4_MARKER="$build_marker" \
  WHISKYWINE_GPTK_RPCRT4_PATCH="$rpcrt4_patch" \
    /usr/bin/perl -0pi -e "$rpcrt4_patch_expression" \
    "$formula_path"

  if ! grep -q "rpcrt4 snprintf compatibility" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit rpcrt4 patch." >&2
    exit 1
  fi
}

patch_gptk_formula_ole_formatting() {
  local formula_path="$1"
  local build_marker
  local ole_patch
  local ole_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  ole_patch=$'    ole32_main_path = buildpath/"wine/dlls/ole32/ole32_main.c"\n'
  ole_patch+=$'    ole32_main_source = File.read(ole32_main_path)\n'
  ole_patch+=$'    ole32_main_source.gsub!('
  ole_patch+=$'/snprintf\\(\\s*szIconIndex\\s*,\\s*10\\s*,\\s*"%u"\\s*,\\s*iIconIndex\\s*\\)/, '
  ole_patch+=$'"sprintf(szIconIndex, \\"%u\\", iIconIndex) /* ole32 snprintf compatibility */")\n'
  ole_patch+=$'    ole32_has_marker = ole32_main_source.include?("ole32 snprintf compatibility")\n'
  ole_patch+=$'    ole32_has_new_call = '
  ole_patch+=$'ole32_main_source.match?(/sprintf\\(\\s*szIconIndex\\s*,\\s*"%u"\\s*,\\s*iIconIndex\\s*\\)/)\n'
  ole_patch+=$'    ole32_has_old_call = ole32_main_source.match?(/\\bsnprintf\\s*\\(/)\n'
  ole_patch+=$'    unless ole32_has_marker && ole32_has_new_call && !ole32_has_old_call\n'
  ole_patch+=$'      ole32_lines = ole32_main_source.lines\n'
  ole_patch+=$'      ole32_printed_context = false\n'
  ole_patch+=$'      ["snprintf", "sprintf(szIconIndex", "szIconIndex", "ExtEscape"].each do |target|\n'
  ole_patch+=$'        ole32_index = ole32_lines.find_index { |line| line.include?(target) }\n'
  ole_patch+=$'        next unless ole32_index\n'
  ole_patch+=$'        ole32_printed_context = true\n'
  ole_patch+=$'        first = [ole32_index - 8, 0].max\n'
  ole_patch+=$'        last = [ole32_index + 14, ole32_lines.length - 1].min\n'
  ole_patch+=$'        $stderr.puts "Failed to patch ole32 snprintf compatibility."\n'
  ole_patch+=$'        $stderr.puts "Nearby ole32_main.c context around #{target}:"\n'
  ole_patch+=$'        (first..last).each do |line_number|\n'
  ole_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, ole32_lines[line_number])\n'
  ole_patch+=$'        end\n'
  ole_patch+=$'      end\n'
  ole_patch+=$'      unless ole32_printed_context\n'
  ole_patch+=$'        $stderr.puts "ole32 snprintf target not found."\n'
  ole_patch+=$'      end\n'
  ole_patch+=$'      raise "failed to patch ole32 snprintf compatibility"\n'
  ole_patch+=$'    end\n'
  ole_patch+=$'    File.write(ole32_main_path, ole32_main_source)\n\n'
  ole_patch+=$'    oleaut_vartype_path = buildpath/"wine/dlls/oleaut32/vartype.c"\n'
  ole_patch+=$'    oleaut_vartype_source = File.read(oleaut_vartype_path)\n'
  ole_patch+=$'    oleaut_vartype_source.gsub!('
  ole_patch+=$'/_swprintf_l\\(\\s*buff\\s*,\\s*ARRAY_SIZE\\(\\s*buff\\s*\\)\\s*,\\s*'
  ole_patch+=$'lpszFormat\\s*,\\s*locale\\s*,\\s*dblIn\\s*\\)/, '
  ole_patch+=$'"swprintf(buff, ARRAY_SIZE(buff), lpszFormat, dblIn) /* oleaut32 swprintf_l compatibility */")\n'
  ole_patch+=$'    oleaut_has_marker = oleaut_vartype_source.include?("oleaut32 swprintf_l compatibility")\n'
  ole_patch+=$'    oleaut_has_new_call = '
  ole_patch+=$'oleaut_vartype_source.match?(/swprintf\\(\\s*buff\\s*,\\s*ARRAY_SIZE\\(\\s*buff\\s*\\)\\s*,\\s*lpszFormat\\s*,\\s*dblIn\\s*\\)/)\n'
  ole_patch+=$'    oleaut_has_old_call = oleaut_vartype_source.match?(/\\b_swprintf_l\\s*\\(/)\n'
  ole_patch+=$'    unless oleaut_has_marker && oleaut_has_new_call && !oleaut_has_old_call\n'
  ole_patch+=$'      oleaut_lines = oleaut_vartype_source.lines\n'
  ole_patch+=$'      oleaut_printed_context = false\n'
  ole_patch+=$'      ["_swprintf_l", "swprintf(buff", "VARIANT_BstrFromReal", "lpszFormat"].each do |target|\n'
  ole_patch+=$'        oleaut_index = oleaut_lines.find_index { |line| line.include?(target) }\n'
  ole_patch+=$'        next unless oleaut_index\n'
  ole_patch+=$'        oleaut_printed_context = true\n'
  ole_patch+=$'        first = [oleaut_index - 8, 0].max\n'
  ole_patch+=$'        last = [oleaut_index + 14, oleaut_lines.length - 1].min\n'
  ole_patch+=$'        $stderr.puts "Failed to patch oleaut32 swprintf_l compatibility."\n'
  ole_patch+=$'        $stderr.puts "Nearby vartype.c context around #{target}:"\n'
  ole_patch+=$'        (first..last).each do |line_number|\n'
  ole_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, oleaut_lines[line_number])\n'
  ole_patch+=$'        end\n'
  ole_patch+=$'      end\n'
  ole_patch+=$'      unless oleaut_printed_context\n'
  ole_patch+=$'        $stderr.puts "oleaut32 swprintf_l target not found."\n'
  ole_patch+=$'      end\n'
  ole_patch+=$'      raise "failed to patch oleaut32 swprintf_l compatibility"\n'
  ole_patch+=$'    end\n'
  ole_patch+=$'    File.write(oleaut_vartype_path, oleaut_vartype_source)\n\n'
  ole_patch+="$build_marker"

  ole_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_OLE_MARKER}\E/'
  ole_patch_expression+='$ENV{WHISKYWINE_GPTK_OLE_PATCH}/'

  WHISKYWINE_GPTK_OLE_MARKER="$build_marker" \
  WHISKYWINE_GPTK_OLE_PATCH="$ole_patch" \
    /usr/bin/perl -0pi -e "$ole_patch_expression" \
    "$formula_path"

  if ! grep -q "ole32 snprintf compatibility" "$formula_path" || \
     ! grep -q "oleaut32 swprintf_l compatibility" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit ole formatting patch." >&2
    exit 1
  fi
}

patch_gptk_formula_oledb32_swscanf() {
  local formula_path="$1"
  local build_marker
  local oledb_patch
  local oledb_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  oledb_patch=$'    oledb_convert_path = buildpath/"wine/dlls/oledb32/convert.c"\n'
  oledb_patch+=$'    oledb_convert_source = File.read(oledb_convert_path)\n'
  oledb_patch+=$'    unless oledb_convert_source.include?("oledb32 swscanf compatibility")\n'
  oledb_patch+=$'      oledb_parser = <<~OLEDB_PARSER\n'
  oledb_patch+=$'        static BOOL parse_dbtimestamp_compat(const WCHAR *str, DBTIMESTAMP *timestamp)\n'
  oledb_patch+=$'        {\n'
  oledb_patch+=$'            static const WCHAR separators[] = {45, 45, 32, 58, 58, 46, 0};\n'
  oledb_patch+=$'            int values[7];\n'
  oledb_patch+=$'            unsigned int i;\n'
  oledb_patch+=$'\n'
  oledb_patch+=$'            for (i = 0; i < ARRAY_SIZE(values); i++)\n'
  oledb_patch+=$'            {\n'
  oledb_patch+=$'                int value = 0, digits = 0;\n'
  oledb_patch+=$'\n'
  oledb_patch+=$'                while (*str >= 48 && *str <= 57)\n'
  oledb_patch+=$'                {\n'
  oledb_patch+=$'                    value = value * 10 + *str++ - 48;\n'
  oledb_patch+=$'                    digits++;\n'
  oledb_patch+=$'                }\n'
  oledb_patch+=$'                if (!digits) return FALSE;\n'
  oledb_patch+=$'                values[i] = value;\n'
  oledb_patch+=$'                if (separators[i] && *str++ != separators[i]) return FALSE;\n'
  oledb_patch+=$'            }\n'
  oledb_patch+=$'\n'
  oledb_patch+=$'            timestamp->year = values[0];\n'
  oledb_patch+=$'            timestamp->month = values[1];\n'
  oledb_patch+=$'            timestamp->day = values[2];\n'
  oledb_patch+=$'            timestamp->hour = values[3];\n'
  oledb_patch+=$'            timestamp->minute = values[4];\n'
  oledb_patch+=$'            timestamp->second = values[5];\n'
  oledb_patch+=$'            timestamp->fraction = values[6];\n'
  oledb_patch+=$'            return TRUE; /* oledb32 swscanf compatibility */\n'
  oledb_patch+=$'        }\n'
  oledb_patch+=$'      OLEDB_PARSER\n'
  oledb_patch+=$'      oledb_convert_source.sub!(/WINE_DEFAULT_DEBUG_CHANNEL\\(oledb\\);/, "\\\\0\\n\\n#{oledb_parser}")\n'
  oledb_patch+=$'    end\n'
  oledb_patch+=$'    oledb_convert_source.gsub!('
  oledb_patch+=$'/swscanf\\(\\s*s\\s*,\\s*L"%d-%d-%d %d:%d:%d\\.%d"\\s*,\\s*'
  oledb_patch+=$'&d->year\\s*,\\s*&d->month\\s*,\\s*&d->day\\s*,\\s*&d->hour\\s*,\\s*&d->minute\\s*,\\s*'
  oledb_patch+=$'&d->second\\s*,\\s*&d->fraction\\s*\\)\\s*!=\\s*7/m, '
  oledb_patch+=$'"!parse_dbtimestamp_compat(s, d)")\n'
  oledb_patch+=$'    oledb_has_marker = oledb_convert_source.include?("oledb32 swscanf compatibility")\n'
  oledb_patch+=$'    oledb_has_new_call = oledb_convert_source.include?("!parse_dbtimestamp_compat(s, d)")\n'
  oledb_patch+=$'    oledb_has_old_call = oledb_convert_source.match?(/\\bswscanf\\s*\\(/)\n'
  oledb_patch+=$'    unless oledb_has_marker && oledb_has_new_call && !oledb_has_old_call\n'
  oledb_patch+=$'      oledb_lines = oledb_convert_source.lines\n'
  oledb_patch+=$'      oledb_printed_context = false\n'
  oledb_patch+=$'      ["swscanf", "parse_dbtimestamp_compat", "DBTYPE_DBTIMESTAMP", "WINE_DEFAULT_DEBUG_CHANNEL"].each do |target|\n'
  oledb_patch+=$'        oledb_index = oledb_lines.find_index { |line| line.include?(target) }\n'
  oledb_patch+=$'        next unless oledb_index\n'
  oledb_patch+=$'        oledb_printed_context = true\n'
  oledb_patch+=$'        first = [oledb_index - 8, 0].max\n'
  oledb_patch+=$'        last = [oledb_index + 18, oledb_lines.length - 1].min\n'
  oledb_patch+=$'        $stderr.puts "Failed to patch oledb32 swscanf compatibility."\n'
  oledb_patch+=$'        $stderr.puts "Nearby convert.c context around #{target}:"\n'
  oledb_patch+=$'        (first..last).each do |line_number|\n'
  oledb_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, oledb_lines[line_number])\n'
  oledb_patch+=$'        end\n'
  oledb_patch+=$'      end\n'
  oledb_patch+=$'      unless oledb_printed_context\n'
  oledb_patch+=$'        $stderr.puts "oledb32 swscanf target not found."\n'
  oledb_patch+=$'      end\n'
  oledb_patch+=$'      raise "failed to patch oledb32 swscanf compatibility"\n'
  oledb_patch+=$'    end\n'
  oledb_patch+=$'    File.write(oledb_convert_path, oledb_convert_source)\n\n'
  oledb_patch+="$build_marker"

  oledb_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_OLEDB_MARKER}\E/'
  oledb_patch_expression+='$ENV{WHISKYWINE_GPTK_OLEDB_PATCH}/'

  WHISKYWINE_GPTK_OLEDB_MARKER="$build_marker" \
  WHISKYWINE_GPTK_OLEDB_PATCH="$oledb_patch" \
    /usr/bin/perl -0pi -e "$oledb_patch_expression" \
    "$formula_path"

  if ! grep -q "oledb32 swscanf compatibility" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit oledb32 patch." >&2
    exit 1
  fi
}

patch_gptk_formula_mpg123_kernelbase_formatting() {
  local formula_path="$1"
  local build_marker
  local format_patch
  local format_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  format_patch=$'    mpg123_ntom_path = buildpath/"wine/libs/mpg123/src/libmpg123/ntom.c"\n'
  format_patch+=$'    mpg123_ntom_source = File.read(mpg123_ntom_path)\n'
  format_patch+=$'    mpg123_ntom_source.gsub!('
  format_patch+=$'/if\\s*\\(\\s*VERBOSE2\\s*\\)\\s*\\n\\s*fprintf\\s*\\(\\s*stderr\\s*,\\s*"Init rate converter: %ld->%ld\\\\n"\\s*,\\s*m\\s*,\\s*n\\s*\\)\\s*;/m, '
  format_patch+=$'"if (VERBOSE2) { /* mpg123 fprintf compatibility */ }")\n'
  format_patch+=$'    mpg123_has_marker = mpg123_ntom_source.include?("mpg123 fprintf compatibility")\n'
  format_patch+=$'    mpg123_has_old_call = mpg123_ntom_source.match?(/^[^*\\n]*\\bfprintf\\s*\\(/)\n'
  format_patch+=$'    unless mpg123_has_marker && !mpg123_has_old_call\n'
  format_patch+=$'      mpg123_lines = mpg123_ntom_source.lines\n'
  format_patch+=$'      mpg123_printed_context = false\n'
  format_patch+=$'      ["fprintf", "VERBOSE2", "Init rate converter", "frame_freq"].each do |target|\n'
  format_patch+=$'        mpg123_index = mpg123_lines.find_index { |line| line.include?(target) }\n'
  format_patch+=$'        next unless mpg123_index\n'
  format_patch+=$'        mpg123_printed_context = true\n'
  format_patch+=$'        first = [mpg123_index - 8, 0].max\n'
  format_patch+=$'        last = [mpg123_index + 14, mpg123_lines.length - 1].min\n'
  format_patch+=$'        $stderr.puts "Failed to patch bundled mpg123 fprintf compatibility."\n'
  format_patch+=$'        $stderr.puts "Nearby ntom.c context around #{target}:"\n'
  format_patch+=$'        (first..last).each do |line_number|\n'
  format_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, mpg123_lines[line_number])\n'
  format_patch+=$'        end\n'
  format_patch+=$'      end\n'
  format_patch+=$'      unless mpg123_printed_context\n'
  format_patch+=$'        $stderr.puts "bundled mpg123 fprintf target not found."\n'
  format_patch+=$'      end\n'
  format_patch+=$'      raise "failed to patch bundled mpg123 fprintf compatibility"\n'
  format_patch+=$'    end\n'
  format_patch+=$'    File.write(mpg123_ntom_path, mpg123_ntom_source)\n\n'
  format_patch+=$'    kernelbase_debug_path = buildpath/"wine/dlls/kernelbase/debug.c"\n'
  format_patch+=$'    kernelbase_debug_source = File.read(kernelbase_debug_path)\n'
  format_patch+=$'    unless kernelbase_debug_source.include?("kernelbase snprintf compatibility")\n'
  format_patch+=$'      kernelbase_debug_source.sub!(/WINE_DEFAULT_DEBUG_CHANNEL\\([^\\n]+\\);/, "\\\\0\\n\\n#ifndef snprintf\\n#define snprintf(buffer, size, ...) sprintf(buffer, __VA_ARGS__) /* kernelbase snprintf compatibility */\\n#endif")\n'
  format_patch+=$'    end\n'
  format_patch+=$'    kernelbase_has_marker = kernelbase_debug_source.include?("kernelbase snprintf compatibility")\n'
  format_patch+=$'    kernelbase_has_macro = '
  format_patch+=$'kernelbase_debug_source.include?("#define snprintf(buffer, size, ...) sprintf(buffer, __VA_ARGS__)")\n'
  format_patch+=$'    unless kernelbase_has_marker && kernelbase_has_macro\n'
  format_patch+=$'      kernelbase_lines = kernelbase_debug_source.lines\n'
  format_patch+=$'      kernelbase_printed_context = false\n'
  format_patch+=$'      ["snprintf", "WINE_DEFAULT_DEBUG_CHANNEL", "format_exception_msg", "Unhandled"].each do |target|\n'
  format_patch+=$'        kernelbase_index = kernelbase_lines.find_index { |line| line.include?(target) }\n'
  format_patch+=$'        next unless kernelbase_index\n'
  format_patch+=$'        kernelbase_printed_context = true\n'
  format_patch+=$'        first = [kernelbase_index - 8, 0].max\n'
  format_patch+=$'        last = [kernelbase_index + 18, kernelbase_lines.length - 1].min\n'
  format_patch+=$'        $stderr.puts "Failed to patch kernelbase snprintf compatibility."\n'
  format_patch+=$'        $stderr.puts "Nearby debug.c context around #{target}:"\n'
  format_patch+=$'        (first..last).each do |line_number|\n'
  format_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, kernelbase_lines[line_number])\n'
  format_patch+=$'        end\n'
  format_patch+=$'      end\n'
  format_patch+=$'      unless kernelbase_printed_context\n'
  format_patch+=$'        $stderr.puts "kernelbase snprintf target not found."\n'
  format_patch+=$'      end\n'
  format_patch+=$'      raise "failed to patch kernelbase snprintf compatibility"\n'
  format_patch+=$'    end\n'
  format_patch+=$'    File.write(kernelbase_debug_path, kernelbase_debug_source)\n\n'
  format_patch+="$build_marker"

  format_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_FORMAT_MARKER}\E/'
  format_patch_expression+='$ENV{WHISKYWINE_GPTK_FORMAT_PATCH}/'

  WHISKYWINE_GPTK_FORMAT_MARKER="$build_marker" \
  WHISKYWINE_GPTK_FORMAT_PATCH="$format_patch" \
    /usr/bin/perl -0pi -e "$format_patch_expression" \
    "$formula_path"

  if ! grep -q "mpg123 fprintf compatibility" "$formula_path" || \
     ! grep -q "kernelbase snprintf compatibility" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit mpg123/kernelbase patch." >&2
    exit 1
  fi
}

patch_gptk_formula_ntdll_formatting() {
  local formula_path="$1"
  local build_marker
  local ntdll_patch
  local ntdll_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  ntdll_patch=$'    ntdll_format_files = %w[\n'
  ntdll_patch+=$'      atom.c\n'
  ntdll_patch+=$'      actctx.c\n'
  ntdll_patch+=$'      loader.c\n'
  ntdll_patch+=$'      locale.c\n'
  ntdll_patch+=$'      relay.c\n'
  ntdll_patch+=$'      rtl.c\n'
  ntdll_patch+=$'      rtlstr.c\n'
  ntdll_patch+=$'      sec.c\n'
  ntdll_patch+=$'      thread.c\n'
  ntdll_patch+=$'    ]\n'
  ntdll_patch+=$'    ntdll_format_block = <<~NTDLL_FORMAT_COMPAT\n'
  ntdll_patch+=$'      /* Avoid MinGW CRT formatting imports when linking ntdll. */\n'
  ntdll_patch+=$'      extern int CDECL _vsnprintf( char *str, SIZE_T len, const char *format, va_list args );\n'
  ntdll_patch+=$'      extern int CDECL _vsnwprintf( WCHAR *str, SIZE_T len, const WCHAR *format, va_list args );\n'
  ntdll_patch+=$'\n'
  ntdll_patch+=$'      static int __wine_ntdll_compat_sprintf( char *str, const char *format, ... )\n'
  ntdll_patch+=$'      {\n'
  ntdll_patch+=$'          int ret;\n'
  ntdll_patch+=$'          va_list args;\n'
  ntdll_patch+=$'\n'
  ntdll_patch+=$'          va_start( args, format );\n'
  ntdll_patch+=$'          ret = _vsnprintf( str, ~(SIZE_T)0 >> 1, format, args );\n'
  ntdll_patch+=$'          va_end( args );\n'
  ntdll_patch+=$'          return ret;\n'
  ntdll_patch+=$'      }\n'
  ntdll_patch+=$'\n'
  ntdll_patch+=$'      static int __wine_ntdll_compat_snprintf( char *str, SIZE_T len, const char *format, ... )\n'
  ntdll_patch+=$'      {\n'
  ntdll_patch+=$'          int ret;\n'
  ntdll_patch+=$'          va_list args;\n'
  ntdll_patch+=$'\n'
  ntdll_patch+=$'          va_start( args, format );\n'
  ntdll_patch+=$'          ret = _vsnprintf( str, len, format, args );\n'
  ntdll_patch+=$'          va_end( args );\n'
  ntdll_patch+=$'          return ret;\n'
  ntdll_patch+=$'      }\n'
  ntdll_patch+=$'\n'
  ntdll_patch+=$'      static int __wine_ntdll_compat_swprintf( WCHAR *str, SIZE_T len, const WCHAR *format, ... )\n'
  ntdll_patch+=$'      {\n'
  ntdll_patch+=$'          int ret;\n'
  ntdll_patch+=$'          va_list args;\n'
  ntdll_patch+=$'\n'
  ntdll_patch+=$'          va_start( args, format );\n'
  ntdll_patch+=$'          ret = _vsnwprintf( str, len, format, args );\n'
  ntdll_patch+=$'          va_end( args );\n'
  ntdll_patch+=$'          return ret;\n'
  ntdll_patch+=$'      }\n'
  ntdll_patch+=$'\n'
  ntdll_patch+=$'      #undef sprintf\n'
  ntdll_patch+=$'      #undef snprintf\n'
  ntdll_patch+=$'      #undef swprintf\n'
  ntdll_patch+=$'      #define sprintf __wine_ntdll_compat_sprintf\n'
  ntdll_patch+=$'      #define snprintf __wine_ntdll_compat_snprintf\n'
  ntdll_patch+=$'      #define swprintf __wine_ntdll_compat_swprintf\n'
  ntdll_patch+=$'    NTDLL_FORMAT_COMPAT\n'
  ntdll_patch+=$'    ntdll_format_files.each do |file|\n'
  ntdll_patch+=$'      ntdll_path = buildpath/"wine/dlls/ntdll/#{file}"\n'
  ntdll_patch+=$'      ntdll_source = File.read(ntdll_path)\n'
  ntdll_patch+=$'      ntdll_target_count = ntdll_source.scan(/\\b(?:sprintf|snprintf|swprintf)\\s*\\(/).length\n'
  ntdll_patch+=$'      unless ntdll_source.include?("Avoid MinGW CRT formatting imports when linking ntdll.")\n'
  ntdll_patch+=$'        ntdll_source.sub!(/WINE_DEFAULT_DEBUG_CHANNEL\\([^\\n]+\\);/, "\\\\0\\n\\n#{ntdll_format_block}")\n'
  ntdll_patch+=$'      end\n'
  ntdll_patch+=$'      ntdll_has_block = ntdll_source.include?("Avoid MinGW CRT formatting imports when linking ntdll.")\n'
  ntdll_patch+=$'      ntdll_has_macros = %w[sprintf snprintf swprintf].all? do |name|\n'
  ntdll_patch+=$'        ntdll_source.include?("#define #{name} __wine_ntdll_compat_#{name}")\n'
  ntdll_patch+=$'      end\n'
  ntdll_patch+=$'      unless ntdll_target_count.positive? && ntdll_has_block && ntdll_has_macros\n'
  ntdll_patch+=$'        ntdll_lines = ntdll_source.lines\n'
  ntdll_patch+=$'        ntdll_printed_context = false\n'
  ntdll_patch+=$'        ["sprintf", "snprintf", "swprintf", "WINE_DEFAULT_DEBUG_CHANNEL"].each do |target|\n'
  ntdll_patch+=$'          ntdll_index = ntdll_lines.find_index { |line| line.include?(target) }\n'
  ntdll_patch+=$'          next unless ntdll_index\n'
  ntdll_patch+=$'          ntdll_printed_context = true\n'
  ntdll_patch+=$'          first = [ntdll_index - 8, 0].max\n'
  ntdll_patch+=$'          last = [ntdll_index + 18, ntdll_lines.length - 1].min\n'
  ntdll_patch+=$'          $stderr.puts "Failed to patch ntdll CRT formatting imports in #{ntdll_path}."\n'
  ntdll_patch+=$'          $stderr.puts "Nearby context around #{target}:"\n'
  ntdll_patch+=$'          (first..last).each do |line_number|\n'
  ntdll_patch+=$'            $stderr.printf("%5d: %s", line_number + 1, ntdll_lines[line_number])\n'
  ntdll_patch+=$'          end\n'
  ntdll_patch+=$'        end\n'
  ntdll_patch+=$'        unless ntdll_printed_context\n'
  ntdll_patch+=$'          $stderr.puts "ntdll formatting targets not found in #{ntdll_path}."\n'
  ntdll_patch+=$'        end\n'
  ntdll_patch+=$'        raise "failed to patch ntdll CRT formatting imports"\n'
  ntdll_patch+=$'      end\n'
  ntdll_patch+=$'      File.write(ntdll_path, ntdll_source)\n'
  ntdll_patch+=$'    end\n\n'
  ntdll_patch+="$build_marker"

  ntdll_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_NTDLL_FORMAT_MARKER}\E/'
  ntdll_patch_expression+='$ENV{WHISKYWINE_GPTK_NTDLL_FORMAT_PATCH}/'

  WHISKYWINE_GPTK_NTDLL_FORMAT_MARKER="$build_marker" \
  WHISKYWINE_GPTK_NTDLL_FORMAT_PATCH="$ntdll_patch" \
    /usr/bin/perl -0pi -e "$ntdll_patch_expression" \
    "$formula_path"

  if ! grep -q "ntdll CRT formatting imports" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit ntdll formatting patch." >&2
    exit 1
  fi
}

patch_gptk_formula_msiquery_vswprintf() {
  local formula_path="$1"
  local build_marker
  local msiquery_patch
  local msiquery_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  msiquery_patch=$'    msiquery_path = buildpath/"wine/dlls/msi/msiquery.c"\n'
  msiquery_patch+=$'    msiquery_source = File.read(msiquery_path)\n'
  msiquery_patch+=$'    unless msiquery_source.include?(\'#include "wine/unicode.h"\')\n'
  msiquery_patch+=$'      msiquery_source.gsub!(\'#include "wine/debug.h"\', '
  msiquery_patch+=$'\'#include "wine/debug.h"\\n#include "wine/unicode.h"\')\n'
  msiquery_patch+=$'    end\n'
  msiquery_patch+=$'    msiquery_source.gsub!(/\\bvswprintf\\s*\\(/, "_vsnwprintf(")\n'
  msiquery_patch+=$'    msiquery_has_unicode = '
  msiquery_patch+=$'msiquery_source.include?(\'#include "wine/unicode.h"\')\n'
  msiquery_patch+=$'    msiquery_has_new_calls = '
  msiquery_patch+=$'msiquery_source.scan(/\\b_vsnwprintf\\s*\\(/).length == 2\n'
  msiquery_patch+=$'    msiquery_has_old_calls = '
  msiquery_patch+=$'msiquery_source.match?(/\\bvswprintf\\s*\\(/)\n'
  msiquery_patch+=$'    unless msiquery_has_unicode && msiquery_has_new_calls && '
  msiquery_patch+=$'!msiquery_has_old_calls\n'
  msiquery_patch+=$'      msiquery_lines = msiquery_source.lines\n'
  msiquery_patch+=$'      msiquery_printed_context = false\n'
  msiquery_patch+=$'      ["wine/debug.h", "wine/unicode.h", "vswprintf", '
  msiquery_patch+=$'"_vsnwprintf"].each do |target|\n'
  msiquery_patch+=$'        msiquery_index = msiquery_lines.find_index do |line|\n'
  msiquery_patch+=$'          line.include?(target)\n'
  msiquery_patch+=$'        end\n'
  msiquery_patch+=$'        next unless msiquery_index\n'
  msiquery_patch+=$'        msiquery_printed_context = true\n'
  msiquery_patch+=$'        first = [msiquery_index - 8, 0].max\n'
  msiquery_patch+=$'        last = [msiquery_index + 14, msiquery_lines.length - 1].min\n'
  msiquery_patch+=$'        $stderr.puts "Failed to patch msiquery vswprintf imports."\n'
  msiquery_patch+=$'        $stderr.puts "Nearby msiquery.c context around #{target}:"\n'
  msiquery_patch+=$'        (first..last).each do |line_number|\n'
  msiquery_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, '
  msiquery_patch+=$'msiquery_lines[line_number])\n'
  msiquery_patch+=$'        end\n'
  msiquery_patch+=$'      end\n'
  msiquery_patch+=$'      unless msiquery_printed_context\n'
  msiquery_patch+=$'        $stderr.puts "msiquery vswprintf targets not found."\n'
  msiquery_patch+=$'      end\n'
  msiquery_patch+=$'      raise "failed to patch msiquery vswprintf imports"\n'
  msiquery_patch+=$'    end\n'
  msiquery_patch+=$'    File.write(msiquery_path, msiquery_source)\n\n'
  msiquery_patch+="$build_marker"

  msiquery_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_MSIQUERY_MARKER}\E/'
  msiquery_patch_expression+='$ENV{WHISKYWINE_GPTK_MSIQUERY_PATCH}/'

  WHISKYWINE_GPTK_MSIQUERY_MARKER="$build_marker" \
  WHISKYWINE_GPTK_MSIQUERY_PATCH="$msiquery_patch" \
    /usr/bin/perl -0pi -e "$msiquery_patch_expression" \
    "$formula_path"

  if ! grep -q "msiquery vswprintf imports" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit msiquery patch." >&2
    exit 1
  fi
}

patch_gptk_formula_msvcp_locale_scprintf() {
  local formula_path="$1"
  local build_marker
  local locale_patch
  local locale_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  locale_patch=$'    msvcp_locale_path = buildpath/"wine/dlls/msvcp90/locale.c"\n'
  locale_patch+=$'    msvcp_locale_source = File.read(msvcp_locale_path)\n'
  locale_patch+=$'    msvcp_locale_source.gsub!('
  locale_patch+=$'/prec = get_precision\\(base\\);\\n\\s*size = _scprintf\\(fmt, prec, v\\);/, '
  locale_patch+=$'"prec = get_precision(base);\\n    if (prec > 1048576) prec = 1048576;'
  locale_patch+=$' /* msvcp locale _scprintf compatibility */\\n    size = prec + 512;")\n'
  locale_patch+=$'    msvcp_locale_has_marker = '
  locale_patch+=$'msvcp_locale_source.scan(/msvcp locale _scprintf compatibility/).length == 3\n'
  locale_patch+=$'    msvcp_locale_has_bad_calls = '
  locale_patch+=$'msvcp_locale_source.match?(/\\b_scprintf\\s*\\(/)\n'
  locale_patch+=$'    msvcp_locale_has_size_patch = '
  locale_patch+=$'msvcp_locale_source.scan(/size = prec \\+ 512;/).length == 3\n'
  locale_patch+=$'    unless msvcp_locale_has_marker && !msvcp_locale_has_bad_calls && '
  locale_patch+=$'msvcp_locale_has_size_patch\n'
  locale_patch+=$'      msvcp_locale_lines = msvcp_locale_source.lines\n'
  locale_patch+=$'      msvcp_locale_printed_context = false\n'
  locale_patch+=$'      ["get_precision", "_scprintf", "size = prec + 512"].each do |target|\n'
  locale_patch+=$'        msvcp_locale_index = msvcp_locale_lines.find_index do |line|\n'
  locale_patch+=$'          line.include?(target)\n'
  locale_patch+=$'        end\n'
  locale_patch+=$'        next unless msvcp_locale_index\n'
  locale_patch+=$'        msvcp_locale_printed_context = true\n'
  locale_patch+=$'        first = [msvcp_locale_index - 8, 0].max\n'
  locale_patch+=$'        last = [msvcp_locale_index + 14, msvcp_locale_lines.length - 1].min\n'
  locale_patch+=$'        $stderr.puts "Failed to patch msvcp locale _CRTIMP compatibility."\n'
  locale_patch+=$'        $stderr.puts "Nearby msvcp90/locale.c context around #{target}:"\n'
  locale_patch+=$'        (first..last).each do |line_number|\n'
  locale_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, '
  locale_patch+=$'msvcp_locale_lines[line_number])\n'
  locale_patch+=$'        end\n'
  locale_patch+=$'      end\n'
  locale_patch+=$'      unless msvcp_locale_printed_context\n'
  locale_patch+=$'        $stderr.puts "msvcp locale _scprintf targets not found."\n'
  locale_patch+=$'      end\n'
  locale_patch+=$'      raise "failed to patch msvcp locale _scprintf compatibility"\n'
  locale_patch+=$'    end\n'
  locale_patch+=$'    File.write(msvcp_locale_path, msvcp_locale_source)\n\n'
  locale_patch+="$build_marker"

  locale_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_MSVCP_LOCALE_MARKER}\E/'
  locale_patch_expression+='$ENV{WHISKYWINE_GPTK_MSVCP_LOCALE_PATCH}/'

  WHISKYWINE_GPTK_MSVCP_LOCALE_MARKER="$build_marker" \
  WHISKYWINE_GPTK_MSVCP_LOCALE_PATCH="$locale_patch" \
    /usr/bin/perl -0pi -e "$locale_patch_expression" \
    "$formula_path"

  if ! grep -q "msvcp locale _scprintf compatibility" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit msvcp locale patch." >&2
    exit 1
  fi
}

patch_gptk_formula_d3dcompiler_asmshader() {
  local formula_path="$1"
  local build_marker
  local asmshader_patch
  local asmshader_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  asmshader_patch=$'    asmshader_path = buildpath/"wine/dlls/d3dcompiler_43/asmshader.l"\n'
  asmshader_patch+=$'    asmshader_source = File.read(asmshader_path)\n'
  asmshader_patch+=$'    unless asmshader_source.include?("asmshader flex fprintf compatibility")\n'
  asmshader_patch+=$'      asmshader_source.gsub!('
  asmshader_patch+=$'/WINE_DEFAULT_DEBUG_CHANNEL\\(asmshader\\);/, '
  asmshader_patch+=$'"WINE_DEFAULT_DEBUG_CHANNEL(asmshader);\\n\\n'
  asmshader_patch+=$'/* Avoid MinGW importing fprintf from the generated flex fatal-error helper. */\\n'
  asmshader_patch+=$'#ifndef fprintf\\n#define fprintf(...) ((void)0) '
  asmshader_patch+=$'/* asmshader flex fprintf compatibility */\\n#endif")\n'
  asmshader_patch+=$'    end\n'
  asmshader_patch+=$'    asmshader_has_marker = '
  asmshader_patch+=$'asmshader_source.include?("asmshader flex fprintf compatibility")\n'
  asmshader_patch+=$'    asmshader_has_macro = '
  asmshader_patch+=$'asmshader_source.match?(/#define\\s+fprintf\\s*\\(\\.\\.\\.\\)\\s+'
  asmshader_patch+=$'\\(\\(void\\)0\\)/)\n'
  asmshader_patch+=$'    asmshader_has_call = '
  asmshader_patch+=$'asmshader_source.match?(/^[^#\\n]*\\bfprintf\\s*\\(/)\n'
  asmshader_patch+=$'    unless asmshader_has_marker && asmshader_has_macro && '
  asmshader_patch+=$'!asmshader_has_call\n'
  asmshader_patch+=$'      asmshader_lines = asmshader_source.lines\n'
  asmshader_patch+=$'      asmshader_printed_context = false\n'
  asmshader_patch+=$'      ["fprintf", "asmshader", "WINE_DEFAULT_DEBUG_CHANNEL"].each do |target|\n'
  asmshader_patch+=$'        asmshader_index = asmshader_lines.find_index do |line|\n'
  asmshader_patch+=$'          line.include?(target)\n'
  asmshader_patch+=$'        end\n'
  asmshader_patch+=$'        next unless asmshader_index\n'
  asmshader_patch+=$'        asmshader_printed_context = true\n'
  asmshader_patch+=$'        first = [asmshader_index - 8, 0].max\n'
  asmshader_patch+=$'        last = [asmshader_index + 14, asmshader_lines.length - 1].min\n'
  asmshader_patch+=$'        $stderr.puts "Failed to patch d3dcompiler asmshader flex fprintf."\n'
  asmshader_patch+=$'        $stderr.puts "Nearby asmshader.l context around #{target}:"\n'
  asmshader_patch+=$'        (first..last).each do |line_number|\n'
  asmshader_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, '
  asmshader_patch+=$'asmshader_lines[line_number])\n'
  asmshader_patch+=$'        end\n'
  asmshader_patch+=$'      end\n'
  asmshader_patch+=$'      unless asmshader_printed_context\n'
  asmshader_patch+=$'        $stderr.puts "d3dcompiler asmshader/fprintf targets not found."\n'
  asmshader_patch+=$'      end\n'
  asmshader_patch+=$'      raise "failed to patch d3dcompiler asmshader flex fprintf"\n'
  asmshader_patch+=$'    end\n'
  asmshader_patch+=$'    File.write(asmshader_path, asmshader_source)\n\n'
  asmshader_patch+="$build_marker"

  asmshader_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_ASMSHADER_MARKER}\E/'
  asmshader_patch_expression+='$ENV{WHISKYWINE_GPTK_ASMSHADER_PATCH}/'

  WHISKYWINE_GPTK_ASMSHADER_MARKER="$build_marker" \
  WHISKYWINE_GPTK_ASMSHADER_PATCH="$asmshader_patch" \
    /usr/bin/perl -0pi -e "$asmshader_patch_expression" \
    "$formula_path"

  if ! grep -q "asmshader flex fprintf compatibility" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit d3dcompiler asmshader patch." >&2
    exit 1
  fi
}

patch_gptk_formula_msxml_stdio() {
  local formula_path="$1"
  local build_marker
  local msxml_patch
  local msxml_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  msxml_patch=$'    xml2_header_path = buildpath/"wine/libs/xml2/libxml.h"\n'
  msxml_patch+=$'    xml2_header_source = File.read(xml2_header_path)\n'
  msxml_patch+=$'    unless xml2_header_source.include?("xml2 stdio inline compatibility")\n'
  msxml_patch+=$'      xml2_header_source.gsub!(/#ifndef WITH_TRIO/, '
  msxml_patch+=$'"#ifdef _NO_CRT_STDIO_INLINE\\n#undef _NO_CRT_STDIO_INLINE\\n'
  msxml_patch+=$'#endif /* xml2 stdio inline compatibility */\\n\\n#ifndef WITH_TRIO")\n'
  msxml_patch+=$'    end\n'
  msxml_patch+=$'    xslt_header_path = buildpath/"wine/libs/xslt/libxslt/libxslt.h"\n'
  msxml_patch+=$'    xslt_header_source = File.read(xslt_header_path)\n'
  msxml_patch+=$'    unless xslt_header_source.include?("xslt stdio inline compatibility")\n'
  msxml_patch+=$'      xslt_header_source.gsub!(/#include <libxslt\\/xsltconfig\\.h>/, '
  msxml_patch+=$'"#ifdef _NO_CRT_STDIO_INLINE\\n#undef _NO_CRT_STDIO_INLINE\\n'
  msxml_patch+=$'#endif /* xslt stdio inline compatibility */\\n\\n'
  msxml_patch+=$'#include <libxslt/xsltconfig.h>")\n'
  msxml_patch+=$'    end\n'
  msxml_patch+=$'    xslpattern_path = buildpath/"wine/dlls/msxml3/xslpattern.l"\n'
  msxml_patch+=$'    xslpattern_source = File.read(xslpattern_path)\n'
  msxml_patch+=$'    unless xslpattern_source.include?("xslpattern flex fprintf compatibility")\n'
  msxml_patch+=$'      xslpattern_source.gsub!('
  msxml_patch+=$'/WINE_DEFAULT_DEBUG_CHANNEL\\(msxml\\);/, '
  msxml_patch+=$'"WINE_DEFAULT_DEBUG_CHANNEL(msxml);\\n\\n'
  msxml_patch+=$'/* Avoid MinGW importing fprintf from the generated flex fatal-error helper. */\\n'
  msxml_patch+=$'#ifndef fprintf\\n#define fprintf(...) ((void)0) '
  msxml_patch+=$'/* xslpattern flex fprintf compatibility */\\n#endif")\n'
  msxml_patch+=$'    end\n'
  msxml_patch+=$'    msxml_targets = {\n'
  msxml_patch+=$'      "xml2 libxml.h" => [xml2_header_source, '
  msxml_patch+=$'"xml2 stdio inline compatibility"],\n'
  msxml_patch+=$'      "xslt libxslt.h" => [xslt_header_source, '
  msxml_patch+=$'"xslt stdio inline compatibility"],\n'
  msxml_patch+=$'      "msxml3 xslpattern.l" => [xslpattern_source, '
  msxml_patch+=$'"xslpattern flex fprintf compatibility"]\n'
  msxml_patch+=$'    }\n'
  msxml_patch+=$'    msxml_failed_target = msxml_targets.find do |_name, pair|\n'
  msxml_patch+=$'      !pair.first.include?(pair.last)\n'
  msxml_patch+=$'    end\n'
  msxml_patch+=$'    xslpattern_has_macro = '
  msxml_patch+=$'xslpattern_source.match?(/#define\\s+fprintf\\s*\\(\\.\\.\\.\\)\\s+'
  msxml_patch+=$'\\(\\(void\\)0\\)/)\n'
  msxml_patch+=$'    unless msxml_failed_target.nil? && xslpattern_has_macro\n'
  msxml_patch+=$'      [[xml2_header_path, xml2_header_source], '
  msxml_patch+=$'[xslt_header_path, xslt_header_source], '
  msxml_patch+=$'[xslpattern_path, xslpattern_source]].each do |path, source|\n'
  msxml_patch+=$'        source_lines = source.lines\n'
  msxml_patch+=$'        ["_NO_CRT_STDIO_INLINE", "fprintf", "WINE_DEFAULT_DEBUG_CHANNEL"].each do |target|\n'
  msxml_patch+=$'          source_index = source_lines.find_index { |line| line.include?(target) }\n'
  msxml_patch+=$'          next unless source_index\n'
  msxml_patch+=$'          first = [source_index - 8, 0].max\n'
  msxml_patch+=$'          last = [source_index + 14, source_lines.length - 1].min\n'
  msxml_patch+=$'          $stderr.puts "Failed to patch msxml/xml stdio compatibility in #{path}."\n'
  msxml_patch+=$'          $stderr.puts "Nearby context around #{target}:"\n'
  msxml_patch+=$'          (first..last).each do |line_number|\n'
  msxml_patch+=$'            $stderr.printf("%5d: %s", line_number + 1, source_lines[line_number])\n'
  msxml_patch+=$'          end\n'
  msxml_patch+=$'        end\n'
  msxml_patch+=$'      end\n'
  msxml_patch+=$'      raise "failed to patch msxml/xml stdio compatibility"\n'
  msxml_patch+=$'    end\n'
  msxml_patch+=$'    File.write(xml2_header_path, xml2_header_source)\n'
  msxml_patch+=$'    File.write(xslt_header_path, xslt_header_source)\n'
  msxml_patch+=$'    File.write(xslpattern_path, xslpattern_source)\n\n'
  msxml_patch+="$build_marker"

  msxml_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_MSXML_MARKER}\E/'
  msxml_patch_expression+='$ENV{WHISKYWINE_GPTK_MSXML_PATCH}/'

  WHISKYWINE_GPTK_MSXML_MARKER="$build_marker" \
  WHISKYWINE_GPTK_MSXML_PATCH="$msxml_patch" \
    /usr/bin/perl -0pi -e "$msxml_patch_expression" \
    "$formula_path"

  if ! grep -q "msxml/xml stdio compatibility" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit msxml stdio patch." >&2
    exit 1
  fi
}

patch_gptk_formula_mfreadwrite_reader() {
  local formula_path="$1"
  local build_marker
  local reader_patch
  local reader_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  reader_patch=$'    reader_path = buildpath/"wine/dlls/mfreadwrite/reader.c"\n'
  reader_patch+=$'    reader_source = File.read(reader_path)\n'
  reader_patch+=$'    reader_source.gsub!(/\\bunsigned\\s+int\\s+i\\s*,\\s*j\\s*,\\s*'
  reader_patch+=$'length\\s*=\\s*0\\s*,\\s*caps\\s*=\\s*0\\s*;/, '
  reader_patch+=$'"unsigned int i, j;\\n    UINT32 length = 0;\\n    DWORD caps = 0;'
  reader_patch+=$'\\n    ULONG read_length = 0;")\n'
  reader_patch+=$'    reader_source.gsub!('
  reader_patch+=$'/(IMFByteStream_Read\\(\\s*stream\\s*,\\s*buffer\\s*,\\s*'
  reader_patch+=$'sizeof\\s*\\(\\s*buffer\\s*\\)\\s*,\\s*)&length(\\s*\\))/, '
  reader_patch+=$'"\\\\1&read_length\\\\2")\n'
  reader_patch+=$'    reader_has_new_caps = '
  reader_patch+=$'reader_source.match?(/\\bDWORD\\s+caps\\s*=\\s*0\\s*;/)\n'
  reader_patch+=$'    reader_has_new_length = '
  reader_patch+=$'reader_source.match?(/\\bUINT32\\s+length\\s*=\\s*0\\s*;/)\n'
  reader_patch+=$'    reader_has_read_length = '
  reader_patch+=$'reader_source.match?(/\\bULONG\\s+read_length\\s*=\\s*0\\s*;/)\n'
  reader_patch+=$'    reader_read_uses_read_length = '
  reader_patch+=$'reader_source.match?(/IMFByteStream_Read\\([^;]*&read_length\\s*\\)/m)\n'
  reader_patch+=$'    reader_attrs_uses_length = '
  reader_patch+=$'reader_source.match?(/IMFAttributes_GetStringLength\\([^;]*&length\\s*\\)/m)\n'
  reader_patch+=$'    reader_has_bad_combined = '
  reader_patch+=$'reader_source.match?(/\\bunsigned\\s+int\\s+i\\s*,\\s*j\\s*,\\s*'
  reader_patch+=$'length\\s*=\\s*0\\s*,\\s*caps\\s*=\\s*0\\s*;/)\n'
  reader_patch+=$'    unless reader_has_new_caps && reader_has_new_length && '
  reader_patch+=$'reader_has_read_length && reader_read_uses_read_length && '
  reader_patch+=$'reader_attrs_uses_length && !reader_has_bad_combined\n'
  reader_patch+=$'      reader_lines = reader_source.lines\n'
  reader_patch+=$'      reader_printed_context = false\n'
  reader_patch+=$'      ["caps", "length", "read_length", "IMFByteStream_Read", '
  reader_patch+=$'"IMFAttributes_GetStringLength", "bytestream_get_url_hint"].each do |target|\n'
  reader_patch+=$'        reader_index = reader_lines.find_index do |line|\n'
  reader_patch+=$'          line.include?(target)\n'
  reader_patch+=$'        end\n'
  reader_patch+=$'        next unless reader_index\n'
  reader_patch+=$'        reader_printed_context = true\n'
  reader_patch+=$'        first = [reader_index - 8, 0].max\n'
  reader_patch+=$'        last = [reader_index + 14, reader_lines.length - 1].min\n'
  reader_patch+=$'        $stderr.puts "Failed to patch mfreadwrite reader types."\n'
  reader_patch+=$'        $stderr.puts "Nearby reader.c context around #{target}:"\n'
  reader_patch+=$'        (first..last).each do |line_number|\n'
  reader_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, '
  reader_patch+=$'reader_lines[line_number])\n'
  reader_patch+=$'        end\n'
  reader_patch+=$'      end\n'
  reader_patch+=$'      unless reader_printed_context\n'
  reader_patch+=$'        $stderr.puts "mfreadwrite reader targets not found."\n'
  reader_patch+=$'      end\n'
  reader_patch+=$'      raise "failed to patch mfreadwrite reader types"\n'
  reader_patch+=$'    end\n'
  reader_patch+=$'    File.write(reader_path, reader_source)\n\n'
  reader_patch+="$build_marker"

  reader_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_READER_MARKER}\E/'
  reader_patch_expression+='$ENV{WHISKYWINE_GPTK_READER_PATCH}/'

  WHISKYWINE_GPTK_READER_MARKER="$build_marker" \
  WHISKYWINE_GPTK_READER_PATCH="$reader_patch" \
    /usr/bin/perl -0pi -e "$reader_patch_expression" \
    "$formula_path"

  if ! grep -q "mfreadwrite reader types" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit mfreadwrite patch." >&2
    exit 1
  fi
}

patch_gptk_formula_wow64cpu() {
  local formula_path="$1"
  local build_marker
  local wow64cpu_patch
  local wow64cpu_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  wow64cpu_patch=$'    inreplace "wine/dlls/wow64cpu/cpu.c",\n'
  wow64cpu_patch+=$'      "context->Rsp = NtCurrentTeb()->TlsSlots[2];",\n'
  wow64cpu_patch+=$'      "context->Rsp = '
  wow64cpu_patch+=$'(DWORD64)(ULONG_PTR)NtCurrentTeb()->TlsSlots[2];"\n\n'
  wow64cpu_patch+="$build_marker"

  wow64cpu_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_WOW64CPU_MARKER}\E/'
  wow64cpu_patch_expression+='$ENV{WHISKYWINE_GPTK_WOW64CPU_PATCH}/'

  WHISKYWINE_GPTK_WOW64CPU_MARKER="$build_marker" \
  WHISKYWINE_GPTK_WOW64CPU_PATCH="$wow64cpu_patch" \
    /usr/bin/perl -0pi -e "$wow64cpu_patch_expression" \
    "$formula_path"

  if ! grep -q "(DWORD64)(ULONG_PTR)NtCurrentTeb" "$formula_path"; then
    echo "Failed to patch game-porting-toolkit wow64cpu source edit." >&2
    exit 1
  fi
}

patch_gptk_formula_winhlp32() {
  local formula_path="$1"
  local build_marker
  local winhlp32_patch
  local winhlp32_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  winhlp32_patch=$'    inreplace "wine/programs/winhlp32/macro.h",\n'
  winhlp32_patch+=$'      "BOOL          bool;",\n'
  winhlp32_patch+=$'      "BOOL          boolean;"\n\n'
  winhlp32_patch+="$build_marker"

  winhlp32_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_WINHLP32_MARKER}\E/'
  winhlp32_patch_expression+='$ENV{WHISKYWINE_GPTK_WINHLP32_PATCH}/'

  WHISKYWINE_GPTK_WINHLP32_MARKER="$build_marker" \
  WHISKYWINE_GPTK_WINHLP32_PATCH="$winhlp32_patch" \
    /usr/bin/perl -0pi -e "$winhlp32_patch_expression" \
    "$formula_path"

  if ! grep -q "BOOL          boolean;" "$formula_path"; then
    echo "Failed to patch game-porting-toolkit winhlp32 source edit." >&2
    exit 1
  fi
}

patch_gptk_formula_atiadlxx() {
  local formula_path="$1"
  local build_marker
  local atiadlxx_patch
  local atiadlxx_patch_expression

  build_marker=$'    # Build 64-bit Wine first.'

  atiadlxx_patch=$'    atiadlxx_path = '
  atiadlxx_patch+=$'buildpath/"wine/dlls/atiadlxx/atiadlxx_main.c"\n'
  atiadlxx_patch+=$'    atiadlxx_source = File.read(atiadlxx_path)\n'
  atiadlxx_patch+=$'    atiadlxx_pattern = /ADL_Adapter_AdapterInfo_Get\\(\\s*'
  atiadlxx_patch+=$'\\*info\\s*,\\s*sizeof\\s*\\(\\s*ADLAdapterInfo\\s*\\)\\s*\\)/\n'
  atiadlxx_patch+=$'    atiadlxx_replacement = '
  atiadlxx_patch+=$'"ADL_Adapter_AdapterInfo_Get((ADLAdapterInfo *)*info, "\n'
  atiadlxx_patch+=$'    atiadlxx_replacement += "sizeof(ADLAdapterInfo))"\n'
  atiadlxx_patch+=$'    unless atiadlxx_source.sub!(atiadlxx_pattern, '
  atiadlxx_patch+=$'atiadlxx_replacement)\n'
  atiadlxx_patch+=$'      atiadlxx_lines = atiadlxx_source.lines\n'
  atiadlxx_patch+=$'      atiadlxx_index = atiadlxx_lines.find_index do |line|\n'
  atiadlxx_patch+=$'        line.include?("ADL_Adapter_AdapterInfo_Get") && '
  atiadlxx_patch+=$'line.include?("*info")\n'
  atiadlxx_patch+=$'      end\n'
  atiadlxx_patch+=$'      atiadlxx_index ||= atiadlxx_lines.find_index do |line|\n'
  atiadlxx_patch+=$'        line.include?("ADL_Adapter_AdapterInfo_Get")\n'
  atiadlxx_patch+=$'      end\n'
  atiadlxx_patch+=$'      if atiadlxx_index\n'
  atiadlxx_patch+=$'        first = [atiadlxx_index - 5, 0].max\n'
  atiadlxx_patch+=$'        last = [atiadlxx_index + 5, '
  atiadlxx_patch+=$'atiadlxx_lines.length - 1].min\n'
  atiadlxx_patch+=$'        $stderr.puts "Failed to patch atiadlxx adapter info."\n'
  atiadlxx_patch+=$'        $stderr.puts "Nearby atiadlxx_main.c context:"\n'
  atiadlxx_patch+=$'        (first..last).each do |line_number|\n'
  atiadlxx_patch+=$'          $stderr.printf("%5d: %s", line_number + 1, '
  atiadlxx_patch+=$'atiadlxx_lines[line_number])\n'
  atiadlxx_patch+=$'        end\n'
  atiadlxx_patch+=$'      else\n'
  atiadlxx_patch+=$'        $stderr.puts "ADL_Adapter_AdapterInfo_Get not found."\n'
  atiadlxx_patch+=$'      end\n'
  atiadlxx_patch+=$'      raise "failed to patch atiadlxx adapter info"\n'
  atiadlxx_patch+=$'    end\n'
  atiadlxx_patch+=$'    File.write(atiadlxx_path, atiadlxx_source)\n\n'
  atiadlxx_patch+="$build_marker"

  atiadlxx_patch_expression='s/\Q$ENV{WHISKYWINE_GPTK_ATIADLXX_MARKER}\E/'
  atiadlxx_patch_expression+='$ENV{WHISKYWINE_GPTK_ATIADLXX_PATCH}/'

  WHISKYWINE_GPTK_ATIADLXX_MARKER="$build_marker" \
  WHISKYWINE_GPTK_ATIADLXX_PATCH="$atiadlxx_patch" \
    /usr/bin/perl -0pi -e "$atiadlxx_patch_expression" \
    "$formula_path"

  if ! grep -Fq "atiadlxx_pattern" "$formula_path"; then
    echo "Failed to insert game-porting-toolkit atiadlxx runtime patch." >&2
    exit 1
  fi
}

prepare_gptk_formula() {
  local tap_suffix
  local tap_path
  local formula_path

  cleanup_formula_patch_tap
  cleanup_stale_patch_taps

  tap_suffix="$(date +%s)-$$"
  formula_patch_tap="${patch_tap_prefix}-gptk-${tap_suffix}"

  echo "Creating temporary Homebrew tap: $formula_patch_tap" >&2
  brew tap-new --no-git "$formula_patch_tap" >/dev/null

  tap_path="$(brew --repository "$formula_patch_tap")"
  formula_path="$tap_path/Formula/game-porting-toolkit.rb"

  brew cat "$gptk_formula" > "$formula_path"
  patch_gptk_formula_openssl "$formula_path"
  patch_gptk_formula_sdkroot "$formula_path"
  patch_gptk_formula_cross_cflags "$formula_path"
  patch_gptk_formula_wcstring "$formula_path"
  patch_gptk_formula_msvcrt_wcs "$formula_path"
  patch_gptk_formula_http_sys "$formula_path"
  patch_gptk_formula_jscript_bool "$formula_path"
  patch_gptk_formula_msi_cond_bool "$formula_path"
  patch_gptk_formula_winecrt0_debug "$formula_path"
  patch_gptk_formula_dbghelp_msc "$formula_path"
  patch_gptk_formula_cryptnet_snprintf "$formula_path"
  patch_gptk_formula_dmusic_snprintf "$formula_path"
  patch_gptk_formula_jpeg_fprintf "$formula_path"
  patch_gptk_formula_hnetcfg_snprintf "$formula_path"
  patch_gptk_formula_inetcomm_snprintf "$formula_path"
  patch_gptk_formula_rpcrt4_snprintf "$formula_path"
  patch_gptk_formula_ole_formatting "$formula_path"
  patch_gptk_formula_oledb32_swscanf "$formula_path"
  patch_gptk_formula_mpg123_kernelbase_formatting "$formula_path"
  patch_gptk_formula_ntdll_formatting "$formula_path"
  patch_gptk_formula_msiquery_vswprintf "$formula_path"
  patch_gptk_formula_msvcp_locale_scprintf "$formula_path"
  patch_gptk_formula_d3dcompiler_asmshader "$formula_path"
  patch_gptk_formula_msxml_stdio "$formula_path"
  patch_gptk_formula_mfreadwrite_reader "$formula_path"
  patch_gptk_formula_wow64cpu "$formula_path"
  patch_gptk_formula_winhlp32 "$formula_path"
  patch_gptk_formula_atiadlxx "$formula_path"

  echo "$formula_patch_tap/game-porting-toolkit"
}

install_gptk_formula() {
  local formula_name

  formula_name="$(prepare_gptk_formula)"
  brew install "$formula_name"
  cleanup_formula_patch_tap
}

process_arch() {
  local current_arch
  current_arch="$(arch)"

  if [[ "$current_arch" == "i386" ]]; then
    echo "x86_64"
  else
    echo "$current_arch"
  fi
}

require_supported_gptk_architecture() {
  local gptk_formula_contents
  gptk_formula_contents="$(brew cat "$gptk_formula")"
  if [[ "$gptk_formula_contents" != *'depends_on arch: :x86_64'* ]]; then
    return
  fi

  local current_arch
  local brew_prefix
  local brew_macos
  local translated
  current_arch="$(process_arch)"
  brew_prefix="$(brew --prefix)"
  brew_macos="$(brew config | awk -F': ' '/^macOS:/ {print $2}')"
  translated="$(sysctl -in sysctl.proc_translated 2>/dev/null || echo 0)"

  if [[ "$current_arch" == "x86_64" && "$brew_macos" != *"arm64"* ]]; then
    return
  fi

  cat >&2 <<ERROR
The official $gptk_formula formula requires an x86_64 Homebrew build:

  depends_on arch: :x86_64

The old $gptk_compiler_formula formula intentionally builds an x86_64-native
clang for that Wine build. This script is currently running with:

  process arch: $current_arch
  translated:   $translated
  brew prefix:  $brew_prefix
  brew macOS:   $brew_macos

Do not force the old formula's x86_64 CMake flags from native arm64 Homebrew.
Run this rebuild from an x86_64/Rosetta shell with Intel Homebrew instead:

  softwareupdate --install-rosetta --agree-to-license
  arch -x86_64 /bin/zsh
  export PATH="/usr/local/bin:/usr/local/sbin:\$PATH"
  brew tap "$tap_name" "$tap_url"
  cd "$repo_root"
  WHISKYWINE_ACK_GPTK_LOCAL_TESTING=1 Scripts/build-whiskywine-libraries.sh

If /usr/local/bin/brew is missing, install Intel Homebrew from the Rosetta shell
before rerunning the build.
ERROR
  exit 1
}

install_gptk_compiler() {
  if [[ "$gptk_compiler_install_done" == "1" ]] || gptk_compiler_installed; then
    gptk_compiler_install_done=1
    echo "Using installed game-porting-toolkit-compiler: $(gptk_compiler_keg_path)"
    cleanup_formula_patch_tap
    cleanup_stale_patch_taps
    return
  fi

  case "$cmake_strategy" in
    cmake@3)
      if ! brew info "$cmake3_formula" >/dev/null 2>&1; then
        echo "$cmake3_formula is not available; falling back to CMake policy compatibility flag."
        local formula_name
        formula_name="$(prepare_gptk_compiler_formula policy)"
        install_gptk_compiler_formula "$formula_name"
        require_gptk_compiler_installed
        cleanup_formula_patch_tap
        return
      fi

      echo "Installing $cmake3_formula for this compiler build"
      brew install "$cmake3_formula"
      local cmake3_prefix
      cmake3_prefix="$(brew --prefix "$cmake3_formula")"
      export PATH="$cmake3_prefix/bin:$PATH"
      local cmake3_version
      cmake3_version="$("$cmake3_prefix/bin/cmake" --version | head -n 1)"
      echo "Using $cmake3_version for game-porting-toolkit-compiler"

      local formula_name
      formula_name="$(prepare_gptk_compiler_formula cmake@3)"
      install_gptk_compiler_formula "$formula_name"
      require_gptk_compiler_installed
      cleanup_formula_patch_tap
      ;;
    policy)
      echo "Using CMAKE_POLICY_VERSION_MINIMUM=$cmake_policy_version_minimum for compiler build"
      local formula_name
      formula_name="$(prepare_gptk_compiler_formula policy)"
      install_gptk_compiler_formula "$formula_name"
      require_gptk_compiler_installed
      cleanup_formula_patch_tap
      ;;
    none)
      install_gptk_compiler_formula "$gptk_compiler_formula"
      require_gptk_compiler_installed
      ;;
    *)
      echo "Unknown WHISKYWINE_CMAKE_STRATEGY: $cmake_strategy" >&2
      echo "Expected one of: cmake@3, policy, none" >&2
      exit 1
      ;;
  esac
}

require_command brew
require_command curl
require_command ditto
require_command find
require_command tar

echo "Using builder assets from: $builder_dir"
require_dir "$libs_dir" "extra WhiskyBuilder libs"
require_dir "$dxvk_dir" "DXVK"
require_dir "$gptk_redist_lib_dir" "GPTK redist/lib"
require_file "$version_plist" "GPTKVersion.plist"

echo "Tapping Homebrew formula source: $tap_name $tap_url"
brew tap "$tap_name" "$tap_url"

echo "Installing Homebrew formulas"
require_supported_gptk_architecture
install_gptk_compiler
require_gptk_compiler_installed
cleanup_formula_patch_tap
cleanup_stale_patch_taps
install_gptk_formula
cleanup_formula_patch_tap
cleanup_stale_patch_taps
brew install "$winetricks_formula"

gptk_prefix="${WHISKYWINE_GPTK_PREFIX:-$(brew --prefix game-porting-toolkit)}"
winetricks_prefix="${WHISKYWINE_WINETRICKS_PREFIX:-$(brew --prefix winetricks)}"

require_dir "$gptk_prefix" "game-porting-toolkit Homebrew prefix"
require_file "$winetricks_prefix/bin/winetricks" "winetricks executable"

echo "Recreating staging directory: $libraries_dir"
rm -rf "$staging_root"
mkdir -p "$libraries_dir/Wine"

echo "Copying game-porting-toolkit into Libraries/Wine"
ditto "$gptk_prefix" "$libraries_dir/Wine"

echo "Trimming copied Wine files"
rm -rf "$libraries_dir/Wine/.brew"
rm -rf "$libraries_dir/Wine/include"
rm -rf "$libraries_dir/Wine/INSTALL_RECEIPT.json"
rm -rf "$libraries_dir/Wine/share/man"
if [[ -d "$libraries_dir/Wine/bin" ]]; then
  find "$libraries_dir/Wine/bin" \
    -type f \
    ! -name "wine64" \
    ! -name "wine64-preloader" \
    ! -name "wineserver" \
    -delete
  find "$libraries_dir/Wine/bin" -type l -delete
fi

echo "Copying winetricks"
cp -a "$winetricks_prefix/bin/winetricks" "$libraries_dir/"

echo "Copying WhiskyBuilder libs"
mkdir -p "$libraries_dir/Wine/lib"
cp -a "$libs_dir/." "$libraries_dir/Wine/lib/"

echo "Copying DXVK"
cp -a "$dxvk_dir" "$libraries_dir/"

echo "Copying version plist"
cp -a "$version_plist" "$libraries_dir/GPTKVersion.plist"

echo "Downloading winetricks verbs list"
curl --fail --location --retry 3 "$verbs_url" -o "$libraries_dir/verbs.txt"

echo "Copying local-testing-only GPTK redist files"
ditto "$gptk_redist_lib_dir" "$libraries_dir/Wine/lib/"
ln -sfn ./external/libd3dshared.dylib "$libraries_dir/Wine/lib/libd3dshared.dylib"
ln -sfn ./external/D3DMetal.framework "$libraries_dir/Wine/lib/D3DMetal.framework"

"$script_dir/package-whiskywine-libraries.sh" "$libraries_dir" "$archive_path"

echo "Local-testing-only WhiskyWine archive ready: $archive_path"
