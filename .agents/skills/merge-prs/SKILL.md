---
name: merge-prs
description: Land labeled GitHub pull requests onto main as a linear signed history. Use when asked to merge, land, or scan merge-me pull requests. Requires maintainer approval plus merge-me:squash or merge-me:no-squash. Orders a stack by branch dependency, resolves conflicts, checks every landed commit, pushes once, deletes the landed work branch locally and on origin, and comments on each pull request.
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

List both labels, then drop duplicate numbers. A pull request with both labels keeps its commits (`merge-me:no-squash` wins). Skip drafts.

```sh
gh pr list --state open --label merge-me:squash --limit 100 \
  --json number,title,body,isDraft,author,baseRefName,headRefName,headRefOid,isCrossRepository
gh pr list --state open --label merge-me:no-squash --limit 100 \
  --json number,title,body,isDraft,author,baseRefName,headRefName,headRefOid,isCrossRepository
gh pr list --state open --limit 100 --json number,headRefName,baseRefName,isDraft
```

The third command is the open-pull-request index. Use it to resolve base branches. Do not land a pull request just because it appears there.

## Queue order

Write the landing order before the first landing. The report uses that order.

A pull request depends on another when its base branch is that other pull request's head branch. The dependency lands first. A pull request whose base is `main` has no dependency. Independent pull requests go in ascending number.

Walk the chain. A pull request stacked on a pull request stacked on `main` lands after both, nearest base first.

A cycle fails every pull request in the cycle. Remove those labels. The comment names the cycle.

When the base branch is not `main` and no open pull request has that head branch, fail this pull request and remove its label. The comment names the missing base branch.

When the base pull request is open but not in this batch, leave this label in place. Comment that it waits for that number. Skip it. If that comment is already the latest comment, do not comment again.

When a pull request fails its own checks, leave the label on every pull request that depends on it. Comment that it waits for the failed number. Continue with pull requests that do not depend on the failure.

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

Record `origin/main`. For each approved pull request, in queue order, land it on local `main`, then check only the commits just added. After every pull request in the batch has landed, run the test suite once, then push once.

On a per-pull-request check failure, reset only that pull request (`git reset --hard` to the `main` sha from before it). Skip pull requests that depend on it. Continue with the rest of the queue. On a test-suite failure, reset local `main` to `origin/main`, so nothing from the batch is left, and fail every pull request in the batch. Never reset commits this run did not create.

`git reset --hard` is allowed only before the push, and only to a sha this run recorded.

## Land one pull request

Fetch the head. This works for forks:

```sh
git fetch origin pull/N/head
```

The fetched sha is `FETCH_HEAD`. Remember it as the source sha.

Remember each landed pull request's source sha. A dependent pull request needs that sha as the cut, so the dependency's commits are not replayed.

### Keep commits

When `git merge-base --is-ancestor main SOURCE` succeeds, the pull request is already on top of local `main`. Fast-forward:

```sh
git merge --ff-only SOURCE
```

Those commits keep their authors and their signatures.

Otherwise rebase the unique commits onto local `main`. Author names stay. The landing maintainer signs every rewritten commit, because a rebase creates new commit objects. `commit.gpgsign=true` makes `git rebase` sign them.

The cut is the dependency's source sha when this pull request has a dependency. Otherwise the cut is `git merge-base main SOURCE`. After a squash of the dependency, that source sha is not on `main`. A merge-base with `main` would replay the dependency's commits.

```sh
git switch --detach SOURCE
git rebase --onto main "$cut"
new=$(git rev-parse HEAD)
git switch main
git merge --ff-only "$new"
```

The cut must be an ancestor of `SOURCE`. When it is not, fail this pull request. The branch no longer contains the base it declared.

When rebase stops on a conflict, resolve it inside the commit that stopped. Each commit must still build on its own. Continue with `git add` and `git rebase --continue`. Do not use `--reset-author`.

When the conflict cannot be resolved, run `git rebase --abort`, switch back to `main`, and fail this pull request. Record `git range-diff "$cut..SOURCE" "main~count..main"` for the closing comment. `count` is the number of commits this pull request added.

### Squash

Rebase onto local `main` with the same cut as above, so only this pull request's commits remain. Then fold those commits into one. The subject is the pull request title. The body is the pull request body. The title must already be a valid subject; do not invent a replacement.

```sh
git reset --soft main
git commit
```

When `main` is already an ancestor of `SOURCE` and the label is squash, skip the rebase and run `git merge --squash SOURCE` from `main`.

Resolve conflicts in that single commit when there are any. When they cannot be resolved, `git reset --hard` to the `main` sha from before this pull request and fail it.

One author: `git commit --author="Name <email>"`. Several authors: the pull request author is the author, and each other commit author is a `Co-authored-by:` trailer. `commit.gpgsign=true` signs the commit. The original author stays in the author field.

## Checks

After each pull request, with `before` the `main` sha from before it:

```sh
zig build check:each -- "$before..HEAD"
zig build check:commits -- --strict "$before..HEAD"
```

`check:each` runs `zig build check` and `zig build` in a worktree for every new commit. `--strict` rejects merge commits, `fixup!` / `squash!` / `amend!` subjects, and commits with no signature header.

After the last pull request, once:

```sh
zig build test -Dsuite=unit,conformance,e2e
```

A failure prints the reason. Do not push.

## Push and verify

```sh
git push origin main
```

The pre-push hook runs `check-commits --strict` for `refs/heads/main`. The Signed linear history ruleset rejects the push when a commit is unverified or the history is not linear. Admins do not bypass that ruleset. When the hook or the push fails, do not comment that the pull request landed.

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

## Delete the work branch

Do this only after `git push origin main` has succeeded and every landed sha verified. Delete a branch only for a pull request this run landed. Never delete `main`.

Leave a branch that is still the base of another open pull request. That pull request is still stacked on it. Delete the branch after that pull request lands.

Skip the remote delete when `isCrossRepository` is true. The head branch belongs to the fork.

```sh
git push origin --delete BRANCH
git fetch origin --prune
git branch -d BRANCH
```

`git branch -d` deletes the local branch when its tip is contained in `main`. A squash or a rebase leaves the old tip off `main`, so `-d` refuses. For a branch this run landed that way, `git branch -D BRANCH` removes the local branch. A missing local or remote branch is already clean.

## Report

End the run with one row per pull request, in queue order: number, the dependency it waited on, strategy, result (`landed`, `waiting`, or the failure reason), and landed shas.
