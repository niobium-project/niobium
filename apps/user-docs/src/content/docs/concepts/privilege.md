---
title: Authority and access boundaries
description: How logical roots, explicit grants, and native access policies constrain Component-v2 installation effects.
---

A capability library receives only the authority declared for its call. The current Component-v2 profile has no ambient filesystem, network, process, or elevation authority. It supports user-scope roots and rejects machine scope.

The [DSL tutorial](/tutorial/content-capabilities/) shows a files library request bounded by a named grant. The [capability contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/capability-library-v2.md) owns the library boundary; real execution records live on [Status and platforms](/status/).

## Roots and grants

A product declares logical roots and selects one as its state coordinator. At invocation, the host binds those roots to absolute native paths. It rejects duplicate, aliased, nested, or incompatibly owned roots before deployment.

A grant names a root and versioned primitive, with path, entry, byte, and access ceilings. Calls receive only their declared grants. Possessing a content reference or declaring a primitive requirement does not grant deployment authority.

Libraries return resource proposals. The host checks each proposal against its grant and validates the complete inventory before freezing the transaction plan. Libraries cannot directly mutate deployment roots or select ambient host source paths.

## Requested access

Every desired container supplies explicit file and directory access policies. A grant is an upper bound; its ceiling is not an implicit desired policy. The portable contract describes access for the installing owner and other users.

The host creates unpublished resources privately, verifies their contents, applies the requested native access, and reads it back. Unsupported filesystems, ACL conflicts, or policies outside the portable subset produce explicit errors.

The contract does not provide arbitrary principals, deny rules, ownership transfer, or permission inheritance editing. Directory traversal and privileged bypass have separate OS semantics. The [access policy contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/access-policy-v1.md) defines the supported subset and its limits.

## Retained v1 elevation

<details data-pagefind-ignore>
<summary>Manifest-era helper protocol and residual risk</summary>

The manifest-era runtime has a separate machine-scope helper protocol. For one transaction, an unelevated installer starts a second copy with administrator rights through the platform authorization mechanism.

That helper accepts only closed typed file and integration operations. It authenticates requests with a transaction ID and random nonce, rejects replayed message IDs, and confines writes to the selected product's machine root and known integration locations. It has no operation to execute a program, load a library, or open a network connection.

This helper is not a Component-v2 elevation API. Its retained wire contract is [IPC v1](https://github.com/niobium-project/niobium/blob/main/docs/spec/ipc-v1.md); its evidence retains its original scope.

### Retained helper risk { #what-the-boundary-does-not-cover }

The v1 helper confines write locations. The unelevated installer verifies the release content. An attacker controlling that user's session can supply different content within the authorized product root and register its permitted integrations.

The retained helper does not grant arbitrary writes outside those locations. This risk describes the v1 helper protocol; it does not extend the authority available to a Component-v2 library.

</details>
