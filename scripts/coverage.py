#!/usr/bin/env python3
"""Print PostgresConnectionPool line coverage using llvm-cov.

Run ``swift test --enable-code-coverage`` first. The optional ``--minimum``
turns the summary into a CI gate. SwiftPM versions that only emit ``.profraw``
files are supported by merging them with ``llvm-profdata``.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_MARKER = "/Sources/PostgresConnectionPool/"


def bin_path() -> Path:
    return Path(
        subprocess.check_output(
            ["swift", "build", "--show-bin-path"],
            cwd=ROOT,
            text=True,
        ).strip()
    )


def test_binary(bin_dir: Path) -> Path:
    candidates = [
        bin_dir / "PostgresConnectionPoolTests.so",
        bin_dir / "PostgresConnectionPoolTests",
    ]
    candidates.extend(bin_dir.glob("*.xctest"))
    candidates.extend(bin_dir.glob("*.xctest/Contents/MacOS/*"))

    for candidate in candidates:
        if candidate.is_file():
            return candidate

    for xctest in bin_dir.rglob("*.xctest"):
        if xctest.is_file():
            return xctest
        for candidate in xctest.glob("Contents/MacOS/*"):
            if candidate.is_file():
                return candidate

    for candidate in bin_dir.rglob("*"):
        if (
            candidate.is_file()
            and "PostgresConnectionPoolTests" in candidate.name
            and candidate.stat().st_mode & 0o111
        ):
            return candidate

    raise SystemExit(f"Test binary not found in {bin_dir}")


def profdata_path(bin_dir: Path) -> Path:
    codecov = bin_dir / "codecov"
    profdata = codecov / "default.profdata"
    if profdata.exists():
        return profdata

    profraw = sorted(codecov.glob("*.profraw"))
    if profraw:
        merged = codecov / "default.profdata"
        subprocess.check_call(
            [
                "llvm-profdata",
                "merge",
                "-sparse",
                *(str(path) for path in profraw),
                "-o",
                str(merged),
            ],
            cwd=ROOT,
        )
        return merged

    candidates = sorted(bin_dir.rglob("*.profdata"))
    if candidates:
        return candidates[0]

    raise SystemExit(f"Coverage profile not found in {bin_dir}")


def export_coverage(binary: Path, profdata: Path) -> dict:
    output = subprocess.check_output(
        [
            "llvm-cov",
            "export",
            str(binary),
            f"-instr-profile={profdata}",
            "--summary-only",
            "-ignore-filename-regex=(Tests/|/\\.build/|/Dependencies/)",
        ],
        cwd=ROOT,
        text=True,
    )
    return json.loads(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--minimum",
        type=float,
        default=None,
        help="Fail when total line coverage is below this percentage",
    )
    args = parser.parse_args()

    bin_dir = bin_path()
    report = export_coverage(test_binary(bin_dir), profdata_path(bin_dir))
    data = report.get("data", [])
    files = [
        file
        for file in (data[0].get("files", []) if data else [])
        if SOURCE_MARKER in file["filename"]
    ]

    if not files:
        raise SystemExit("No PostgresConnectionPool source files in the coverage data")

    rows = []
    total_lines = 0
    covered_lines = 0
    total_functions = 0
    covered_functions = 0
    total_regions = 0
    covered_regions = 0

    for file in files:
        summary = file["summary"]
        lines = summary.get("lines", {"count": 0, "covered": 0})
        functions = summary.get("functions", {"count": 0, "covered": 0})
        regions = summary.get("regions", {"count": 0, "covered": 0})

        total_lines += int(lines["count"])
        covered_lines += int(lines["covered"])
        total_functions += int(functions["count"])
        covered_functions += int(functions["covered"])
        total_regions += int(regions["count"])
        covered_regions += int(regions["covered"])

        relative = file["filename"].split(SOURCE_MARKER, 1)[1]
        percent = (
            100.0 * int(lines["covered"]) / int(lines["count"])
            if int(lines["count"])
            else 0.0
        )
        rows.append((relative, int(lines["count"]), int(lines["covered"]), percent))

    rows.sort()
    print(f"{'File':55} {'Lines':>7} {'Covered':>8} {'Cover':>8}")
    print("-" * 82)
    for relative, count, covered, percent in rows:
        print(f"{relative:55} {count:7d} {covered:8d} {percent:7.2f}%")
    print("-" * 82)

    line_coverage = 100.0 * covered_lines / total_lines if total_lines else 0.0
    function_coverage = (
        100.0 * covered_functions / total_functions if total_functions else 0.0
    )
    region_coverage = (
        100.0 * covered_regions / total_regions if total_regions else 0.0
    )

    print(f"{'Total':55} {total_lines:7d} {covered_lines:8d} {line_coverage:7.2f}%")
    print(
        f"Functions: {function_coverage:.2f}% "
        f"({covered_functions}/{total_functions}), "
        f"regions: {region_coverage:.2f}% "
        f"({covered_regions}/{total_regions})"
    )

    if args.minimum is not None and line_coverage < args.minimum:
        print(
            f"Line coverage {line_coverage:.2f}% is below the "
            f"{args.minimum:.2f}% minimum",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
