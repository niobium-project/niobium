---
name: niobium-build
description: Maintain git hooks installed by zig build. Use when changing hooks:install, hooks:pre-commit, hooks:pre-push, or the commit-message check.
---

# Git hooks

Hook behavior belongs to `hooks:install`, `hooks:pre-commit`, `hooks:pre-push`, and `check-commits`. Platform wrappers live in `.githooks/posix` and `.githooks/windows` and only call those steps. Do not put a second policy in the wrappers. `zig build hooks:install` copies the host platform's wrappers into `.git/hooks`.

`zig build check-commits -- --strict <range>` rejects merge commits, `fixup!` / `squash!` / `amend!` subjects, and commits with no signature header. `hooks:pre-push` passes `--strict` when the remote ref is `refs/heads/main`.

`zig build check-each -- <range>` runs `zig build check` and `zig build` for every commit in the range, oldest first, and stops at the first failure. The limit is 64 commits.
