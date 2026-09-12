"""Exports the shareable source tree as `CubyzReforged-source.zip` at the repository root.

    python scripts/export_source.py [--no-verify] [--zig PATH]

What ships is the game plus the shaderpack bridge and nothing that only this working copy
needs: no logs, saves, caches, screenshots, recovery material, session notes, third-party zips
or personal settings. The per-frame diagnostics live between `// [diag]` and `// [/diag]` fence
lines in the Zig sources; the export cuts those regions out and drops
`mods/irisbridge/lib/diagnostics.zig` with them, so the shared tree has no instrumentation to
find, switch off or delete. The bridge's design notes move to `docs/irisbridge-notes.md`, the
upstream Cubyz README to `docs/cubyz-README.md`, and `scripts/export/README.md` becomes the
root README.

Unless `--no-verify` is passed, the staged tree is built (`zig build -Doptimize=ReleaseFast`)
and its tests run (`zig build test`) before it is zipped: a source archive that does not build
from a clean extract is worse than none. `--zig` names the compiler; the default is the one
`run_windows.bat` installs into `compiler/`, then `zig` on the PATH.

Discord accepts files up to 10 MB without a subscription; the script says how close it is.
"""

import argparse
import fnmatch
import os
import re
import shutil
import subprocess
import sys
import zipfile

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOP = "CubyzReforged"
STAGE_PARENT = os.path.join(ROOT, "zig-out", "export")
STAGE = os.path.join(STAGE_PARENT, TOP)
OUT = os.path.join(ROOT, TOP + "-source.zip")
DISCORD_LIMIT = 10 * 1000 * 1000

# Directories that never ship, wherever they sit in the tree.
DROP_DIRS = {
    ".zig-cache", "zig-out", "zig-pkg", "zig-cache", ".git", ".github", "compiler", "logs", "saves",
    "backgrounds", "_recovery_junk", "_truncated", "irisbridge_dump", "serverAssets", "_disabled",
    "photos", "snapshots",
}
# Files that never ship, by path relative to the root.
DROP_FILES = {
    "CLAUDE.md", "RECOVERY.md", "launchConfig.zon", "gui_layout.zig.zon", "settings.zig.zon",
    "debug_settings.zig.zon", "gamecontrollerdb.txt", "gamecontrollerdb.stamp",
    "mods/irisbridge/HANDOFF.md", "mods/irisbridge/lib/diagnostics.zig",
    "mods/renderhook.zig", "mods/rotations.zig", "mods/mapgen.zig", "mods/climategen.zig",
    "mods/structuremapgen.zig",
}
# Patterns that never ship: third-party zips, build-fetched assets, the assets of the disabled
# mods, a user's own option overrides and extracted packs.
DROP_GLOBS = [
    "*.zip", "*.exe", "*.tmp", "*.bak", "*.png.import", "test.png", "capture.png",
    "shaderpacks/*", "assets/cubyz/music/*", "assets/cubyz/fonts/*",
    "assets/lostcities/*", "assets/terraindiffusion/*",
]
# Files that ship somewhere else.
RELOCATE = {
    "mods/irisbridge/README.md": "docs/irisbridge-notes.md",
    "README.md": "docs/cubyz-README.md",
}
# Templates written over the staged tree.
TEMPLATES = {
    "scripts/export/README.md": "README.md",
    "scripts/export/shaderpacks-README.md": "shaderpacks/README.md",
}
TEMPLATE_DESTINATIONS = set(TEMPLATES.values())

# What a build or run writes into the tree it runs in; never part of the source.
BUILD_RESIDUE = {"launchConfig.zon", "gamecontrollerdb.txt", "gamecontrollerdb.stamp", "settings.zig.zon", "gui_layout.zig.zon"}

FENCE_OPEN = "// [diag]"
FENCE_CLOSE = "// [/diag]"
# Nothing the fences remove may survive outside a comment in the staged sources.
LEFTOVERS = re.compile(
    r"\bdiag\.|diagnostics\.zig|shaderDebugBuffer|shaderDiagnostics|DepthView|thumbnail|"
    r"readShadowMap|captureThumbnail|sampleCenter\(|\[/?diag\]"
)


def dropped(rel):
    r = rel.replace("\\", "/")
    if r in DROP_FILES:
        return True
    if any(part in DROP_DIRS for part in r.split("/")):
        return True
    return any(fnmatch.fnmatch(r, g) for g in DROP_GLOBS)


def strip_fences(data, rel):
    """Removes every fenced region from a Zig source, keeping the file's own line endings."""
    newline = b"\r\n" if b"\r\n" in data else b"\n"
    kept = []
    depth = 0
    for number, line in enumerate(data.split(newline), 1):
        text = line.strip()
        if text == FENCE_OPEN.encode():
            if depth:
                raise SystemExit(f"{rel}:{number}: nested {FENCE_OPEN}")
            depth = 1
            continue
        if text == FENCE_CLOSE.encode():
            if not depth:
                raise SystemExit(f"{rel}:{number}: {FENCE_CLOSE} without {FENCE_OPEN}")
            depth = 0
            continue
        if not depth:
            kept.append(line)
    if depth:
        raise SystemExit(f"{rel}: {FENCE_OPEN} never closed")
    return newline.join(kept)


def check_leftovers(data, rel):
    """Fails if anything the fences should have removed is still referenced in code."""
    for number, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1):
        code = line.split("//", 1)[0]
        if LEFTOVERS.search(code):
            raise SystemExit(f"{rel}:{number}: diagnostic reference survives the export: {line.strip()}")


def stage():
    if os.path.isdir(STAGE):
        shutil.rmtree(STAGE)
    os.makedirs(STAGE)
    count = 0
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in DROP_DIRS]
        for name in files:
            full = os.path.join(base, name)
            rel = os.path.relpath(full, ROOT).replace("\\", "/")
            if dropped(rel):
                continue
            with open(full, "rb") as f:
                data = f.read()
            if rel.endswith(".zig"):
                data = strip_fences(data, rel)
                check_leftovers(data, rel)
            target = os.path.join(STAGE, RELOCATE.get(rel, rel))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "wb") as f:
                f.write(data)
            count += 1
    for source, destination in TEMPLATES.items():
        target = os.path.join(STAGE, destination)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(os.path.join(ROOT, source), target)
        count += 1
    return count


def find_zig(explicit):
    if explicit:
        return explicit
    bundled = os.path.join(ROOT, "compiler", "zig", "zig.exe" if os.name == "nt" else "zig")
    if os.path.isfile(bundled):
        return bundled
    return shutil.which("zig") or "zig"


def verify(zig):
    for args in (["build", "-Doptimize=ReleaseFast"], ["build", "test"]):
        print(f"  {os.path.basename(zig)} {' '.join(args)} ...", flush=True)
        result = subprocess.run([zig] + args, cwd=STAGE, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if result.returncode != 0:
            print(result.stdout[-4000:])
            print(result.stderr[-4000:])
            raise SystemExit(f"verification failed: zig {' '.join(args)} exited with {result.returncode}")
    print("  builds and passes its tests from the staged tree")


def zip_stage():
    count = 0
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for base, dirs, files in os.walk(STAGE):
            dirs[:] = [d for d in dirs if d not in DROP_DIRS]
            for name in files:
                full = os.path.join(base, name)
                rel = os.path.relpath(full, STAGE).replace("\\", "/")
                # The verification build leaves its own files behind - the music and fonts it
                # fetches, `launchConfig.zon`, the controller database - and those are the working
                # copy's, not the source's. The templates written into dropped locations stay.
                if rel not in TEMPLATE_DESTINATIONS and (dropped(rel) or rel in BUILD_RESIDUE):
                    continue
                # Written with explicit Unix modes rather than `z.write`, which on Windows stores no
                # mode at all: extracted on Linux, `run_linux.sh` and the scripts it calls then
                # arrive without the executable bit and fail until someone runs `chmod +x`.
                info = zipfile.ZipInfo.from_file(full, os.path.join(TOP, rel))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 3  # Unix, so extractors honour the mode below
                mode = 0o755 if rel.endswith(".sh") else 0o644
                info.external_attr = (0o100000 | mode) << 16
                with open(full, "rb") as f:
                    z.writestr(info, f.read(), compresslevel=9)
                count += 1
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--no-verify", action="store_true", help="skip building and testing the staged tree")
    parser.add_argument("--zig", help="path to the Zig 0.16.0 compiler used for verification")
    options = parser.parse_args()

    staged = stage()
    print(f"staged {staged} files in {STAGE}")
    if not options.no_verify:
        verify(find_zig(options.zig))
    zipped = zip_stage()
    size = os.path.getsize(OUT)
    print(f"{os.path.basename(OUT)}: {zipped} files, {size / 1048576:.2f} MB")
    if size > DISCORD_LIMIT:
        print(f"WARNING: over Discord's {DISCORD_LIMIT // 1000000} MB limit for uploads without a subscription")
    else:
        print(f"fits Discord's {DISCORD_LIMIT // 1000000} MB upload limit with {(DISCORD_LIMIT - size) / 1048576:.2f} MB to spare")


if __name__ == "__main__":
    main()
