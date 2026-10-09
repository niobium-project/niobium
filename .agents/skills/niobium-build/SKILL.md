---
name: niobium-build
description: Maintain git hooks installed by zig build. Use when changing hooks:install, hooks:pre-commit, hooks:pre-push, or the commit-message check.
---

# Git hooks

Hook behavior belongs to `hooks:install`, `hooks:pre-commit`, `hooks:pre-push`, and `check-commits`. Platform wrappers live in `.githooks/posix` and `.githooks/windows` and only call those steps. Do not put a second policy in the wrappers. `zig build hooks:install` copies the host platform's wrappers into `.git/hooks`.
