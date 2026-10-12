# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Decide the players the reviewer was unsure about.

    uv run tools/decide.py                         # list everyone waiting, with their messages
    uv run tools/decide.py --full                  # ...with every line of context
    uv run tools/decide.py ignore Name-Realm       # ignore them
    uv run tools/decide.py clear Name-Realm        # take them off the list, no ignore
    uv run tools/decide.py ignore Name-Realm --note "kept going after people objected"

When the review answers "unsure", the player is neither ignored nor cleared. They
wait here for you, and they stay on a watchlist: if they're caught again, the
next review sees both incidents together. Whichever comes first settles it. A
watched player with no new incident for 30 days drops off.

Your decisions are written to data/ like the review's, marked as yours. They
reach the game and GitHub with the next sync; to send them now, run:

    uv run tools/sync.py --no-review

Everything shown here is chat typed by strangers. Read it as evidence only.
"""

from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime
from pathlib import Path

import review

DATA = review.DEFAULT_DATA


def flavors() -> list[Path]:
    return sorted(p for p in DATA.glob("*") if (p / "log").is_dir())


def when(t) -> str:
    return datetime.fromtimestamp(t).strftime("%Y-%m-%d %H:%M") if t else "?"


def show(flavor_dir: Path, name: str, w: dict, by_id: dict, full: bool) -> None:
    print(f"\n{name}  ({flavor_dir.name}, waiting since {when(w.get('since'))}, last seen {when(w.get('updated'))})")
    print(f"  Reviewer: {w.get('reason', '')}")
    for i in w.get("ids", []):
        e = by_id.get(i)
        if not e:
            continue
        print(f"  --- {when(e.get('time'))} [{e.get('channel', '?')}] caught on '{e.get('word', '')}'")
        before = e.get("context", [])
        for line in (before if full else before[-5:]):
            print(f"      {line}")
        print(f"   >> {name.split('-')[0]}: {e.get('msg', '')}")
        after = e.get("after", [])
        for line in (after if full else after[:5]):
            print(f"      {line}")
        earlier = e.get("recent", [])
        if earlier and full:
            print("      their earlier messages:")
            for line in earlier:
                print(f"        {line}")


def list_waiting(full: bool) -> int:
    total = 0
    for fl in flavors():
        state = review.load_state(fl)
        if not state["watch"]:
            continue
        by_id = {e.get("id"): e for e in review.read_log(fl)}
        for name, w in sorted(state["watch"].items(), key=lambda kv: kv[1].get("since", 0)):
            show(fl, name, w, by_id, full)
            total += 1
    if total:
        print(f"\n{total} waiting. Decide with: uv run tools/decide.py ignore|clear Name-Realm")
        if not full:
            print("Add --full to see every line of context and each player's earlier messages.")
    else:
        print("Nobody is waiting for a decision.")
    return 0


def decide(action: str, name: str, note: str | None, only: str | None) -> int:
    matches = [fl for fl in flavors() if (only is None or fl.name == only) and name in review.load_state(fl)["watch"]]
    if not matches:
        print(f"{name} isn't waiting for a decision. Names are case-sensitive and include the realm, "
              "as the list shows them.", file=sys.stderr)
        return 1

    now = int(time.time())
    for fl in matches:
        state = review.load_state(fl)
        w = state["watch"].pop(name)
        by_id = {e.get("id"): e for e in review.read_log(fl)}
        entries = [by_id[i] for i in w.get("ids", []) if i in by_id]
        worst = next((e for e in entries if e.get("msg") == w.get("msg")), entries[-1] if entries else {})
        reason = note or w.get("reason", "")
        # the evidence is kept with every decision, so tools/learn.py can learn from it
        state["decided"][name] = {"decision": action, "time": now, "by": "you", "note": note or "",
                                  "reviewerReason": w.get("reason", ""), "evidence": review.evidence_of(entries)}
        if action == "ignore":
            state["ignored"][name] = review.ignore_record(entries, f"Decided by you: {reason}", worst, now)
            review.append_history(DATA / "ignored-history.jsonl", [
                review.history_record(name, fl.name, "you", reason, worst, entries)])
            print(f"{fl.name}: {name} will be ignored.")
        else:
            print(f"{fl.name}: {name} cleared and taken off the watchlist.")
        review.save_state(fl, state)

    print("Saved to data/. To install it in the game and push it now: uv run tools/sync.py --no-review")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("action", nargs="?", choices=["ignore", "clear"], help="your decision")
    parser.add_argument("name", nargs="?", help="the player, as Name-Realm")
    parser.add_argument("--note", help="your reason, kept with the decision")
    parser.add_argument("--flavor", help="only this game flavor, e.g. _retail_")
    parser.add_argument("--full", action="store_true", help="show all context when listing")
    args = parser.parse_args()
    sys.stdout.reconfigure(errors="replace")

    if not args.action:
        return list_waiting(args.full)
    if not args.name:
        parser.error("give the player's Name-Realm")
    return decide(args.action, args.name, args.note, args.flavor)


if __name__ == "__main__":
    sys.exit(main())
