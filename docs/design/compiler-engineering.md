# Compiler engineering

- **Kind:** Engineering design for [compiler-frontends-v2](../spec/compiler-frontends-v2.md).
- **Owners:** `compiler`, `program`, `image` and the build-time language adapters.
- **Current boundary:** Shared authoring, typed binding, exact locks, local emission cache,
  cancellation, source diagnostics and native assembly are implemented. Registry
  resolution, broader incremental reuse and parallel scheduling remain work packages.

## Stages and interfaces

The [compiler contract](../spec/compiler-frontends-v2.md) owns stage inputs,
validation and publication semantics. Frontends produce a typed author model and
an independent source map. The common backend captures fixed inputs, normalizes
content, binds WIT contracts and resolves input types before emitting the compiled
product. Product assembly consumes a complete published runtime package.

`compiler.author.Builder` is the native Zig construction API.
[`compiler_v2.h`](../../api/c/compiler_v2.h) owns the authoring C ABI;
Starlark calls it through the pinned Go worker. Complete Python, TypeScript, Go
and Rust packages wrap that same boundary. Their package versions do not replace
ABI negotiation. The retained `nbc_` facade and `program.Program` keep their v1
scope; new construction uses `nbc2_` and `program.model.Product`.

The CLI exposes `compile` for emitted IR plus explicit locked inputs and
`runtime-package` for publisher metadata. The latter inspects a template as data.
It does not execute target code to discover a profile. Inspectors and finalizers
receive private captured tool inputs; a writable executable handle is closed
before subprocess launch. A cancelled or failed build preserves the previous
published output.

## Dependencies and determinism

[Compiler inputs v1](../spec/compiler-inputs-v1.md) owns exact versions, hashes,
lengths, target requirements and dependency graphs. Resolution is an independent
build-time operation that produces this lock and explicit sources. No floating
version or alternate library is selected during a locked build or installation.
Publisher authorization is separate from byte identity.

The semantic model, source archive, canonical content, runtime template, library,
compiled product and final setup have independent identities. Content
normalization does not require the raw archive digest to equal the logical tree
digest. Source maps, acquisition locations and diagnostic presentation do not
change semantic identity. Signature metadata can change final image identity.

Author programs are evaluated on every invocation by default. An opt-in frontend
cache must declare every observable input, including module resolution, SDK
versions and build arguments. Native authors that inspect ambient state cannot
claim a complete dependency set automatically.

## Incremental execution and cache ownership

The current local cache uses per-key locking, immutable verified blobs and atomic
record publication. The production CLI includes its own executable identity in
the key. Emission reuse revalidates the model, contracts and exact inputs; a cache
hit never substitutes for those checks. This provides correctness before a wider
incremental scheduler is introduced.

| Reuse boundary | Key inputs | Invalidated by | Parallelization boundary |
|---|---|---|---|
| Author evaluation, opt-in only | Frontend/SDK identity, declared module graph, arguments and all observations | Any declared observable change | Independent author invocation |
| Content normalization | Raw input hash, canonical profile, transform program and limits | Source bytes, transform or profile | Independent captured source |
| Contract inspection | Component hash, engine/profile/tool identity and limits | Library, validator or profile | Disposable worker per library |
| Typed binding | Normalized author graph, reflected contracts and runtime profile | Any type, authority or graph change | Independent products; ordered graph validation within one product |
| Product emission | Bound semantic graph and wire version | Bound semantics or encoding | Immutable output generation |
| Unsigned assembly | Template, program, payload and assembler identity | Any input image byte | Independent candidate file |
| Signing | Exact candidate, signer and publisher policy | Always reconsider final bytes | Independent signer operation; never reuse credentials as cache data |

Additional stage caches must validate their own outputs, preserve diagnostic
source attribution on hits and compare clean versus cached results. Shared
libraries remain immutable; per-product arenas, candidate files and cancellation
state cannot be shared between concurrent jobs. A bounded scheduler must cancel
children, join them and retain ownership of every temporary before returning.

Cache garbage collection needs leases and quotas. It must preserve in-use objects
and remain unnecessary for correctness. Remote caches additionally need trust,
transport limits and poisoning tests; they cannot authorize release bytes.

## Diagnostics and cancellation

A diagnostic identifies a stable stage/code, qualified object kind and ID, cause
and optional source location. The versioned sidecar maps locations independently
of normalized ordering. Frontend adapters preserve their caller's file and line;
SDKs consume structured status rather than parsing human log text.

Further diagnostic work adds bounded expected/actual type detail, argument paths,
related dependency paths and multi-error collection. These are presentation and
analysis improvements, not alternative semantic validators.

Cancellation is checked at stage boundaries and streaming reads. Worker processes
have an absolute deadline, bounded output and explicit termination. Finalizers
have bounded execution. The publication rename is a single final operation;
cancellation after publication reports the resulting completed artifact rather
than inventing rollback of a delivered file.

## Delivery and acceptance

The [authoring guide](../development/authoring-v2.md) covers current APIs and
commands. The [roadmap](../roadmap-v0.3.md) assigns follow-on compiler and SDK
packages. Each package must carry clean/cached equivalence vectors, invalidation
cases, cancellation before publication, source-map independence and real
consumer execution. Throughput claims additionally require fixed workload,
profile, toolchain and hardware measurements.
