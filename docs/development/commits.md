# Commit conventions

Format: `<type>(<scope>): <summary>`, with an English summary of ≤ 72 characters that does not end with a period.

- `type`: `feat`, `fix`, `test`, `docs`, `refactor`, `chore`, `adr`, `build`.
- `scope`: a module name (`trust`, `transaction`, `ui-kit`…) or `repo`.
- The body explains the reason, contract changes, and verification commands and results; when the change exceeds 300 net lines, explain why.

Example: `feat(trust): implement root rotation`.

`zig build check-commits -- origin/main..HEAD` validates the format.
`zig build check-commits -- --message-file <path>` validates one message file.

`zig build hooks:install` copies the repository hooks into `.git/hooks`. It does not change git config. Pre-commit runs `zig fmt --check` on staged Zig files. `commit-msg` checks the subject with the message-file command. Pre-push checks each commit that would be published, using `origin/main` as the base for a new branch.
