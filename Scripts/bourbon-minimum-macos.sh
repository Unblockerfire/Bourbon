#!/bin/bash
set -euo pipefail

PROJECT_FILE="${1:-Source/Whisky.xcodeproj/project.pbxproj}"
TARGETS="$(
  sed -nE 's/^[[:space:]]*MACOSX_DEPLOYMENT_TARGET = ([0-9.]+);/\1/p' "$PROJECT_FILE" \
    | sort -u
)"
TARGET_COUNT="$(printf '%s\n' "$TARGETS" | grep -c '[0-9]')"

if [ "$TARGET_COUNT" -ne 1 ]; then
  echo "Expected one canonical MACOSX_DEPLOYMENT_TARGET, found: ${TARGETS:-none}" >&2
  exit 1
fi

printf '%s\n' "$TARGETS"
