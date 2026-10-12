#!/bin/python3
"""Commit any uncommitted changes, tag the commit, and push the branch and tag.

Usage: release.py TAG [-m MESSAGE] [--remote REMOTE]

The branch and tag are pushed in one atomic push, so the remote never gets one
without the other. Pushing the tag is what starts the packager release workflow.
"""

import argparse
import os
import subprocess
import sys


def git(*args, check=True):
    """Run a git command and return its stdout, stripped."""
    result = subprocess.run(["git", *args], capture_output=True, text=True)
    if check and result.returncode != 0:
        sys.exit(f"git {' '.join(args)} failed:\n{result.stderr.strip()}")
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("tag", help="tag to create, e.g. v1.0.0")
    parser.add_argument("-m", "--message", help="commit and tag message (default: 'Release TAG')")
    parser.add_argument("--remote", default="origin", help="remote to push to (default: origin)")
    args = parser.parse_args()
    message = args.message or f"Release {args.tag}"

    # Run from the repo root so `git add -A` covers the whole repo.
    root = git("rev-parse", "--show-toplevel", check=False)
    if not root:
        sys.exit("Not inside a git repository.")
    os.chdir(root)

    branch = git("symbolic-ref", "--short", "-q", "HEAD", check=False)
    if not branch:
        sys.exit("HEAD is detached. Check out a branch first.")
    if git("rev-parse", "-q", "--verify", f"refs/tags/{args.tag}", check=False):
        sys.exit(f"Tag {args.tag} already exists.")
    if args.remote not in git("remote").split():
        sys.exit(f"No remote named {args.remote}.")

    if git("status", "--porcelain"):
        git("add", "-A")
        git("commit", "-m", message)
        print(f"Committed changes on {branch}.")
    else:
        print("Nothing to commit.")

    git("tag", "-a", args.tag, "-m", message)
    print(f"Tagged {git('rev-parse', '--short', 'HEAD')} as {args.tag}.", flush=True)

    push = subprocess.run([
        "git", "push", "--atomic", "--set-upstream", args.remote,
        f"refs/heads/{branch}:refs/heads/{branch}",
        f"refs/tags/{args.tag}:refs/tags/{args.tag}",
    ])
    if push.returncode != 0:
        sys.exit(
            f"Push failed. The commit and tag are still local. Fix the problem and rerun:\n"
            f"  git push --atomic -u {args.remote} {branch} refs/tags/{args.tag}\n"
            f"or undo the tag with: git tag -d {args.tag}"
        )
    print(f"Pushed {branch} and {args.tag} to {args.remote}.")


if __name__ == "__main__":
    main()
