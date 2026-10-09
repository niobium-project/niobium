---
title: Authority and access boundaries
description: How logical roots, explicit grants, and native access policies constrain Component-v2 installation effects.
---

A capability library receives only the authority declared for its call. The current Component-v2 profile has no ambient filesystem, network, process, or elevation authority. It supports user-scope roots and rejects machine scope.

The [DSL tutorial](/tutorial/content-capabilities/) shows a files library request bounded by a named grant. The [capability contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/capability-library.md) owns the library boundary; real execution records live on [Status and platforms](/status/).

## Roots and grants

A product declares logical roots and selects one as its state coordinator. At invocation, the host binds those roots to absolute native paths. It rejects duplicate, aliased, nested, or incompatibly owned roots before deployment.

A grant names a root and versioned primitive, with path, entry, byte, and access ceilings. Calls receive only their declared grants. Possessing a content reference or declaring a primitive requirement does not grant deployment authority.

Libraries return resource proposals. The host checks each proposal against its grant and validates the complete inventory before freezing the transaction plan. Libraries cannot directly mutate deployment roots or select ambient host source paths.

## Requested access

Every desired container supplies explicit file and directory access policies. A grant is an upper bound; its ceiling is not an implicit desired policy. The portable contract describes access for the installing owner and other users.

The host creates unpublished resources privately, verifies their contents, applies the requested native access, and reads it back. Unsupported filesystems, ACL conflicts, or policies outside the portable subset produce explicit errors.

The contract does not provide arbitrary principals, deny rules, ownership transfer, or permission inheritance editing. Directory traversal and privileged bypass have separate OS semantics. The [access policy contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/access-policy.md) defines the supported subset and its limits.
