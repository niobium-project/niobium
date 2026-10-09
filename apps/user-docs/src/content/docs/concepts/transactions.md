---
title: Transactions and recovery
description: How the Component-v2 kernel freezes installation plans and recovers publication after interruption.
---

The Component-v2 kernel validates and freezes an installation plan before changing deployment resources. A durable commit decision determines whether recovery preserves the old publication or completes the new one.

These concepts apply to the current user-scope profile demonstrated in the [DSL tutorial](/tutorial/). The [runtime lifecycle contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/runtime-lifecycle-v2.md) owns the protocol; [Status and platforms](/status/) records execution evidence.

## Owned roots and generations

Each logical root has an ownership record and unpublished generation directories. One product-declared state root coordinates the transaction across every participating root.

```text
<root>/
  current -> .niobium-v2/generations/<transaction>/data/
  .niobium-v2/
    owner.json
    generations/<transaction>/data/...
    installation.json    in the coordinator root
```

`current` publishes generation content through a Unix symlink or Windows junction. The coordinator also stores frozen content, a pending plan, and a commit decision. Those records bind the installation instance and complete root mapping.

The kernel claims only absent or empty unowned roots. Existing ownership must match the product, installing account, and root mapping. Nonblocking root locks exclude cooperating concurrent operations; a busy root reports `KernelBusy`.

## Preparation and publication

The kernel first evaluates fixed capability calls and validates their desired resources. It captures and verifies content before persisting the complete pending plan.

It then prepares an unpublished generation for every root, checking file contents and native access and persisting receipts. Only after all roots are prepared does the coordinator persist its commit decision.

With that decision durable, the kernel publishes every prepared generation and persists the next installation snapshot. Cleanup removes unchanged retired resources and completes the transaction. Uninstall instead removes the published pointers and active snapshot.

Cross-root publication is sequential. Observers can temporarily see different releases in different roots; the recovery guarantee does not imply simultaneous visibility across filesystems.

## Recovery outcomes

Every invocation completes compatible pending work before its requested action. This includes `status`, which can therefore perform recovery.

| Durable transaction state | Recovery | Published outcome |
|---|---|---|
| No commit decision | Abort completed unpublished preparation | Previous publication |
| Valid commit decision and required receipts | Complete publication and snapshot persistence | Next publication |
| Incompatible or inconsistent records | Refuse unsafe replay and preserve evidence | No inferred recovery result |

Recovery uses the frozen host plan. It does not rerun author code or capability libraries, fetch replacement inputs, or guess missing resources. Repeating a completed recovery is idempotent.

Uninstall retains ownership records and verified content storage. Modified or unknown files may remain in retired generations because cleanup requires the recorded identity and contents to match. Repair produces a fresh desired generation; it does not establish an old-good state after arbitrary external corruption.

## Application data and compatibility

Product model changes and call-state changes require their own explicit compatibility declarations. The kernel checks those independently of the release sequence before mutation.

Application databases and other business data remain product-owned. Deployment recovery does not imply database rollback, and the retained [App Bootstrap protocol](/concepts/app-bootstrap/) is not a hook in the current Component-v2 profile.
