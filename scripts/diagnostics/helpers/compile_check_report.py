#!/usr/bin/env python3
"""Summarise a ReShade.log: which effects compiled, which failed and which never reported.

usage: compile_check_report.py LOG SHADERS_DIR [--known-broken PATH,PATH,...]

LOG is the ReShade.log written next to the test program, SHADERS_DIR the merged Shaders
folder that was given to ReShade. Effects are compared by their path inside that folder.
Effects named in --known-broken are expected to fail: their failure does not count, and a
known-broken effect that compiles is reported so it can be removed from the list.

Exit status: 0 everything compiled, 1 an effect failed or was never reported, 2 ReShade
never started (no runtime was created), so the log says nothing about the effects.
"""
import os
import re
import sys

STAMP = r"\d\d:\d\d:\d\d:\d+"
OK = re.compile(r"(WARN|INFO)\s+\| Successfully compiled '[^']*?Merged\\Shaders\\([^']+)'")
FAIL = re.compile(
    r"ERROR\s+\| Failed to compile '[^']*?Merged\\Shaders\\([^']+)':\n(.*?)(?=\n" + STAMP + r"|\Z)",
    re.S,
)


def effects_on_disk(shaders_dir):
    found = set()
    for root, _dirs, files in os.walk(shaders_dir, followlinks=True):
        for name in files:
            if name.endswith(".fx"):
                found.add(os.path.relpath(os.path.join(root, name), shaders_dir).replace(os.sep, "/"))
    return found


def first_error(message):
    """The first line that names an error, without the machine-specific path or address prefix."""
    lines = [line.strip() for line in message.splitlines() if line.strip()]
    chosen = next((line for line in lines if "error" in line.lower()), lines[0] if lines else "")
    chosen = re.sub(r"^\S*?Merged\\Shaders\\", "", chosen)
    return re.sub(r"^\S*?Shader@0x[0-9A-Fa-f]+", "Shader", chosen)[:220]


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    log_path, shaders_dir = argv[1], argv[2]
    known_broken = set()
    if "--known-broken" in argv:
        raw = argv[argv.index("--known-broken") + 1]
        known_broken = {item.strip() for item in raw.split(",") if item.strip()}

    log = open(log_path, errors="ignore").read().replace("\r\n", "\n")
    if "Recreated runtime environment" not in log:
        print("ReShade never created a runtime, so no effect was compiled.")
        print("COMPILE_CHECK_RESULT=NO_RUNTIME")
        return 2

    compiled, warned, failed = set(), set(), {}
    for level, path in OK.findall(log):
        path = path.replace("\\", "/")
        compiled.add(path)
        if level == "WARN":
            warned.add(path)
    for path, message in FAIL.findall(log):
        failed[path.replace("\\", "/")] = first_error(message)

    on_disk = effects_on_disk(shaders_dir)
    missing = sorted(on_disk - compiled - set(failed))
    unexpected = {p: m for p, m in failed.items() if p not in known_broken}

    print(
        f"Effects: {len(on_disk)}  compiled: {len(compiled)} ({len(warned)} with warnings)  "
        f"failed: {len(failed)}  not reported: {len(missing)}"
    )
    for path, message in sorted(failed.items()):
        label = "EXPECTED FAIL" if path in known_broken else "FAIL"
        print(f"{label:<13} {path} | {message}")
    for path in missing:
        print(f"NOT REPORTED  {path}")
    for path in sorted(known_broken & compiled):
        print(f"NOW COMPILES  {path} | can be removed from SHADER_BROKEN_EFFECTS")

    ok = not unexpected and not missing
    print(f"COMPILE_CHECK_RESULT={'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
