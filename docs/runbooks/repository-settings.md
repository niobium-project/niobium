# Repository settings for pull requests

`main` accepts a fast-forward push from a maintainer. The [`merge-prs` skill](../../.agents/skills/merge-prs/SKILL.md) is that push. These settings keep the GitHub merge buttons from writing a second history.

The maintainer runs the commands from a clone of `niobium-project/niobium`, in this order. Classic branch protection refuses a merge-commit-only repository while its own linear-history setting is on. Linear history and verified signatures therefore live in a ruleset. That ruleset has no bypass, so an admin push has to be linear and signed too.

## Labels

```sh
gh label create merge-me:squash --repo niobium-project/niobium \
  --description "Land as one commit signed by the landing maintainer" \
  --color 0E8A16
gh label create merge-me:no-squash --repo niobium-project/niobium \
  --description "Land keeping commits; rebase and re-sign when needed" \
  --color 1D76DB
```

Creating a label that already exists exits non-zero. Confirm with `gh label list --repo niobium-project/niobium`.

## Branch protection

One approving review is required. Admin enforcement stays off, so the landing push is not blocked by the `linux` check. Required signatures stay on here as well as in the ruleset. Force-push stays disabled. Linear history on this object stays off, because the next section turns off squash and rebase.

```sh
gh api -X PUT repos/niobium-project/niobium/branches/main/protection --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["linux"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": false,
  "required_signatures": true
}
EOF
```

## Merge buttons

GitHub requires one merge method. Squash and rebase would re-sign commits with GitHub's key. The merge-commit method stays on, and the ruleset below rejects the merge commit it would create.

```sh
gh api -X PATCH repos/niobium-project/niobium --input - <<'EOF'
{
  "allow_merge_commit": true,
  "allow_squash_merge": false,
  "allow_rebase_merge": false,
  "allow_auto_merge": false,
  "delete_branch_on_merge": true
}
EOF
```

## Signed linear history

The ruleset targets `refs/heads/main`, is active, and lists no bypass actors. Create it once. A later change replaces the ruleset whose name is `Signed linear history`.

```sh
gh api -X POST repos/niobium-project/niobium/rulesets --input - <<'EOF'
{
  "name": "Signed linear history",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    {"type": "required_linear_history"},
    {"type": "required_signatures"}
  ],
  "bypass_actors": []
}
EOF
```

## Check

```sh
gh api repos/niobium-project/niobium --jq \
  '{merge:.allow_merge_commit,squash:.allow_squash_merge,rebase:.allow_rebase_merge,auto:.allow_auto_merge}'
gh api repos/niobium-project/niobium/branches/main/protection --jq \
  '{admins:.enforce_admins.enabled,linear:.required_linear_history.enabled,signatures:.required_signatures.enabled,reviews:.required_pull_request_reviews.required_approving_review_count}'
gh api repos/niobium-project/niobium/rulesets --jq \
  '.[] | select(.name=="Signed linear history") | {enforcement,name}'
```

Expect `merge: true`, `squash: false`, `rebase: false`, `auto: false`. Expect `admins: false`, `linear: false`, `signatures: true`, `reviews: 1`. Expect the ruleset to be `active`. Read its rules with the ruleset id from `gh api repos/niobium-project/niobium/rulesets`. They are `required_linear_history` and `required_signatures`, and `bypass_actors` is empty.
