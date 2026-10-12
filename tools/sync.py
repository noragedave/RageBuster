# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Collect RageBuster's chat log, review it, and save everything to GitHub.

Runs nightly on the gaming PC (tools/schedule-sync.ps1 sets that up), or by
hand from the repo:

    uv run tools/sync.py
    uv run tools/sync.py --dry-run        # show what would change, touch nothing

It pulls the repo, then for every game flavor under the WoW folder
(_retail_, _classic_, ...):

1. reads WTF/Account/*/SavedVariables/RageBuster.lua and appends log entries
   the repo doesn't have yet to data/<flavor>/log/<date>.jsonl;
2. writes data/<flavor>/game.json: who the add-on already ignores, who was
   unignored by hand, and which entries are still in the in-game log;
3. runs tools/review.py, which asks Claude about the new entries through the
   Claude Code CLI and writes data/<flavor>/Verdicts.lua;
4. copies that Verdicts.lua into Interface/AddOns/RageBuster/ so the add-on
   imports it at the next login.

Then it commits data/ and pushes, so GitHub holds the logs, the verdicts and
the ignore history.

WoW writes SavedVariables only on logout or /reload, so anything logged in a
session that is still running is picked up the next night.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

import review
import settings
from wowlua import as_dict, as_list, read_lua_file

REPO = Path(__file__).resolve().parent.parent
BRANCH = "main"
# "by" (which of your characters saw the message) stays in the game; it would
# put your own character names into the repo.
LOG_FIELDS = ("id", "time", "author", "guid", "channel", "word", "msg", "context")


def git(*args: str, capture: bool = False) -> str:
    result = subprocess.run(["git", "-C", str(REPO), *args], check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return (result.stdout or "").strip()


def read_json(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def known_ids(log_dir: Path) -> set[str]:
    ids = set()
    for f in log_dir.glob("*.jsonl"):
        ids |= {json.loads(line)["id"] for line in f.read_text(encoding="utf-8").splitlines() if line.strip()}
    return ids


def clean_entry(e: dict) -> dict:
    out = {k: e[k] for k in LOG_FIELDS if e.get(k) is not None}
    out["context"] = [str(line) for line in as_list(e.get("context"))]
    return out


def addon_dir(root: Path) -> Path:
    return root / "Interface" / "AddOns" / "RageBuster"


def collect(root: Path, sv_files: list[Path], today: str, dry_run: bool) -> None:
    """Adds the game's new log entries and its ignore state to data/<flavor>/."""
    out = REPO / "data" / root.name
    log, ignored, pardoned = [], set(), {}
    for sv in sv_files:
        db = as_dict(read_lua_file(sv).get("RageBusterDB"))
        log += [clean_entry(e) for e in as_list(db.get("log")) if isinstance(e, dict) and e.get("id")]
        ignored |= set(as_dict(db.get("ignored")))
        for name, t in as_dict(db.get("pardoned")).items():
            pardoned[name] = max(t, pardoned.get(name, 0))

    seen = known_ids(out / "log")
    new = [e for e in log if e["id"] not in seen]
    print(f"{root.name}: {len(log)} entries in the game's log, {len(new)} new.")

    game = {
        "ignored": sorted(ignored),
        "pardoned": dict(sorted(pardoned.items())),
        "logIds": sorted(e["id"] for e in log),
    }
    if dry_run:
        return
    (out / "log").mkdir(parents=True, exist_ok=True)
    if new:
        with (out / "log" / f"{today}.jsonl").open("a", encoding="utf-8", newline="\n") as f:
            for e in sorted(new, key=lambda e: (e.get("time", 0), e["id"])):
                f.write(json.dumps(e, ensure_ascii=False) + "\n")
    if read_json(out / "game.json", None) != game:
        (out / "game.json").write_text(json.dumps(game, ensure_ascii=False, indent=1) + "\n",
                                       encoding="utf-8", newline="\n")


def safe_verdicts(path: Path) -> bool:
    """WoW runs Verdicts.lua as code, and this copy may have come from GitHub.
    Only accept a file that is nothing but `RageBuster_Imported = <literal table>`;
    the parser rejects function calls or any other code."""
    try:
        values = read_lua_file(path)
    except (ValueError, IndexError):
        return False
    return set(values) == {"RageBuster_Imported"} and isinstance(values["RageBuster_Imported"], dict)


def install_verdicts(root: Path, dry_run: bool) -> None:
    verdicts = REPO / "data" / root.name / "Verdicts.lua"
    installed = addon_dir(root) / "Verdicts.lua"
    if verdicts.exists() and not safe_verdicts(verdicts):
        print(f"{root.name}: {verdicts} isn't a plain verdict table, so it was NOT installed. "
              "Check its git history.", file=sys.stderr)
        return
    if verdicts.exists() and (not installed.exists() or installed.read_bytes() != verdicts.read_bytes()):
        print(f"{root.name}: copying new verdicts into the add-on.")
        if not dry_run:
            shutil.copyfile(verdicts, installed)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--wow-dir", type=Path, default=settings.wow_dir(),
                        help="World of Warcraft folder (default: wowDir in local-settings.json)")
    parser.add_argument("--model", default=review.DEFAULT_MODEL, help=f"Claude model (default {review.DEFAULT_MODEL})")
    parser.add_argument("--dry-run", action="store_true", help="show what would change without writing or pushing")
    parser.add_argument("--no-review", action="store_true", help="collect the log without asking Claude about it")
    parser.add_argument("--no-git", action="store_true", help="update data/ and the add-on, but don't pull, commit or push")
    args = parser.parse_args()
    sys.stdout.reconfigure(errors="replace")

    if not args.wow_dir.is_dir():
        print(f"WoW folder not found: {args.wow_dir}", file=sys.stderr)
        return 1

    use_git = not (args.dry_run or args.no_git)
    if use_git:
        branch = git("rev-parse", "--abbrev-ref", "HEAD", capture=True)
        if branch != BRANCH:
            print(f"The repo is on branch '{branch}'. Switch to '{BRANCH}' before syncing.", file=sys.stderr)
            return 1
        git("pull", "--rebase", "--autostash", "--quiet")

    today = date.today().isoformat()
    roots = []
    for root in sorted(p for p in args.wow_dir.iterdir() if p.is_dir()):
        sv_files = sorted(root.glob("WTF/Account/*/SavedVariables/RageBuster.lua"))
        if not sv_files:
            continue
        if not addon_dir(root).is_dir():
            print(f"{root.name}: has RageBuster logs but the add-on isn't installed, skipping.")
            continue
        roots.append(root)
        collect(root, sv_files, today, args.dry_run)
    if not roots:
        print("No RageBuster logs found. Play with the add-on enabled, then log out or /reload.")
        return 0

    # A dry run writes nothing to data/, so there is nothing new to review.
    failed = 0
    if not (args.dry_run or args.no_review):
        failed = review.review_all(REPO / "data", args.model)
    for root in roots:
        install_verdicts(root, args.dry_run)

    # players that failed stay unreviewed and are retried on the next run
    code = 1 if failed else 0
    if not use_git:
        return code
    git("add", "--", "data")
    if not git("diff", "--cached", "--name-only", "--", "data", capture=True):
        print("Nothing new to save.")
        return code
    git("commit", "--quiet", "-m", f"Chat log and review {today}", "--", "data")
    git("push", "--quiet")
    print("Pushed to GitHub.")
    return code


if __name__ == "__main__":
    sys.exit(main())
