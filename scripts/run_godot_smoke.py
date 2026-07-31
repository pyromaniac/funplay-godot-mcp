#!/usr/bin/env python3
"""Run local Godot smoke tests for Funplay MCP for Godot."""

from __future__ import annotations

import argparse
import os
import pathlib
import shutil
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
SMOKE_SCRIPTS = [
    ROOT / "scripts" / "godot_localization_smoke.gd",
    ROOT / "scripts" / "godot_play_mode_controller_smoke.gd",
    ROOT / "scripts" / "godot_runtime_bridge_smoke.gd",
    ROOT / "scripts" / "godot_gdscript_diagnostics_smoke.gd",
]


def existing_candidates(cli_path: str | None) -> list[pathlib.Path]:
    raw_candidates: list[str] = []
    if cli_path:
        raw_candidates.append(cli_path)
    if os.environ.get("GODOT_BIN"):
        raw_candidates.append(os.environ["GODOT_BIN"])
    raw_candidates.extend(
        [
            "/Applications/Godot.app/Contents/MacOS/Godot",
            "/Applications/Godot_mono.app/Contents/MacOS/Godot",
        ]
    )
    for executable in ("godot", "godot4", "Godot"):
        found = shutil.which(executable)
        if found:
            raw_candidates.append(found)

    seen: set[pathlib.Path] = set()
    candidates: list[pathlib.Path] = []
    for value in raw_candidates:
        path = pathlib.Path(value).expanduser()
        if path in seen:
            continue
        seen.add(path)
        if path.exists() and os.access(path, os.X_OK):
            candidates.append(path)
    return candidates


def cleanup_generated_files() -> None:
    shutil.rmtree(ROOT / ".godot", ignore_errors=True)
    for pattern in ("*.gd.uid", "*.import"):
        for path in ROOT.rglob(pattern):
            if ".git" not in path.parts:
                path.unlink(missing_ok=True)


def run_smoke(godot_bin: pathlib.Path) -> int:
    for smoke_script in SMOKE_SCRIPTS:
        command = [
            str(godot_bin),
            "--headless",
            "--path",
            str(ROOT),
            "--script",
            str(smoke_script),
        ]
        print("Running:", " ".join(command), flush=True)
        code = subprocess.run(command, cwd=ROOT, check=False).returncode
        if code != 0:
            return code
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Path to a Godot executable. GODOT_BIN is also supported.")
    parser.add_argument("--keep-generated", action="store_true", help="Keep .godot and generated uid/import files after the smoke test.")
    args = parser.parse_args()

    candidates = existing_candidates(args.godot)
    if not candidates:
        print("No Godot executable found. Pass --godot or set GODOT_BIN.", file=sys.stderr)
        return 2
    for smoke_script in SMOKE_SCRIPTS:
        if not smoke_script.exists():
            print(f"Missing smoke script: {smoke_script.relative_to(ROOT)}", file=sys.stderr)
            return 2

    try:
        for candidate in candidates:
            code = run_smoke(candidate)
            if code == 0:
                return 0
            print(f"Smoke failed with {candidate} (exit {code}).", file=sys.stderr)
        return 1
    finally:
        if not args.keep_generated:
            cleanup_generated_files()


if __name__ == "__main__":
    raise SystemExit(main())
