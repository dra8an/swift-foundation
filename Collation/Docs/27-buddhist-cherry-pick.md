# Cherry-picking port/buddhist onto upstream/main

## Background

The `port/buddhist` branch was developed on `upstream/release/6.3`. Its
changes need to land on `upstream/main` for PR submission. Since the
collation repo (`swift-foundation-collation`) is busy with port/collation
work, use a separate clone to avoid interference.

## Setup (separate clone)

```sh
cd ~/Projects/dra8an
git clone git@github.com:dra8an/swift-foundation.git swift-foundation-buddhist
cd swift-foundation-buddhist
git remote add upstream https://github.com/swiftlang/swift-foundation.git
git fetch upstream
git fetch origin port/buddhist

# Create a new branch from upstream/main
git checkout -b port/buddhist-rebase upstream/main

# Set local identity (same as collation repo)
git config --local user.name "dra8an"
git config --local user.email "chonbey@hotmail.com"
git config --local commit.gpgsign false

# Cherry-pick the commits from port/buddhist
git log --oneline origin/port/buddhist  # identify the commits
git cherry-pick <first-commit>^..<last-commit>

# Resolve any conflicts, then push
git push origin port/buddhist-rebase
```

## Claude Code session prompt

```
We're working on cherry-picking the Buddhist calendar feature from
port/buddhist (based on release/6.3) onto upstream/main for PR submission.

Repo: ~/Projects/dra8an/swift-foundation-buddhist
Branch: port/buddhist-rebase (on top of upstream/main)
Remote: origin = github.com/dra8an/swift-foundation

The original commits are on origin/port/buddhist. Cherry-pick them onto
the new branch, resolve any conflicts, and prepare for a PR to
swiftlang/swift-foundation.

Git identity: dra8an chonbey@hotmail.com, GPG off, NEVER add
Claude/Anthropic to commits, commit and push ONLY when explicitly asked.

PR #2028 (port/hebrew-perf-and-dedup) is already open — don't touch that.
```
