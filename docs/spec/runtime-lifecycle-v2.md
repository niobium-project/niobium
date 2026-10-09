# Runtime lifecycle v2

Status: active contract for the Component product profile in
[ADR-0023](../adr/0023-standard-content-and-component-contracts.md).
The implementation owner is `libs/kernel`. The historical `libs/runtime` module and
runtime lifecycle v1 remain a separate profile; their states and evidence are not
accepted as v2 states or qualification.

Machine-readable shapes are [runtime-state-v2](../../api/schema/runtime-state-v2.schema.json)
and [runtime-plan-v2](../../api/schema/runtime-plan-v2.schema.json). The state schema
also defines ownership and prepared native receipt records in its `$defs` section.
Native validation adds identity, history, aggregate-budget and target-path checks
that JSON Schema cannot express; schema validation alone does not authorize replay.

## Purpose and boundaries

The kernel turns validated desired resources into recoverable native machine effects.
It owns root authorization, concrete resource inventories, transaction decisions,
publication, native metadata receipts, and recovery. A trusted evaluator executes
the signed product graph and capability Components. Capability libraries determine
product policy and desired content; they do not mutate deployment roots.

The public entry point is `kernel.run(Options)`. `Options` passes an allocator, `Io`,
the native platform adapter, an action, named root bindings, the coordinator root ID,
typed input overrides, and trusted evaluation/content-provider callbacks. Product
data is mandatory for every mutating product action, including uninstall. Recovery
and status can operate from authenticated local ownership records and frozen plans.

Actions are `install`, `reconfigure`, `update`, `repair`, `uninstall`, `status`, and
`recover`. Every invocation completes a compatible pending transaction before
performing its requested action. Status therefore may perform recovery.

## Root authority and ownership

`Product.roots` declares named user-scope roots. Signed `Product.state_root` selects
one of them as the durable coordinator. Invocation root bindings must have exactly
the declared IDs and the same coordinator selection. Physical paths are absolute,
bounded UTF-8 paths. Their existing parents are resolved before mutation; duplicate,
aliased, and nested deployment roots are rejected.

The kernel claims only absent or empty roots. A nonempty root without a compatible
ownership record is rejected, including historical v1 installations. Each ownership
record binds the product ID, random installation instance, logical root ID,
coordinator ID, and complete canonical root mapping. All participating records must
agree. The runtime does not adopt a replacement product or guess a missing root map.
Native root owners must match the current installing account.

Roots are locked in canonical path order with nonblocking exclusive locks. Concurrent
maintenance reports `KernelBusy`; it does not retry indefinitely. Existing state and
plan schemas are checked before creating missing lock files. Unknown plan versions
and incompatible state fail before recovery mutations.

## Evaluation and compatibility

The evaluator receives the validated model, current snapshot, resolved typed inputs,
action, selected migration rules, and a private host workspace. This workspace is
not guest filesystem authority. It remains open until container-provider references
have been consumed. Author programs never execute at runtime.

Each plan-producing call returns an explicit desired container set and an optional
private state value. An empty container set removes previously desired resources
from the next published generation. A `none` state clears that call's prior state;
preservation requires returning the previous value explicitly. Every plan-producing
call must return one state result, including `none`. Call ownership, selector, implementation
identity and state version remain persisted independently of those optional private bytes.

State ownership is the tuple `(Call.id, Library.id, interface, function)`. A numeric
state version alone does not establish compatibility. Rebinding a call to a different
library or selector is rejected; cross-selector bridges are outside this profile.
Changing implementation bytes while keeping the state contract and selector stable
is permitted. Changing a state version requires an exact declared `from → to`
migration with its fixed implementation digest. The trusted evaluator's converter
receipts must equal the kernel-selected rules before any plan is persisted. Guest
output cannot assert that a converter ran.

The current converter ABI consumes a prior state value. A version transition from `none`
is rejected even when an edge is declared; the kernel does not invent an input or claim
that a converter ran. A new release with the same call identity, selector and state version
may retain `none`. Optional-input converters require a separately versioned contract.

Release sequences cannot decrease. A model digest change at the same release is
rejected. Reconfiguration and repair use the installed release; update may advance
it. Product-model version changes separately require explicit product upgrade edges.
Typed inputs, call state, implementation identities, and both migration histories are
part of the durable snapshot.

## Desired resources and frozen content

A desired container names its owning call, root, grant, relative prefix, durable
`ContainerRef`, and explicit file/directory access policies. The call must possess
that grant. This slice handles `content.tree` version 1; another primitive's grant
cannot authorize file deployment. Prefixes must remain within the signed grant.
Requested access must be a subset of the corresponding grant ceiling.

The trusted content provider returns a borrowed `content.Body`, which may name a
range in an open file. The kernel streams and hashes its exact bytes into private
durable storage before freezing a plan. Length and digest mismatches fail. Journal
data contains container identities and logical resources, never process handles,
ephemeral descriptors, author programs, or guest continuations.

Canonical containers are parsed with the bounded content parser. Dynamic member
names are accepted within the grant; counts and expanded sizes consume grant and
kernel limits. Shared directories require equal requested policies. File collisions,
file-as-parent conflicts, case aliases, traversal, and unsupported target names are
rejected. Exclusive native creation also detects target filesystem aliases before
the coordinator decides to commit.

Source modes remain content metadata. Deployment access comes exclusively from
[access policy v1](access-policy-v1.md). Files are created privately, written and
verified, then assigned their requested policy and synchronized. Directory policies
are applied after descendants are complete. Native readback must match the policy.

Relative symlinks retain their exact validated logical target bytes in the container
and resource inventory. They must resolve within their container tree. A link has no
independent access grant; the referent's native access applies. The host resolves the
logical target kind before freezing the directory-link creation flag. Windows rejects
unknown target kinds and unsafe native path syntax before capturing content.

Native receipts separately record link identity and exact OS readlink text. Windows
projects logical `/` separators to native `\` separators; it does not collapse dot
components, change case, rename targets, or alter content identity. POSIX uses the
logical bytes unchanged. Cleanup requires identity and the recorded native text to
match. A context that cannot create the requested link reports `KernelUnsupported`
before the commit decision; it does not substitute another kind of link.

## Durable layout and protocol

Each root contains `.niobium-v2/owner.json` and generation directories under
`.niobium-v2/generations/<transaction>/`. Product content lives in each generation's
`data/` directory, separate from kernel receipts. `current` publishes that directory
through a Unix symlink or Windows junction. The coordinator additionally holds
verified container storage, the installation snapshot, one pending plan, and one
commit-decision record.

The version-2 plan freezes the complete root mapping, installation instance,
transaction identity, previous/next snapshots, concrete inventories, and container
identities. The following order is mandatory:

1. Persist and synchronize the complete pending plan.
2. Prepare every root's unpublished generation. Persist its intent, materialize all
   resources, read back content and native access, and persist a prepared receipt
   bound to the pending plan's digest.
3. Persist and synchronize the coordinator decision containing that digest.
4. Publish each prepared generation, synchronizing each root after its pointer
   changes. Uninstall instead removes each current pointer.
5. Persist the next coordinator snapshot, or remove it for uninstall.
6. Clean unchanged retired resources, then remove the pending plan and decision.

No root is activated before all preparations and the coordinator decision are durable.
Cross-root publication is sequential: observers may temporarily see roots from
different releases during activation. The guarantee concerns recovery, not atomic
simultaneous visibility across filesystems. Products needing a single read barrier
must use one published root or an application-level coordinator protocol.

## Failure and recovery

With no durable decision, recovery leaves the previously published roots unchanged
and aborts completed unpublished generations. With a valid decision, recovery checks
all prepared receipts and completes publication of every next root. It then completes
the snapshot and cleanup steps. Recovery does not evaluate Components, resolve new
libraries, fetch replacement dependencies, or rerun authors.

A root already published at the next generation is not rewritten during roll-forward.
Repeated recovery is idempotent. A wrong decision digest, unknown plan ABI, changed
root mapping, unsupported receipt, missing required preparation, or unexpected
publication target produces an explicit error while preserving evidence.

Cleanup removes only inventory entries whose native identity, requested metadata,
and expected contents still match. Unknown files and modified owned files remain in
their retired generation. A durable cleanup intent permits temporarily making owned
read-only directories manageable; retained nonempty directories have their previous
native policy restored. Cleanup never recursively removes a generation.

An interrupted preparation without a completed native receipt is retained privately
for explicit garbage collection. It is never published or guessed to be safe to
delete. Verified container storage and ownership metadata also survive uninstall;
uninstall removes published product resources, not all forensic or cache bytes.
Garbage collection is a separate bounded maintenance operation to be specified.

Known implementation limitation: the qualified Windows 11 Arm64/NTFS run of x64 setup
images under a non-administrator token reported `worker snapshot cleanup: AccessDenied`
after seven successful evaluations. Seven private executable snapshots remained after
uninstall; their bytes matched the delivered setup images. Active installation snapshots
and request files were absent, and the lifecycle assertions passed. The retained files
were not read-only, the owner had full access, and a later native deletion under the same
token succeeded. The exact image-mapping/handle-lifetime cause is not established. The
warning remains visible; no elevation, ACL relaxation, or unproven retry hides it. This
observation describes that execution context, not all Windows systems.

Repair evaluates the same installed release and publishes a fresh desired generation.
It restores missing or changed managed content and access through controlled creation;
modified old content is retained. Unexpected `current` targets are structural drift
and are rejected rather than adopted. Recovery cannot manufacture an old-good state
when external modification had already made the starting installation unhealthy.

## Validation and qualification

`zig build test:kernel` runs the native lifecycle suite and a subprocess witness.
`core-test` and `verify` depend on that step. Evidence is written under
`.evidence/kernel/<UTC>/`, with source/binary provenance and per-command outcomes.

The native suite checks two-root install/reconfiguration/update/uninstall, typed
Unicode inputs, state migration selection, authority and digest rejection, empty
desired sets, unknown plan schemas before mutation, state-owner isolation, controlled
read-only cleanup, v1 adoption rejection, exact symlink targets, and repair.

The crash witness terminates real processes at plan persistence, resource writes,
each root's preparation, the commit decision, each activation, state persistence,
cleanup, and finalization. It verifies actual contents, active generation targets,
typed state, migration history, and repeated recovery. Recovery runs without model,
evaluator, or content-provider callbacks. `N2-KERNEL-RECOVERY-01` requires all roots
to be OLD before the decision or NEW afterward.

macOS native evidence qualifies only the executed host/filesystem context. Windows
and Linux compilation is not native qualification. Their filesystems, junction/link
permissions, directory synchronization, crash recovery, and access readback require
the same suite on real target systems before a support claim.
