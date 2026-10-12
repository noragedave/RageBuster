#!/bin/python3
"""Merge the current branch into main through a GitHub pull request, then create a release.

Usage: pr.py TAG [--target main] [--title TITLE] [--notes NOTES] [--remote origin]

Needs the GitHub CLI (`gh`) installed and logged in (`gh auth login`) as an account
that can merge into the repo. If TAG already exists on GitHub (for example, pushed by
release.py), the release uses it. Otherwise GitHub creates TAG on the target branch
after the merge.
"""

import argparse
import subprocess
import sys

from release import git


def gh(*args, capture=False):
    """Run a gh command and stop on failure. Return its stdout if capture is set."""
    try:
        result = subprocess.run(["gh", *args], capture_output=capture, text=True)
    except FileNotFoundError:
        sys.exit("gh is not installed. See https://cli.github.com")
    if result.returncode != 0:
        detail = f":\n{result.stderr.strip()}" if capture else "."
        sys.exit(f"gh {' '.join(args)} failed{detail}")
    return (result.stdout or "").strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("tag", help="tag to release, e.g. v1.0.0")
    parser.add_argument("--target", default="main", help="branch to merge into (default: main)")
    parser.add_argument("--title", help="pull request title (default: 'Release TAG')")
    parser.add_argument("--notes", help="pull request body and release notes (default: 'Release TAG')")
    parser.add_argument("--remote", default="origin", help="remote the branch is pushed to (default: origin)")
    args = parser.parse_args()
    title = args.title or f"Release {args.tag}"
    notes = args.notes or f"Release {args.tag}"

    branch = git("symbolic-ref", "--short", "-q", "HEAD", check=False)
    if not branch:
        sys.exit("HEAD is detached. Check out the branch to merge first.")
    if branch == args.target:
        sys.exit(f"Already on {args.target}. Check out the working branch to merge.")
    if git("status", "--porcelain"):
        sys.exit("There are uncommitted changes. Commit them first, e.g. with release.py.")

    # The pull request is built from what's on GitHub, so push any local commits first.
    git("push", "--set-upstream", args.remote, branch)

    # Reuse an open pull request for this branch, or open one.
    number = gh("pr", "list", "--head", branch, "--base", args.target,
                "--json", "number", "--jq", ".[0].number", capture=True)
    if not number:
        gh("pr", "create", "--head", branch, "--base", args.target,
           "--title", title, "--body", notes)
        number = gh("pr", "view", branch, "--json", "number", "--jq", ".number", capture=True)

    # --merge keeps the branch's commits, so a tag already on one of them ends up on main.
    gh("pr", "merge", number, "--merge")
    print(f"Merged pull request #{number} ({branch}) into {args.target}.", flush=True)

    # --target is only used if the tag doesn't exist yet on GitHub.
    gh("release", "create", args.tag, "--target", args.target, "--title", args.tag, "--notes", notes)
    print(f"Created release {args.tag}.")


if __name__ == "__main__":
    main()
