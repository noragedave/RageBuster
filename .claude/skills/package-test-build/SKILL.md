---
name: package-test-build
description: Builds a local test package of the RageBuster WoW add-on with the same BigWigs packager and .pkgmeta that releases use, then optionally installs it into the WoW AddOns folder so the user can try it in game. Nothing is uploaded or published. Use this whenever the user wants to test, try, package, zip, build, or install their current add-on changes, for example "package it so I can test", "make me a test zip", "put the latest build in WoW", or "does the package look right", even if they don't say "package". For publishing a real release, use publish-release instead.
---

# Build a RageBuster test package

`tools/package.py` runs BigWigs packager (pinned in the script) with the repo's `.pkgmeta` and the `-S` flag, the same way `.github/workflows/build.yml` does for a GitHub release. A local test build therefore contains exactly what a release would. The script doesn't upload anything. Git Bash has no `zip`, so the script zips the result in Python.

**Test builds and releases differ in one way: debug.** Code between `--@alpha@` and `--@end-alpha@` in the Lua files is active in untagged builds, which is every test build this skill makes. The packager comments it out when building a tagged release. `/rbust debug`, which prints the hidden messages, lives in those blocks, so it works in test builds and doesn't exist in published releases. Any new debug-only code belongs in such a block. If the user asks why debug is missing from a release, this is why.

The build comes from the **working tree**, so uncommitted edits are included. That's the point of a test build. The version is the latest git tag, or the short commit hash when there are no tags. The hash doesn't change for uncommitted edits, so mention it when the tree is dirty, so the user isn't misled by a version they've seen before.

## Pick the command

Run it from the repo root (the folder with `.pkgmeta`):

| The user wants | Command |
|---|---|
| A zip, or to see what would ship | `uv run tools/package.py` |
| To try it in game | `uv run tools/package.py --install` |
| A different game version this time | `uv run tools/package.py --install --flavor _retail_` (repeat `--flavor` for more) |
| A one-off WoW location | add `--wow-dir "<path>"` |

Where WoW lives, and which flavor folders `--install` targets, come from `local-settings.json` at the repo root. That file is gitignored and specific to this PC:

```json
{ "wowDir": "D:\\Games\\World of Warcraft", "installFlavors": ["_classic_beta_"] }
```

An empty `installFlavors` means every flavor folder with `Interface/AddOns`. Single backslashes in paths are fine. If the user says WoW or their test flavor has moved for good, edit this file rather than passing flags each time. Then say which folder you installed into, so a stale setting is easy to spot.

"So I can test it" or "put it in WoW" means install. "Make a zip" or "build a package" alone means build only. If it's unclear, build only and offer to install. Building is harmless, while installing replaces files in their game folder.

Installing replaces the add-on's files but deliberately keeps the existing `Verdicts.lua` in each install. That file holds the real verdicts the nightly `tools/sync.py` put there, and the repo's copy is only an empty placeholder. Leave that behavior alone. Overwriting the file would silently drop pending ignores.

## Before installing

- Run `git -C <repo> status --short`. If there are uncommitted changes, note which add-on files they touch, since those are what's being tested.
- If WoW is running (`tasklist /FI "IMAGENAME eq Wow*"`; each client has its own name, such as `Wow.exe`, `WowClassic.exe` or `WowB.exe` for the beta), installing still works. Tell the user what reloads what: `/reload` picks up Lua changes, while a change to `RageBuster.toc` (a new file, the Interface line, SavedVariables) needs a full game restart.

## Check the result

The script prints the packager's `Copying:` and `Ignoring:` lines. Read them before reporting, because this is the step that catches a bad `.pkgmeta`:

- **Should be copied:** `RageBuster.toc`, `BlockList.lua`, `Match.lua`, `RageBuster.lua`, `Verdicts.lua`, and the generated `CHANGELOG.md`.
- **Should be ignored:** `tools/`, `data/`, `POLICY.md`, `PLAN.md`, `CLAUDE.md`, `README.md`. Dotfiles such as `.claude/` and `.github/` are skipped automatically.

If anything from `data/` shows up as copied, stop and tell the user, because that folder holds other players' chat logs and must never be packaged. Likewise, if a file the `.toc` lists is missing from the package, the add-on will error on load. Point that out.

If the packager fails, show its output. On the first run, the script downloads the packager from GitHub, so a network error there is the usual cause. A missing Git for Windows `bash.exe` is the other common cause.

## Report back

Keep it short:

1. The version built, and whether the working tree had uncommitted changes (list the add-on files they touch).
2. The zip path (`.release/RageBuster-<version>.zip`) and the unpacked folder (`.release/RageBuster/`).
3. Where it was installed, if it was, and that each install kept its own `Verdicts.lua`.
4. What to do in game: `/reload` for Lua changes, or a restart for `.toc` changes. Then, to confirm it loaded, `/rbust status`.

`.release/` is gitignored, so test builds never get committed.
