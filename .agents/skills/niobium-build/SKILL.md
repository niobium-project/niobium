---
name: niobium-build
description: Maintain git hooks installed by zig build. Use when changing hooks:install, hooks:pre-commit, hooks:pre-push, or the commit-message check.
---

# Git hooks

Hook behavior belongs to `hooks:install`, `hooks:pre-commit`, `hooks:pre-push`, and `check-commits`. Do not put a second policy in the shell wrappers under `.githooks/`. `zig build hooks:install` copies those wrappers into `.git/hooks`.
