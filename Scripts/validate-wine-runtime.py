#!/usr/bin/env python3
"""Validate the macOS compatibility contract of a BourbonWine runtime."""

from __future__ import annotations

import argparse
import csv
import os
import re
import subprocess
import sys
from pathlib import Path


CRITICAL_PATHS = (
    "bin/wine",
    "bin/wineserver",
    "lib/wine/x86_64-unix/ntdll.so",
)
FORBIDDEN_UNDEFINED_SYMBOLS = ("_pipe2",)


def run(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(arguments, check=check, capture_output=True, text=True)


def version_tuple(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", value))


def is_macho(path: Path) -> bool:
    result = run("/usr/bin/file", "-b", str(path), check=False)
    return result.returncode == 0 and "Mach-O" in result.stdout


def build_versions(path: Path) -> list[tuple[str, str, str]]:
    result = run("/usr/bin/vtool", "-show-build", str(path), check=False)
    records: list[tuple[str, str, str]] = []
    platform = minos = sdk = None
    for line in result.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("platform "):
            platform = stripped.split(maxsplit=1)[1]
        elif stripped.startswith("minos "):
            minos = stripped.split(maxsplit=1)[1]
        elif stripped.startswith("sdk "):
            sdk = stripped.split(maxsplit=1)[1]
        if platform and minos and sdk:
            records.append((platform, minos, sdk))
            platform = minos = sdk = None
    if records:
        return records

    legacy = run("/usr/bin/otool", "-l", str(path), check=False)
    minimum = sdk = None
    in_legacy_command = False
    for line in legacy.stdout.splitlines():
        stripped = line.strip()
        if stripped == "cmd LC_VERSION_MIN_MACOSX":
            in_legacy_command = True
        elif in_legacy_command and stripped.startswith("version "):
            minimum = stripped.split(maxsplit=1)[1]
        elif in_legacy_command and stripped.startswith("sdk "):
            sdk = stripped.split(maxsplit=1)[1]
        if minimum and sdk:
            return [("MACOS", minimum, sdk)]
    return []


def architectures(path: Path) -> str:
    result = run("/usr/bin/lipo", "-archs", str(path), check=False)
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def linked_libraries(path: Path) -> list[str]:
    result = run("/usr/bin/otool", "-L", str(path), check=False)
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines()[1:] if line.strip()]


def undefined_symbols(path: Path) -> set[str]:
    result = run("/usr/bin/nm", "-u", str(path), check=False)
    symbols = set()
    for line in result.stdout.splitlines():
        candidate = line.strip().split()[-1] if line.strip() else ""
        if candidate:
            symbols.add(candidate)
    return symbols


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("runtime_root", type=Path)
    parser.add_argument("--maximum-minimum", required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--links-report", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    root = arguments.runtime_root.resolve()
    maximum = version_tuple(arguments.maximum_minimum)
    failures: list[str] = []

    for relative in CRITICAL_PATHS:
        path = root / relative
        if not path.is_file():
            failures.append(f"required runtime binary is missing: {relative}")
        elif not os.access(path, os.X_OK):
            failures.append(f"required runtime binary is not executable: {relative}")

    macho_files = sorted(path for path in root.rglob("*") if path.is_file() and is_macho(path))
    if not macho_files:
        failures.append("runtime contains no Mach-O binaries")

    arguments.report.parent.mkdir(parents=True, exist_ok=True)
    with arguments.report.open("w", newline="", encoding="utf-8") as report_file, \
            arguments.links_report.open("w", encoding="utf-8") as links_file:
        writer = csv.writer(report_file, delimiter="\t")
        writer.writerow(("path", "architectures", "platform", "minimum_macos", "sdk"))

        for path in macho_files:
            relative = path.relative_to(root).as_posix()
            versions = build_versions(path)
            if not versions:
                failures.append(f"Mach-O binary has no LC_BUILD_VERSION metadata: {relative}")
                writer.writerow((relative, architectures(path), "unknown", "unknown", "unknown"))
                continue

            for platform, minimum, sdk in versions:
                writer.writerow((relative, architectures(path), platform, minimum, sdk))
                if platform.upper() == "MACOS" and version_tuple(minimum) > maximum:
                    failures.append(
                        f"{relative} requires macOS {minimum}, newer than supported {arguments.maximum_minimum}"
                    )

            forbidden = undefined_symbols(path).intersection(FORBIDDEN_UNDEFINED_SYMBOLS)
            if forbidden:
                failures.append(f"{relative} references unsupported symbol(s): {', '.join(sorted(forbidden))}")

            if relative in CRITICAL_PATHS:
                links_file.write(f"## {relative}\n")
                for library in linked_libraries(path):
                    links_file.write(f"{library}\n")
                links_file.write("\n")

    for relative in CRITICAL_PATHS:
        path = root / relative
        if path.is_file() and is_macho(path):
            archs = architectures(path).split()
            if "x86_64" not in archs:
                failures.append(f"critical runtime binary is missing x86_64 architecture: {relative}")

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1

    print(
        f"Validated {len(macho_files)} Mach-O runtime files; "
        f"all minimum macOS targets are <= {arguments.maximum_minimum}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
