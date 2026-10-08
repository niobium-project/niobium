# Runtime lifecycle v1

- **Status:** Normative target; implementation evidence is in [N2 acceptance](../acceptance-plan-v0.2.md).
- **Decision:** [ADR-0022](../adr/0022-installer-dsl-and-aot-toolchain.md).
- **Machine contracts:** [runtime-state-v1.schema.json](../../api/schema/runtime-state-v1.schema.json), [runtime-plan-v1.schema.json](../../api/schema/runtime-plan-v1.schema.json).

## Runtime responsibilities

The runtime is a complete precompiled native executable. It reads the compiled
program embedded by the compiler, binds user inputs and host facts, evaluates
capability libraries, and executes a frozen host plan. It does not evaluate
Starlark or other author source and does not download a replacement library to
finish planning or recovery.

The first executable profile is macOS arm64, ordinary user scope, CLI and explicit
`--root`. Commands are `install`, `apply`, `uninstall`, `status` and `recover`.
Declared runtime inputs use `--set name=value`. Production discovery, elevation,
GUI, online sources and additional targets have independent roadmap packages.

## Evaluation and plan

Before mutation, the runtime validates the image, program, compatibility, ownership
and upgrade declaration. Recovery of a pending transaction precedes new work.
Unknown state or plan versions fail without trying to reinterpret their fields.

Each instance receives only its bound inputs, assets and resources. Evaluation is
defined by [capability-library-v1](capability-library-v1.md). The runtime validates
the union of outputs for ownership and collisions before freezing a plan. No
instance can reference another instance's unbound resource handle.

A frozen plan includes product and release identity, the program digest, instance
and library identities, selected inputs, migration identities, output contents,
resulting state and the host operations needed to reach the target. Content is
durable before any operation refers to it. A plan never records a future request
to rerun author code or consult a new library version.

## Durable wire records

`runtime-state-v1` describes the installed snapshot. Its `owner` definition
describes the root ownership receipt. `runtime-plan-v1` describes the pending
transaction, including nullable previous/next snapshots and exact output bytes.

| Record | Required identity and contents |
|---|---|
| Owner | Schema, product ID and random root ID |
| Snapshot | Root/product identity, generation, release/model versions, program digest, selected inputs, owned resource inventory, instance states and migration receipts |
| Resource inventory | Stable resource ID, relative path and content digest |
| Instance state | Instance/library identity, implementation digest, state version and hex-encoded bytes |
| Migration receipt | Rule ID, owner, source/target version and implementation digest |
| Plan | Schema/host ABI, resolved root path, product/root identity, generation, previous/next snapshot and owned file outputs |
| File output | Resource ID, relative path, SHA-256 and exact hex-encoded content |

A null next snapshot means uninstall and requires an empty output set. Every
non-null next snapshot uses the plan generation; previous generations are lower.
File outputs must match the next snapshot's resource inventory exactly. Persisted
root identity must match the opened root's ownership receipt. Native
validation checks these relationships and digests in addition to JSON shape.

Whole plans are bounded by `runtime_plan_bytes`; individual values also retain
the bounds in `contracts.Limits`. Hex strings contain two lowercase characters
per byte. Snapshot state is bounded by `wasm_state_bytes`. JSON Schema character
limits supplement native UTF-8 byte limits.

## Transactions and recovery

The initial host profile stages immutable generations and activates one through a
`current` symlink. A journal records the transaction and its commit boundary.
Before commit recovery validates the old generation receipt and all recorded
resource hashes before making any change, then restores OLD. Missing or tampered
old resources cause a refusal that preserves the pending plan. After commit
recovery completes NEW. All durable operations are bounded, idempotent and owned
by the host.

| Boundary | Required recovery result |
|---|---|
| Plan/content durable, transaction not begun | No active change; orphan content may be cleaned |
| Transaction begun, before commit | Roll back staged work and retain OLD |
| Commit durable, activation interrupted | Replay frozen activation and reach NEW |
| New state durable, cleanup interrupted | Keep NEW and finish owned cleanup |
| Unknown plan schema or missing required plan bytes | Reject before mutation and retain evidence |

The runtime writes migration state and deployment state in the same transaction.
It must not advance the model version while the active generation still describes
the old model. Repeated recovery reaches the same committed result.

Recovery replays host operations from the durable plan and copied output bytes.
It works when the original guest module is unavailable. Recorded library identity
still explains the result, but guest reevaluation is not part of recovery.

Before claiming an installation root, the runtime requires it to be empty
except for its transaction lock. A preexisting target generation is a conflict
before plan persistence; the host never adopts unrelated contents as owned.

Uninstall and generation cleanup remove only resources whose ownership is
established by the snapshot inventory, plus the host generation receipt. The
host prunes empty directories and preserves unregistered user-added files. It
never recursively deletes an entire generation merely because it owns the
generation name. Unknown or corrupt state is an explicit failure. User data does not become
owned merely because it is under a convenient path. Locking and path checks must
exclude concurrent transactions and link-based escapes within the supported
user-scope profile.

## Mechanism and policy

The generation/symlink implementation is an initial deployment profile. Its
business choices do not define all future capability libraries. Host primitive
contracts define effects and authority; standard libraries define higher-level
deployment conventions. The ownership boundary is specified in
[host primitives and standard libraries](../design/host-primitives-and-stdlib.md).

Product/model and library-state compatibility follow [migration-v1](migration-v1.md).
Application activation is a separate product capability. Deployment success does
not imply business migration success or reversibility.

## Acceptance

- `N2-LIFE-01`: install/apply/status/uninstall exercise a packaged program without author tooling.
- `N2-REC-01`: true process kills around durable transitions recover to OLD or NEW.
- `N2-REC-01`: recovery succeeds from frozen outputs with the guest removed.
- `N2-SAFE-01`: unknown plan/state schemas, missing bytes and ownership violations fail before mutation.
- `N2-MIG-01`: model migration, selected values and resulting state commit together.

Current code locations and gaps are tracked in [architecture overview](../architecture/overview.md).
