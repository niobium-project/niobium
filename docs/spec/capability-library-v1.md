# Capability library v1

- **Status:** Normative target; implementation evidence is in [N2 acceptance](../acceptance-plan-v0.2.md).
- **Decision:** [ADR-0022](../adr/0022-installer-dsl-and-aot-toolchain.md).

## Execution boundary

A capability library is a fixed Wasm module implementing a versioned contract.
The host controls instance inputs, asset handles, resource handles, state and
execution limits. Official and product libraries use the same interface. Library
origin confers no additional authority.

The initial engine is the pinned WAMR interpreter. No JIT, Wasm AOT engine mode, WASI or guest threads are enabled. Instruction metering bounds interpreter execution.
Only the imports below are allowed. Modules export memory and `nb_plan_v1`;
`nb_migrate_v1` is optional when no state transition is required. A start section,
`__post_instantiate` and `__wasm_call_ctors` are rejected. Guest initialization is
explicit and falls within the evaluation budget.

The bounded profile scanner rejects unsupported structure and imports. It does
not replace WAMR's full module validation. The compiler and runtime both use the
same profile checks. Dependency version, source hash, license and local changes
belong to `third_party/wamr/PROVENANCE.md`.

## Wasm ABI

All imports use module name `niobium_v1`. Parameters are 32-bit integers. Status
results use zero for success where no byte count is returned, and negative values
for errors. The public C declarations live in `api/c/capability.h`.

| Import | Signature | Result |
|---|---|---|
| `read` | `(kind, index, ptr, capacity) -> i32` | Bytes copied, or a negative error |
| `emit` | `(resource_index, ptr, len) -> i32` | Registers one output for a bound resource |
| `state` | `(ptr, len) -> i32` | Supplies the instance's resulting state |

| Read kind | Value | Index scope |
|---|---|---|
| Input | 1 | Current instance's ordered input bindings |
| OS | 2 | Index 0 only |
| Architecture | 3 | Index 0 only |
| Previous state | 4 | Index 0 only |
| Asset | 5 | Current instance's ordered asset bindings |

| Export | Signature | Requirement |
|---|---|---|
| `nb_plan_v1` | `() -> i32` | Required; zero means successful planning |
| `nb_migrate_v1` | `(from, to) -> i32` | Required when executing a declared state migration |
| `memory` | Wasm linear memory | Required; host validates every access |

Guests use their own static buffers. An exported allocator is not required. Guest
pointers never identify host memory. The host rejects overflow, out-of-bounds
ranges, invalid kinds or indexes, duplicate resource emits and output budget
violations. Host-owned copies survive guest teardown; borrowed guest pointers do
not escape evaluation.

## Host evaluation

The native host receives input byte strings, asset byte strings, previous state,
OS, architecture and a resource count. Optional migration parameters contain
`from` and `to`. Its result contains copied resource outputs and resulting state.

If migration is requested, the host calls `nb_migrate_v1` before `nb_plan_v1` and
makes the migrated state available to planning. Previous-state reads remain
stable within each phase: migration reads persisted state, planning reads the
migration result, and `state` proposes a replacement without changing that
phase's read snapshot. Migration may emit state only; resource emission is confined to planning.
Migration and planning share one budget. Fuel or equivalent instruction accounting, memory, host-call counts and
aggregate output are bounded by the host limits. A trap, nonzero guest result or
budget exhaustion discards the complete evaluation output.

Resource bindings are grants, not mandatory outputs. Omitted resources are absent
from the desired generation. Planning may preserve existing state; migration must
produce exactly one replacement state before planning. Planning may replace state
once.

Guest execution performs no filesystem mutation. The runtime first collects and
validates all outputs, then freezes them in the host transaction plan. A guest's
`emit` is a proposed desired resource value, not a write syscall. Recovery needs
the frozen host plan and bytes, without executing the guest again.

WAMR process initialization and teardown must have a single controlled owner.
Host context is module-instance data, never unscoped mutable library state. If
the engine needs serialized initialization, that constraint is explicit in the
host implementation and concurrency tests.

## Compatibility and acceptance

Library digest, library ABI, instance identity and state version are recorded
separately. A new implementation cannot claim compatibility by reusing an ID.
State transitions follow [migration-v1](migration-v1.md). Host imports are an ABI:
adding authority requires a new reviewed host contract, not a broader guest import
allowlist.

- `N2-LIB-01`: a real guest observes bound input, OS and architecture and emits output.
- `N2-SAFE-01`: unauthorized imports, start behavior and malformed modules are rejected.
- `N2-SAFE-01`: traps, invalid pointers, duplicate output and budget exhaustion leave no machine effects.
- `N2-LIB-01`: official and external libraries use the same ABI without rebuilding the runtime.
- `N2-MIG-01`: declared library-state migration runs before planning and preserves the evaluation budget.

The guest SDK design is in [Wasm library SDK](../design/wasm-library-sdk.md).
