# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Build a test package of the RageBuster add-on, the same way a release does.

    uv run tools/package.py                    # build .release/RageBuster and a zip
    uv run tools/package.py --install          # ...and install it into WoW
    uv run tools/package.py --install --flavor _retail_

Where WoW is, and which flavors --install targets, come from
local-settings.json (see tools/settings.py); --wow-dir and --flavor override it.

It runs the same BigWigs packager the GitHub release workflow uses
(.github/workflows/build.yml), with the same .pkgmeta, so what you test is what
ships. Nothing is uploaded. The packager script is downloaded once, at a pinned
version, into .release/.packager/.

The build comes from the working tree, uncommitted changes included. Its
version is the latest tag, or the commit hash when there are no tags yet.

--install replaces the add-on's files in Interface/AddOns/RageBuster/ but keeps
the Verdicts.lua already there, because that file holds the real verdicts
tools/sync.py installed. A /reload picks up Lua changes; a .toc change needs
the game restarted.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

import settings

REPO = Path(__file__).resolve().parent.parent
RELEASE = REPO / ".release"
PACKAGER_VERSION = "v2.6.1"
# Pinned to the commit behind v2.6.1 (the same one build.yml uses) and checked
# against its SHA-256, because this script gets executed. Tags can be moved;
# commits and hashes can't. To upgrade, update all three together.
PACKAGER_COMMIT = "e50a250f8705041e40f2fa1ddcb280a686d65aa0"
PACKAGER_SHA256 = "59b15a8d851b09e6d0fdec702aec91331b9b49d84dbe778da6c621b48f268703"
PACKAGER_URL = f"https://raw.githubusercontent.com/BigWigsMods/packager/{PACKAGER_COMMIT}/release.sh"
PACKAGER = RELEASE / ".packager" / PACKAGER_VERSION / "release.sh"
ADDON = "RageBuster"
KEEP_ON_INSTALL = {"Verdicts.lua"}


def find_bash() -> str:
    """Git for Windows' bash. WSL's bash.exe in System32 can't see Windows paths the same way."""
    if os.name != "nt":
        return shutil.which("bash") or "bash"
    exec_path = subprocess.run(["git", "--exec-path"], capture_output=True, text=True, check=True).stdout.strip()
    git_root = Path(exec_path).parents[2]          # .../Git/mingw64/libexec/git-core -> .../Git
    for candidate in (git_root / "bin" / "bash.exe", git_root / "usr" / "bin" / "bash.exe"):
        if candidate.exists():
            return str(candidate)
    sys.exit("Couldn't find Git for Windows' bash.exe, which the packager needs.")


def get_packager() -> Path:
    if not PACKAGER.exists():
        print(f"Downloading BigWigs packager {PACKAGER_VERSION}...")
        PACKAGER.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(PACKAGER_URL) as r:
            PACKAGER.write_bytes(r.read())
    # checked on every run, so a cached copy that changed on disk is caught too
    digest = hashlib.sha256(PACKAGER.read_bytes()).hexdigest()
    if digest != PACKAGER_SHA256:
        PACKAGER.unlink()
        sys.exit(f"The packager script's checksum doesn't match ({digest}); it was deleted and not run.")
    return PACKAGER


def bash_path(p: Path) -> str:
    """C:\\Users\\x -> /c/Users/x, the form the packager needs under Git Bash."""
    if os.name != "nt":
        return str(p)
    drive, rest = p.resolve().drive, p.resolve().as_posix()[2:]
    return f"/{drive[0].lower()}{rest}"


def build() -> Path:
    out = RELEASE / ADDON
    shutil.rmtree(out, ignore_errors=True)
    # -d: don't upload anywhere   -z: we zip below (Git Bash has no zip)   -S: same as the workflow
    cmd = [find_bash(), bash_path(get_packager()), "-t", bash_path(REPO), "-r", bash_path(RELEASE),
           "-d", "-z", "-S"]
    result = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode != 0 or not (out / f"{ADDON}.toc").exists():
        print(result.stdout + result.stderr, file=sys.stderr)
        sys.exit("The packager failed; its output is above.")
    for line in result.stdout.splitlines():
        if line.lstrip().startswith(("Copying:", "Ignoring:")):
            print(line)
    return out


def version_of(package: Path) -> str:
    m = re.search(r"^## Version:\s*(\S+)", (package / f"{ADDON}.toc").read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else "unknown"


def make_zip(package: Path, version: str) -> Path:
    path = RELEASE / f"{ADDON}-{version}.zip"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(package.rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(RELEASE).as_posix())   # entries start with RageBuster/
    return path


def install(package: Path, wow_dir: Path, flavors: list[str]) -> None:
    roots = [wow_dir / f for f in flavors] if flavors else \
        sorted(p for p in wow_dir.iterdir() if (p / "Interface" / "AddOns").is_dir())
    if not roots:
        sys.exit(f"No game flavors with an Interface/AddOns folder under {wow_dir}.")
    for root in roots:
        target = root / "Interface" / "AddOns" / ADDON
        if not (root / "Interface" / "AddOns").is_dir():
            print(f"{root.name}: no Interface/AddOns folder, skipping.")
            continue
        target.mkdir(exist_ok=True)
        for old in target.iterdir():
            if old.name in KEEP_ON_INSTALL:
                continue
            shutil.rmtree(old) if old.is_dir() else old.unlink()
        for f in package.rglob("*"):
            dest = target / f.relative_to(package)
            if f.is_dir():
                dest.mkdir(exist_ok=True)
            elif not (f.name in KEEP_ON_INSTALL and dest.exists()):
                shutil.copy2(f, dest)
        print(f"{root.name}: installed into {target}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--install", action="store_true", help="copy the build into the WoW AddOns folder")
    parser.add_argument("--wow-dir", type=Path, default=settings.wow_dir(),
                        help="World of Warcraft folder (default: wowDir in local-settings.json)")
    parser.add_argument("--flavor", action="append", default=[],
                        help="install only into this flavor folder, e.g. _retail_ (repeatable; "
                             "default: installFlavors in local-settings.json, else every flavor)")
    args = parser.parse_args()

    package = build()
    version = version_of(package)
    zip_path = make_zip(package, version)
    print(f"\nBuilt {ADDON} {version}")
    print(f"  folder: {package}")
    print(f"  zip:    {zip_path}")

    if args.install:
        if not args.wow_dir.is_dir():
            sys.exit(f"WoW folder not found: {args.wow_dir}")
        install(package, args.wow_dir, args.flavor or settings.install_flavors())
        print("Type /reload in game for Lua changes; restart the game if the .toc changed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
