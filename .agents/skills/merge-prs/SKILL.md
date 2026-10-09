---
name: merge-prs
description: Land labeled GitHub pull requests onto main as a linear signed history. Use when asked to merge, land, or scan merge-me pull requests. Requires maintainer approval plus merge-me:squash or merge-me:no-squash. Resolves conflicts, checks every landed commit, pushes once, and comments on each pull request.
---

# Merge pull requests

Land open pull requests onto `main`. The commit rules are in [Commits and pull requests](../../../docs/development/commits.md). This file is the procedure.

Use `gh` and `git`. Do not use the GitHub merge buttons. Do not force-push.

## Stop before any pull request

Stop the whole run when any of these is true:

1. `gh auth status` fails, or `git` is missing.
2. `git config --get commit.gpgsign` is not `true`. New commits would be unsigned.
3. `git status --porcelain` is not empty.
4. After `git fetch origin main`, local `main` and `origin/main` differ. This run only creates the commits it pushes.

Check out `main` and fast-forward it: `git switch main` and `git merge --ff-only origin/main`.

## Which pull requests

List both labels, then drop duplicate numbers. A pull request with both labels keeps its commits (`merge-me:no-squash` wins). Skip drafts. Handle the rest in ascending pull request number.

```sh
gh pr list --state open --label merge-me:squash --limit 100 \
  --json number,title,body,isDraft,author,baseRefName,headRefOid
gh pr list --state open --label merge-me:no-squash --limit 100 \
  --json number,title,body,isDraft,author,baseRefName,headRefOid
```

The base branch must be `main`. Any other base is a failure for that pull request.

## Maintainer approval

A maintainer is a user whose permission on `niobium-project/niobium` is `admin` or `maintain`:

```sh
gh api repos/niobium-project/niobium/collaborators/LOGIN/permission --jq .permission
```

The pull request is approved when either:

- a review with state `APPROVED` comes from a maintainer, or
- the author is a maintainer and a maintainer added the current merge-me label.

GitHub does not let an author approve their own pull request. The label case covers that.

```sh
gh api repos/niobium-project/niobium/pulls/N/reviews
gh api repos/niobium-project/niobium/issues/N/events
```

Use the latest `labeled` event whose label name is the merge-me label still on the pull request. The actor of that event added it.

## One batch, one push

Record `origin/main`. For each approved pull request, land it on local `main`, then check only the commits just added. After every pull request in the batch has landed, run the test suite once, then push once.

On a per-pull-request check failure, reset only that pull request (`git reset --hard` to the `main` sha from before it) and continue with the others. On a test-suite failure, reset local `main` to `origin/main`, so nothing from the batch is left, and fail every pull request in the batch. Never reset commits this run did not create.

`git reset --hard` is allowed only before the push, and only to a sha this run recorded.

## Land one pull request

Fetch the head. This works for forks:

```sh
git fetch origin pull/N/head
```

The fetched sha is `FETCH_HEAD`. Remember it as the source sha.

### Keep commits

When `git merge-base --is-ancestor main SOURCE` succeeds, the pull request is already on top of local `main`. Fast-forward:

```sh
git merge --ff-only SOURCE
```

Those commits keep their authors and their signatures.

Otherwise rebase onto local `main`. Author names stay. The landing maintainer signs every rewritten commit, because a rebase creates new commit objects. `commit.gpgsign=true` makes `git rebase` sign them.

```sh
base=$(git merge-base main SOURCE)
git switch --detach SOURCE
git rebase --onto main "$base"
new=$(git rev-parse HEAD)
git switch main
git merge --ff-only "$new"
```

When rebase stops on a conflict, resolve it inside the commit that stopped. Each commit must still build on its own. Continue with `git add` and `git rebase --continue`. Do not use `--reset-author`.

When the conflict cannot be resolved, run `git rebase --abort`, switch back to `main`, and fail this pull request. Record `git range-diff "$base..SOURCE" "main~count..main"` for the closing comment. `count` is the number of commits this pull request added.

### Squash

Build one commit. The subject is the pull request title. The body is the pull request body. The title must already be a valid subject; do not invent a replacement.

```sh
git merge --squash SOURCE
```

Resolve conflicts in that single commit when there are any. When they cannot be resolved, `git reset --hard` to the `main` sha from before this pull request and fail it.

One author: `git commit --author="Name <email>"`. Several authors: the pull request author is the author, and each other commit author is a `Co-authored-by:` trailer. `commit.gpgsign=true` signs the commit. The original author stays in the author field.

## Checks

After each pull request, with `before` the `main` sha from before it:

```sh
zig build check-each -- "$before..HEAD"
zig build check-commits -- --strict "$before..HEAD"
```

`check-each` runs `zig build check` and `zig build` in a worktree for every new commit. `--strict` rejects merge commits, `fixup!` / `squash!` / `amend!` subjects, and commits with no signature header.

After the last pull request, once:

```sh
zig build test -Dsuite=unit,conformance,e2e
```

A failure prints the reason. Do not push.

## Push and verify

```sh
git push origin main
```

The pre-push hook runs `check-commits --strict` for `refs/heads/main`. When the hook fails, do not comment that the pull request landed.

Then fetch `origin/main` and, for every sha just pushed:

```sh
gh api repos/niobium-project/niobium/commits/SHA --jq .commit.verification.verified
```

Every value must be `true`. A `false` value means GitHub rejected the signature. Say so on the pull request. Do not force-push a replacement.

## Comments

Failing a pull request: post one comment, then remove whichever merge-me label it has.

```sh
gh pr comment N --body-file -
gh pr edit N --remove-label merge-me:squash --remove-label merge-me:no-squash
```

The failure comment names the reason in one sentence, then: add the label again after the fix.

Success: comment with the strategy (`squash` or `keep commits`), each landed sha and subject, the three checks above, and the range-diff when commits were rewritten.

When the source sha is now on `origin/main`, GitHub marks the pull request merged. Comment, and do not close it again. When the commits were rewritten, `gh pr close N` after the comment. Close only after `git push` has succeeded.

## Report

End the run with one row per pull request: number, strategy, result (`landed` or the failure reason), and landed shas.
