# Commits and pull requests

A commit subject is `<type>(<scope>): <summary>`. The summary is English and at most 72 characters. It has no final period.

- `type`: `feat`, `fix`, `test`, `docs`, `refactor`, `chore`, `adr`, `build`, `revert`.
- `scope`: a module name (`trust`, `transaction`, `ui-kit`) or `repo`.
- The body states the reason, any contract change, and the verification commands with their results. A change over 300 net lines says why it is that size.

Example: `feat(trust): implement root rotation`.

`zig build check-commits -- origin/main..HEAD` checks subjects on a range.
`zig build check-commits -- --message-file <path>` checks one message file.
`zig build check-commits -- --strict <range>` is the rule for commits that land on `main`.

## Signing

Each contributor turns on signing for this clone. `zig build hooks:install` copies hook scripts. The contributor owns the signing config below.

```sh
git config commit.gpgsign true
git config gpg.format ssh
git config user.signingkey ~/.ssh/id_ed25519.pub
```

GPG works the same way: set `gpg.format` to `openpgp` and set `user.signingkey` to the key id. The public key is registered on the GitHub account. The [Signed linear history ruleset](../runbooks/repository-settings.md) rejects an unverified signature, and an admin cannot bypass that ruleset.

A fast-forward keeps the author signature on each commit. A squash, a rebase, or a conflict resolution creates new commits. The landing maintainer signs those, and the author field stays the original author. Several authors on a squash become `Co-authored-by` trailers.

## What lands

Each commit on `main` has one purpose a reviewer can read without the neighboring commits. That commit also builds. `zig build check-each -- origin/main..HEAD` runs `zig build check` and `zig build` on every commit in the range, oldest first, and stops at the first failure. A range longer than 64 commits fails the step.

Draft pull requests may hold `fixup!`, `squash!`, and `amend!` subjects. The commit-msg hook accepts a prefix when the rest of the subject is valid. `--strict` rejects those prefixes, merge commits, and any commit whose object has no `gpgsig` or `gpgsig-sha256` header.

## Labels

Two labels select a pull request for landing. The procedure is the [`merge-prs` skill](../../.agents/skills/merge-prs/SKILL.md).

| Label | Result |
|---|---|
| `merge-me:squash` | One commit. The subject is the pull request title and the body is the pull request body. |
| `merge-me:no-squash` | The commits stay. A branch already on `main` fast-forwards. The skill rebases any other branch and resolves each conflict in the commit that hit it. |

A pull request with both labels keeps its commits. Drafts are not eligible. A pull request based on another open pull request lands after that one. The [`merge-prs` skill](../../.agents/skills/merge-prs/SKILL.md) decides the order.

A maintainer is a collaborator with `admin` or `maintain` permission. Approval is an approving review from a maintainer. On a maintainer's own pull request, the merge-me label added by a maintainer is the approval, because GitHub has no self-approval.

The landing maintainer runs the skill locally. It comments on success and on failure. A failure comment removes the merge-me label. Add the label again after the fix. After the push to `main` succeeds, the skill deletes that pull request's branch locally and on origin. A branch that is still the base of another open pull request stays until that pull request lands.

GitHub's squash and rebase buttons are off. The remaining merge-commit button cannot land a pull request while linear history is required. Repository settings are in [repository settings](../runbooks/repository-settings.md).

## Reverts

A revert uses type `revert`. The subject names the behavior that returns, and the body names the reverted commit.

Example: `revert(trust): revert root rotation`.

## Hooks

`zig build hooks:install` copies [`.githooks/posix`](../../.githooks/posix/pre-commit) or [`.githooks/windows`](../../.githooks/windows/commit-msg.cmd) into `.git/hooks`. Pre-commit runs `zig fmt --check` on staged Zig files. The commit-msg hook checks the subject. Pre-push checks the commits being pushed, and passes `--strict` when the remote ref is `refs/heads/main`. On Windows, Git for Windows starts `.githooks/windows/launch.sh`, which runs the sibling `.cmd` script.
