#!/usr/bin/env python3
"""Runs every *Check.swift: the compile-and-run command is in its header comment.

    python3 scripts/run-checks.py            # all
    python3 scripts/run-checks.py Favicon    # only files whose name contains the word

Checks that need a window server are skipped when SKIP_GUI_CHECKS is set (CI sets it).
"""
import glob, os, re, subprocess, sys, tempfile

GUI = {"BrowserColdLaunchCheck", "BrowserWindowOpeningCheck", "WindowFrameInteractionCheck",
       "EscapeKeyCheck", "SpaceSwitchCheck", "LibrarySwipeDecisionCheck"}

def command(path):
    lines = []
    for raw in open(path, encoding="utf-8"):
        if not raw.startswith("//"):
            break
        lines.append(raw[2:].strip())
    for i, line in enumerate(lines):
        if line.startswith("swiftc "):
            parts = [line]
            while parts[-1].endswith("\\") and i + len(parts) < len(lines):
                parts.append(lines[i + len(parts)])
            return " ".join(p.rstrip("\\").strip() for p in parts)
    return None

def main():
    word = sys.argv[1] if len(sys.argv) > 1 else ""
    files = sorted(glob.glob("Packages/*/Checks/*Check.swift") + glob.glob("scripts/tests/*Check.swift"))
    failed, ran = [], 0
    for path in files:
        name = os.path.basename(path)[:-6]
        if word not in name:
            continue
        if os.environ.get("SKIP_GUI_CHECKS") and name in GUI:
            print(f"skip  {name} (needs a window server)")
            continue
        cmd = command(path)
        if not cmd:
            print(f"skip  {name} (no swiftc line in its header)")
            continue
        if "[" in cmd.split("&&")[-1]:
            print(f"skip  {name} (needs an input file: {cmd.split('&&')[-1].strip()})")
            continue
        # Some commands are written from the package folder, some from the repo root.
        first = next((w for w in cmd.split() if w.endswith(".swift")), "")
        cwd = os.getcwd() if os.path.exists(first) else os.path.dirname(os.path.dirname(path))
        out = tempfile.mktemp(prefix="check-")
        cmd = re.sub(r"-o\s+\S+", f"-o {out}", cmd)
        cmd = re.sub(r"&&\s*/tmp/\S+", f"&& {out}", cmd)
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd)
        ran += 1
        if result.returncode != 0:
            failed.append(name)
            print(f"FAIL  {name}\n{(result.stdout + result.stderr).strip()[-600:]}")
        else:
            print(f"ok    {name}")
    print(f"\n{ran - len(failed)}/{ran} checks passed")
    sys.exit(1 if failed else 0)

main()
