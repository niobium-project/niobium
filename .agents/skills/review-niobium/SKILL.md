---
name: review-niobium
description: Security and boundary checklist for reviewing Niobium changes (process execution, elevation, archive extraction, TUF, C ABI, size and dependency growth, module boundaries). Use for reviews, self-checks, or changes that touch the security surface.
---

# Niobium review checklist

Answer each item "yes/no/not applicable"; every "no" must come with a fix or a justification in the review.

## Compiler, libraries and runtime

- [ ] Author code and Starlark are absent from runtime dependencies.
- [ ] Product assembly preserves the runtime template input and executable code sections without relinking.
- [ ] Official and external libraries use the same checked ABI and authority grants.
- [ ] Wasm validation rejects ambient imports and automatic initialization; all explicit calls share their session budget; the parent enforces process deadlines and output bounds. Type-only imports are structurally checked and carry no callable authority.
- [ ] Guest state/output is copied and frozen before mutation; recovery executes only durable host plans.
- [ ] Library/product/framework versions and migration identities are checked independently.
- [ ] Core types contain no product-specific component/channel policy.

## Execution and elevation

- [ ] New process spawns appear only in paths listed in `build/modules.zig` `spawn_allowlist`.
- [ ] The spawn argv comes from validated data; it does not go through a shell; it has a timeout and an output limit.
- [ ] Elevated ops belong to the closed `ipc-v1` set; the helper validates the tx-id, the nonce, and that paths are inside the install root.
- [ ] When the helper crashes (EOF), the broker rolls back the transaction and keeps the installer alive.

## Archives and file system

- [ ] Retained archive extraction keeps its existing rejection rules. New content trees use the canonical pax profile and validate explicit symlink targets before materialization; build-tool extraction remains separate and rejects selected links. Neither path permits writes outside its owned root.
- [ ] Machine writes follow the selected host primitive lifecycle; generation deployment stages before pointer activation. Guest imports cannot write directly.
- [ ] Delete operations are confined to the install root and have journal records.

## Trust

The following checks apply to the retained TUF distribution profile and its library adaptation. Other declared profiles require their own authorization contract and evidence.

- [ ] All remote bytes are verified by TUF before use (length + sha256 + signature chain).
- [ ] Comparing old and new uses `release_sequence` and the TUF version number; rollback, freeze (expiry), and mix-and-match snapshots are rejected.
- [ ] Root rotation requires threshold signatures from both the old root and the new root.

## C ABI

- [ ] `export fn` does not expose Zig types, slices, error unions, or allocators.
- [ ] Every error maps to the owning ABI status; output buffers are provided by the caller or have a matching free function.
- [ ] The owning header (`compiler_v2.h`, versioned WIT or a retained header) matches its implementation and consumer tests; its designated test lane ran. C object handles reject foreign contexts and wrong kinds. Transient Component resources never enter durable values.

## Size and dependencies

- [ ] `zig build check:size`: setup ≤ 30 MiB, growth ≤ 5% (otherwise update the baseline in the same commit and explain).
- [ ] Retained `check-binary` rules stay unchanged. Component publication uses the exact OS/ABI policy in ADR-0024: no undeclared dependencies or interpreter; PE flags complete; no RWX segments or executable stack. Policy changes require measured imports and target evidence.
- [ ] New third_party code has a LICENSE, PROVENANCE.md, and hand-written bindings.

## Boundaries and quality

- [ ] No new import edges outside `build/modules.zig`.
- [ ] No new `lint-allow`, or each one has a specific reason.
- [ ] Test names carry acceptance IDs; acceptance table statuses have evidence.
- [ ] Logs and crash records contain no tokens, raw signed URLs, or archive bytes.
- [ ] No new queue, retry, or read without an upper bound (AGENTS.md section 5).
- [ ] Generated outputs are in sync with their inputs and were not edited by hand.
