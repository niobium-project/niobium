# Product journeys and qualification work packages

This design connects product requirements to the mechanisms in
[ADR-0023](../adr/0023-standard-content-and-component-contracts.md) and the
[feature catalog](../feature-coverage.md). The scenarios are public, anonymized
design cases. They do not claim compatibility with a particular producer's
installer or completion of the full product experience.

The current slices are versioned content containers, portable access policy,
typed authoring/Component calls and owned-root maintenance. A component, SDK or
workload is a product concept. It may select several artifacts, share immutable
content with another selection, and produce several desired resources. Neither
component count nor artifact count is a kernel invariant.

## Shared interface baseline

| Boundary | Owning contract |
|---|---|
| Author programs, type binding and fixed compiler inputs | [Compiler](../spec/compiler-frontends-v2.md), [inputs](../spec/compiler-inputs-v1.md), [author ABI](../spec/authoring-c-abi-v2.md) |
| Content trees, composition and source-independent identity | [Content container](../spec/content-container-v1.md) |
| Library calls, type-only imports, generated content and private state | [Capability library](../spec/capability-library-v2.md) |
| Resource authority and target access | [Access policy](../spec/access-policy-v1.md) |
| Maintenance, receipts, frozen plans and recovery | [Runtime lifecycle](../spec/runtime-lifecycle-v2.md) |
| Precompiled runtimes and delivered native bytes | [Setup image](../spec/setup-image-v2.md) |

The four host families are content; machine state; authority and ownership;
and execution and maintenance. Product libraries combine these mechanisms and
decide how to respond to their results. Missing primitives and unsupported target
semantics are explicit refusals. Missing product prerequisites are observations
for product policy, not a universal instruction to download, elevate or adopt them.

## PJ-01: Optional SDK modules and workloads

A developer installs a base toolchain and optionally adds headers, language SDKs,
debug symbols, examples and an IDE integration. A workload names a product-owned
set of these choices; it is not a new kernel resource kind.

The author program fixes the available libraries, artifacts and grants. At
runtime, typed user input and library policy compute the desired content and
private selection state. Several archives may contribute to one selected module;
a shared immutable artifact may serve multiple modules. A disabled optional
module emits no owned resources for that selection.

Acceptance must cover base-only, every optional module, workload expansion,
conflicts, missing required rules and reconfiguration. An incompatible library
or target must fail before mutation. Disabling an option must not remove another
module's resources or external shared dependencies. Dependency solving, workload
catalogs and selection explanation remain product/preset work.

- FC links: FC-MOD-03, FC-MOD-04, FC-MOD-05, FC-LIF-03, FC-UX-02, FC-ADM-03.
- Owner: product-composition/stdlib maintainer, with preset authors.
- Dependencies: CORE-01, CORE-02, CORE-05 and CORE-06 from the roadmap.
- Current slice: typed optional inputs and library-selected desired resources.
- Remaining contract: workload expansion, dependency/conflict rules and stable selection migration.

## PJ-02: Compose several artifacts into a native content tree

A product combines a platform runtime, architecture-specific executable, shared
libraries, headers and a product overlay. The result includes ordinary files,
empty directories, executable members and relative symbolic links. Relocation
or generated configuration belongs to a declared derivation, not an implicit
extraction hook.

Build-time transformations preserve source provenance and produce a distinct
logical content identity. Duplicate destinations, incompatible kinds, unsafe
links and target-name collisions fail explicitly. Producer tools perform native
binary relocation before the resulting bytes are locked. A runtime derivation
needs fixed inputs, bounded output and an available host mechanism; the present
worker does not expose ambient file or process access.

The mixed executable/data recipe in the [Component SDK guide](../development/component-library-sdk.md#deploy-executables-and-data-with-different-access)
uses separate references with explicit access policies. Source tar RWX bits do
not authorize deployment permissions. A future per-entry policy extension must
retain bounds, ownership, native receipts and crash recovery.

- FC links: FC-PKG-01, FC-PKG-02, FC-PKG-03, FC-PKG-04, FC-PKG-05, FC-OS-01, FC-COMP-01.
- Owner: content/toolchain maintainer; product adapters own producer-specific transforms.
- Dependencies: CORE-03, CORE-04 and compiler input locking.
- Negative vectors: traversal, duplicate path, symlink cycle/escape, conflicting overlays, unsupported metadata and source mutation during capture.
- Remaining contract: producer adapters and richer native metadata require separate qualification.

## PJ-03: Generate toolchain configuration through typed library composition

One fixed library selects a declared content reference. A second independent
library consumes that typed result, a machine observation, user options and prior
state to generate a toolchain environment description. The host validates and
freezes the generated tree and mints its identity. A guest does not choose its own
write authority or certify the digest of bytes it has not persisted.

The official files library's `select-content` is a pure identity choice; it does
not acquire or verify content. Reference resolution and actual content use retain
their host checks. The generated description file is not a global PATH or registry
integration. Those need separate machine-state primitives and ownership receipts.

- FC links: FC-CUS-07, FC-MOD-06, FC-PKG-04, FC-OS-07, FC-DX-06.
- Owner: stdlib/product-library maintainer; evaluator owns type-safe dependency execution.
- Dependencies: CORE-02, CORE-03, CORE-05 and CORE-06.
- Acceptance: changing the selected reference or input changes the computed file; undeclared roots/grants, wrong types, cycles and missing facts fail without partial effects.
- Current slice: standard WIT calls, prebound facts, reference selection and generated content. Global environment integration remains planned.

## PJ-04: Detect a shared prerequisite without adopting it

A product finds an existing compiler, runtime or SDK that another installer or
administrator owns. Detection reports facts and uncertainty. It does not create
ownership receipts for that installation, silently repair it or authorize its
removal.

The product may accept the prerequisite, offer its own private copy, explain a
missing dependency, or decline installation. Its policy must distinguish absent,
present, incompatible, unreadable and unsupported observations. Additional
filesystem, registry, package-manager and version observations need explicit
bounded contracts beyond the current OS/architecture fact slice.

- FC links: FC-MOD-08, FC-MOD-10, FC-COMP-07, FC-ADM-10, FC-SEC-08.
- Owner: machine-state primitive maintainer and product policy author.
- Dependencies: observation schema/provenance, target adapters and authority contracts.
- Negative vectors: misleading PATH entries, permission denial, stale observations, unowned symlink targets and conflicting package managers.
- Acceptance: install, update and uninstall leave the independently owned prerequisite unchanged. Ownership transfer requires a separate explicit bridge contract.

## PJ-05: Reconfigure with the same setup program

The user reruns the same delivered setup and changes optional selections or
configuration. The runtime evaluates its fixed library graph with new typed
inputs and compatible installed state. It does not rerun Starlark or rebuild the
native runtime.

The new desired set is reconciled against durable ownership. Removed selections
remove their owned resources; unrelated files remain protected. The same
transaction rules apply as installation and update. Selection metadata and
resource state commit together, and recovery uses the frozen plan if libraries
are subsequently unavailable.

- FC links: FC-LIF-03, FC-TXN-01, FC-TXN-03, FC-ADM-03, FC-UX-06.
- Owner: lifecycle maintainer for mechanisms, product/preset author for selection policy.
- Dependencies: CORE-06 and explicit stable call/state identities.
- Negative vectors: lost worker, canceled evaluation, crash after staging/commit, unknown plan version, user-added files and changed access policy.
- Current slice: reconfiguration mechanism and typed input overrides. GUI selection and enterprise configuration formats remain separate work.

## PJ-06: Coexisting toolchain versions

A developer keeps two SDK versions or channels installed for different projects.
Each instance has explicit roots, state, libraries and ownership. A product-owned
selector may choose a preferred version; it must not merge the installations into
one implicit global state.

Content reuse does not imply shared mutable ownership. A PATH entry, shim or
system registration has its own machine-state identity and restoration rules.
Changing a selector must preserve the other instance and respect running
applications. Retention and cleanup policy belong to the product; recovery still
protects every object needed by an unfinished transaction.

- FC links: FC-MOD-09, FC-OS-07, FC-LIF-08, FC-TXN-05, FC-TXN-09, FC-COMP-10.
- Owner: coexistence preset/stdlib maintainer and machine-state adapters.
- Dependencies: instance naming contract, controlled integrations and multi-instance tests.
- Negative vectors: overlapping roots, competing selectors, stale leases, removal of the active version and locked executable files.
- Remaining work: full coexistence policy, shared selector ownership and platform qualification.

## PJ-07: Upgrade, bridge and remove owned state

A second release changes a library's private state model and desired resources.
It declares an explicit converter from the installed state version, with fixed
implementation identity. A fresh second-release installation starts in the new
state model; it must not rely on an old-state migration to initialize correctly.

The reference consumer has two distinct Component artifacts with one stable
interface and call lineage. Revision two initializes `v2` state on a fresh install
and refuses unconverted revision-one state. The host owns migration eligibility,
freezing and commit. The guest computes state; it does not edit the journal.

- FC links: FC-MOD-02, FC-LIF-04, FC-LIF-06, FC-TXN-03, FC-DX-10, FC-COMP-05.
- Owner: migration/lifecycle maintainer and product library author.
- Dependencies: fixed migration identity, compatible state type and runtime recovery contracts.
- Acceptance: fresh v2, v1-to-v2, missing path, unknown version, changed converter digest, repeated recovery and uninstall after recovery.
- Remaining work: multi-hop paths, bridge-release orchestration and explicit adoption of legacy installer ownership. Discovery alone cannot authorize that adoption.

## PJ-08: Wrap an existing native application

An application producer supplies a native tree or language bundle. A build-time
adapter maps it into canonical content, retains the necessary relationships and
records transformations. The installer model is independent of whether the
producer used a native compiler, Qt, Electron or a Python bundler.

The wrapping product must name the update owner and avoid competing maintenance
systems. It must qualify the exact final native application and setup bytes,
including required symlinks, executable access and platform trust metadata.
Basic file/tree support does not establish complete application-bundle metadata,
Developer ID, notarization, MSI/MSIX semantics or package-manager adoption.

- FC links: FC-PKG-08, FC-PKG-09, FC-COMP-01 through FC-COMP-10, FC-SEC-04, FC-QA-09.
- Owner: producer adapter/preset maintainer and release engineering.
- Dependencies: CORE-03, CORE-04, CORE-07 and per-producer qualification fixtures.
- Negative vectors: signature invalidation, omitted side files, changed link targets, unsupported metadata and two active update owners.
- Remaining work: one independently reviewable adapter and actual final-byte evidence per claimed producer/target combination.

## PJ-09: Choose installer components and Niobium build profiles

A product selects a published runtime profile and a fixed set of libraries. The
Niobium project can build different runtime profiles for native mechanisms and
frontends. Product assembly consumes those complete precompiled binaries;
selection does not relink a product-specific runtime.

An SDK or preset can hide routine authoring detail while emitting the common
model. It cannot add OS authority by installing a Wasm library. A new native
primitive requires a runtime implementation, versioned contract, permissions and
recovery behavior. A new resource-free WIT type package does not require a native
runtime release.

- FC links: FC-DX-01, FC-CUS-03, FC-CUS-07, FC-CUS-08, FC-SDK-06, FC-QA-07.
- Owner: compiler/runtime-profile maintainer and SDK/preset maintainers.
- Dependencies: CORE-01, CORE-02, CORE-05, CORE-07 and published runtime metadata.
- Negative vectors: wrong target, missing primitive, altered library/runtime bytes, unpinned build tool and source-dependent assembly.
- Current slice: native Zig/C/Starlark authors, standard Components and fixed runtime packaging. Complete language distributions and profile/preset catalogs remain planned.

## Acceptance and parallel handoff

The current foundation commands are:

```sh
zig build test:author test:component test:core --cache-poison=disallowed
zig build core:e2e --cache-poison=disallowed
```

These are entry points for the slices described above. Their presence is not a
PASS for a complete journey. Real-OS permission behavior, final-byte delivery,
crash outcomes and unsupported cases need their own recorded scenario vectors.
No new journey completion is asserted by this document.

Each follow-on package must supply a public interface baseline, named owner,
prerequisites, deliverables, non-goals, exact command/vector and evidence path.
A new command must enter the build graph and `verify` before its cases can qualify
a feature. Use the source snapshot, tool versions, runtime profile, library and
content identities, actual target/scope and final delivered digest in evidence.
A fault case must state the expected OLD/NEW outcome and verify actual resources,
state and repeated recovery, not only an exit code.

Workload/preset, producer-adapter, coexistence, machine-observation/integration,
bridge-migration and language-SDK packages can proceed independently after their
shared interfaces are fixed. They must not silently extend the kernel's four
families or infer privilege, ownership or compatibility from successful detection.
