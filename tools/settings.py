"""Per-PC settings, read from local-settings.json at the repo root (gitignored).

    {
      "wowDir": "D:\\\\Games\\\\World of Warcraft",
      "installFlavors": ["_classic_beta_"]
    }

wowDir          the World of Warcraft folder (the one holding _retail_, _classic_, ...).
installFlavors  which flavor folders tools/package.py --install targets; empty means all.

Scripts read this every time they run, so moving WoW only means editing the file.
A --wow-dir or --flavor flag on the command line still wins.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SETTINGS_FILE = REPO / "local-settings.json"
DEFAULT_WOW_DIR = Path(r"C:\Program Files (x86)\World of Warcraft")


def load() -> dict:
    if not SETTINGS_FILE.exists():
        return {}
    text = SETTINGS_FILE.read_text(encoding="utf-8")
    # Accept Windows paths typed with single backslashes ("D:\Games\new folder").
    # The file only holds paths, so a lone backslash is always literal: double it
    # unless it is already doubled or escapes a quote. (Without this, "\n" in
    # "D:\new" would become a newline.)
    text = re.sub(r'(?<!\\)\\(?![\\"])', r"\\\\", text)
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise SystemExit(f"{SETTINGS_FILE} isn't valid JSON ({e}). Fix it or delete it to use the defaults.")


def wow_dir() -> Path:
    return Path(load().get("wowDir") or DEFAULT_WOW_DIR)


def install_flavors() -> list[str]:
    return list(load().get("installFlavors") or [])
