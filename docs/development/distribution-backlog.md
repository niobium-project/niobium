# Distribution backlog

Online, offline-file and self-extracting profiles are planned under
[ADR-0020](../adr/0020-distribution-delivery-milestones.md). The current runtime
packages fixed Component/content inputs; it has no connected online updater.

Independent `libs/trust`, `libs/repository` and `libs/package` components retain
cryptographic verification, bounded acquisition and safe tar.zst extraction tests.
Reuse at the current runtime boundary requires new contracts and acceptance.

Before implementing a profile, decide authorized sources, root/channel policy,
transport and logical identities, cache ownership, offline freshness, archive
limits and signing order. Qualify interrupted acquisition, corrupt bytes, expired
and rolled-back metadata, missing offline content and exact final-image execution.
Product policies belong to libraries and presets, not global kernel enums.
