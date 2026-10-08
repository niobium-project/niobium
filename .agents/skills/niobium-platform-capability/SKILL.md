---
name: niobium-platform-capability
description: Contract-first workflow for capability libraries, host primitives and platform backends, including authority, ownership, migration and recovery.
---

# Capability libraries and host primitives

Read ADR-0022, the active capability/runtime/migration specs and [host primitives and stdlib](../../../docs/design/host-primitives-and-stdlib.md) before extending a capability.

## Choose the owner

1. Use an author library or preset for build-time composition and product policy.
2. Use a Wasm capability library for runtime computation over existing host inputs and primitives.
3. Add a host primitive only when the required mechanism is absent. Define its authority, platform/scope support, ownership and recovery before implementation.
4. Keep platform implementation details inside the declared native backend. Libraries use the public guest ABI, including official libraries.

## Contract-first process

1. Specify request/result types, limits, versions, errors and required host grants.
2. Define observation, planning, durable operation and recovery boundaries. Guest outputs are proposals; they cause no machine mutation.
3. Describe ownership collision, user edits, uninstall, upgrade and state migration behavior.
4. Add negative vectors for unavailable authority, invalid handles, unsupported targets and incompatible states.
5. Implement host mechanisms with a virtual/fault backend where appropriate, then real platform behavior. Run the same contract cases against both.
6. For elevation, define a closed authenticated helper operation; no generic execution import is allowed.
7. Update runtime profile compatibility and compiler checks. Persist required primitive versions in recovery records.

Targets enter at Tier 3 and qualify under [ADR-0014](../../../docs/adr/0014-tier-based-platform-support.md). The new PoC is macOS arm64 user scope; legacy platform evidence does not qualify a new primitive automatically.

## Platform review

- Windows: bounded UTF-16 conversion, long paths, sharing violations, service/registry ownership, junction activation and elevation cancellation.
- macOS: code signatures after packaging, symlink/path containment, bundle conventions, main-thread UI and explicit privileged sessions.
- Linux: service-manager availability, X11 failure, file permissions, desktop registration and explicit unsupported behavior.

Each operation defines bounded retry and its timeout. Missing optional platform facilities need a contractually defined result; the implementation must not silently treat them as success.

## Completion

Run the named N2 contract and real-OS scenarios, the relevant existing regression lane, and `zig build verify`. Record NOT_RUN/BLOCKED where execution evidence is missing. Include the exact runtime profile, library identity and platform/scope in the evidence.
