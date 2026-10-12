---
name: publish-release
description: "Prepares a WoW add-on for release (README, .pkgmeta, packager workflow). Use whenever the user mentions releasing, packaging, tagging or publishing an add-on, even without saying 'release'
---

# TODO: Skill title

One or two sentences on what this skill is for and what a good result looks like.

## When to use
When the user asks you to release a new version of the add-on to GitHub.

## Steps
1. Run `gh` cli utility to check the latest release tag. This will be used to increment the tag version number. The tag will always be in format x.x.x, which is major.minor.incremental version format.
2. Run `git` with the following information:
     1. Commit any uncommitted edits with message.
          1. If the update is only to the word list, commit message will be "Update to word list.".
          2. If the update is only to the ignore player list, commit message will be "Update to player list.".
          3. If the update is to both the word list and the ignore player list, commit message will be "Update to word list and player list.".
          4. If the updates are more extensive, prompt user for commit message.
     2. Set tag version
          1. If the user asks you to set the tag version number to a specific version, set the tag to the version the user asks.
          2. If the user does not give you a specific tag version number, consider the following:
               1. If the version only includes updates to the word list or the ignore player list, only update the incremental version number. This will be most releases.
               2. If the version is more than and update to the world list or the ignore player list, update the minor number.
               3. Only update the major number at the user's request. You may prompt the user for to update the major version if warranted.
     3. Push the local working branch to remote.
3. Run `gh` utility to create a pull request to merge with main. Squash commits to latest commit that you added during this skill.
4. Run `gh` utility to publish a release of the add-on with the tag set during this run. Use commit message as release notes.



## Examples
**Example 1**
Input: Release a new version on GitHub


<!-- ## Bundled files
<!-- Point to these only when they exist, and say when to read or run each one.
     Keep this file under about 500 lines; move long material into references/. 
- `scripts/`: code for repeatable or exact steps. Claude runs it without reading it all.
- `references/`: longer docs, read only when needed. Give files over 300 lines a table of contents.
- `assets/`: files used in the output, such as templates or icons. -->
