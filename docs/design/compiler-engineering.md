# Compiler engineering

- **Kind:** Implementation design for [compiler-frontends-v1](../spec/compiler-frontends-v1.md).
- **Audience:** Compiler, frontend and build-tool maintainers.
- **Implementation boundary:** The PoC implements the shared model, native/C/Starlark entrypoints and native image assembly. Caching, package resolution and concurrent builds are follow-on implementation packages.

## Pipeline and ownership

The compiler accepts a completed typed product model and fixed build inputs. Source-language evaluation happens in a frontend before the common backend runs. Native author programs are trusted build tools; the compiler does not sandbox their access to the build machine.

| Stage | Input | Output | Owner and failure boundary |
|---|---|---|---|
| Evaluate | Source, explicit build options, frontend dependencies | Product model and source map | Frontend; retain source locations, reject incomplete construction |
| Normalize | Product model | Canonical semantic model | `program`; sort unordered entries, preserve indexed bindings |
| Validate | Model, blobs and limits | Validated references, versions and identities | `program`; no output on semantic errors |
| Bind | Validated model, library contracts, runtime profile | Fixed capability bindings | Compiler; reject missing authority, ABI or target |
| Encode | Bound model | Compiled program bytes and digest | `program`; serialization contains no source expressions |
| Assemble | Program and runtime template | Unsigned setup candidate | Image backend; preserve executable code sections |
| Sign | Setup candidate and signing policy | Final setup and provenance | Compiler application; failed signing cannot publish a successful output |

`libs/compiler` owns the shared compiler operations. `apps/compiler` owns command-line IO and signing. `apps/libcompiler` owns the C ABI adapter. The Starlark worker is build-time code with no dependency path into runtime.

The native Zig API accepts `program.Program` values and explicit allocators. The C builder produces the same values through typed entry operations. Frontends must not implement separate semantic validators that accept different programs.

## Public interfaces and errors

The authoring C ABI is owned by `api/c/compiler.h`. Every operation returns a status; error text supplements that status. Builders own copied inputs. Returned byte buffers have explicit destruction, and failed construction leaves the builder usable without partially inserted entries.

Bindings map host-language strings to bounded UTF-8 buffers and reject lengths that cannot be represented by the ABI. Builder and buffer objects are not thread-safe. An individual compilation owns its handles; callers may run separate compilations concurrently once the backend supports that mode.

Diagnostics use a stable stage and error category, the offending object ID, and optional source location. The target machine-readable diagnostic record has `schema`, `stage`, `code`, `message`, `object_id`, `source`, and bounded related locations. Source locations carry a frontend URI, byte offset and optional line/column. They live in a sidecar and never affect program identity.

The initial CLI may render the shared error category as text. Structured diagnostics add an explicit output option; human text is not parsed by SDKs. Future category additions are append-only within a diagnostic version. Unknown categories remain errors to clients.

Cancellation is checked between stages and bounded chunks of IO. A canceled compile deletes its private candidate and leaves any previous published output intact. Signing processes have a timeout and bounded output. Cancellation does not interrupt a published file replacement halfway through.

## Dependencies and locking

The PoC binds local library and asset bytes supplied by the author. It does not implement registry discovery. The package resolver must produce those same inputs before it enters the backend.

The resolver design uses a versioned lockfile containing logical dependency name, exact version, origin, content digest, target requirements and transitive dependency identities. Runtime profile entries include the complete template digest and supported ABI/profile. The compiler resolves no floating dependency during a locked build.

A dependency graph is bounded and acyclic. Duplicate logical dependencies must resolve to the same identity within one namespace or receive explicit distinct names. Aliasing never changes a library's contract identity. Updates are explicit build actions that produce a reviewable lockfile diff.

Resolution can fetch only at build time. Verification checks every downloaded object's digest before caching. Publisher authorization is an independent release policy; a hash proves identity only. Offline locked builds fail with the missing identity and never substitute another cached version.

## Determinism and incremental builds

Native author programs can inspect their environment, so evaluation runs on every invocation by default. Declared source dependencies can support an opt-in frontend cache only when that frontend accounts for its complete observable input set.

The common backend cache key contains compiler semantic version, normalized model digest, all library and asset digests, target/profile identity, runtime-template digest and backend options. Source maps and presentation-only diagnostics are excluded. Limits that change acceptance or output participate in the key.

Cache records store stage schema, key, output digest and bounded output bytes. A cache hit rechecks the digest and required compatibility. Corrupt records are discarded and recomputed; an invalid source program is never accepted because an earlier cached program passed.

Writes use a private temporary file and atomic publish. Per-key coordination prevents partial readers. Concurrent computations may race safely to publish identical content. An implementation may initially serialize compilation; the upgrade point is independent stage jobs with the same immutable keys.

Incremental invalidation follows dependencies: an asset change invalidates binding/encoding/image stages that reference it; a runtime change invalidates image assembly; a source-location change only invalidates diagnostic sidecars. Tests compare cached and clean outputs for every case.

Unsigned image construction is deterministic for fixed inputs and tool versions. Final signing is a separate step because signatures may include nondeterministic metadata. Provenance records both unsigned and final identities rather than claiming byte equality across signing runs.

## Output publication and provenance

The compiler writes to a private candidate beside the destination, validates the carrier, signs it, verifies the platform signature, and atomically publishes the destination. Disk-full, permission, capacity and signing failures preserve the old output.

Provenance records the compiler/frontend versions, lockfile digest, semantic program digest, runtime-template digest, library and artifact digests, target and signing identity. Final setup identity is measured after signing. Secret signing inputs are never written into provenance or logs.

The first image backend uses the reserved Mach-O product section described in [program-image-v1](../spec/program-image-v1.md). PE/ELF and larger carriers implement the same input/output contract. They cannot compile or link a product-specific runtime.

## SDK delivery and verification

| SDK | Native binding | Ownership adaptation | Required conformance |
|---|---|---|---|
| Zig | Native compiler/program API | Caller allocator and explicit errors | Canonical model, reference and binding-order vectors |
| C | `nbc_` ABI | Explicit builder and buffer destruction | Failure atomicity, null/length checks, lifetime and repeated disposal policy |
| Starlark | Go worker using authoring C ABI | Scoped worker ownership | Functions, loops, conditions, module loading and native-equivalent output |
| Python | C ABI binding | Context manager and deterministic release | No dependency on garbage-collection timing |
| TypeScript | Native C ABI adapter | Explicit close with finalizer fallback | UTF-8 boundaries and lossless unsigned integer handling |
| Go | cgo adapter | Scoped release and copied buffers | No retained Go pointers across C calls |
| Rust | C ABI wrapper | RAII and typed status mapping | No borrowed views after owner destruction |

All bindings use the same model vectors and must package a real setup as acceptance. Their package versions are independent of ABI and wire versions. A wrapper must reject an unsupported ABI before exposing a usable builder.

[N2 acceptance](../acceptance-plan-v0.2.md) owns results. [The roadmap](../roadmap-v0.2.md) assigns compiler, resolver, caching and SDK work packages.
