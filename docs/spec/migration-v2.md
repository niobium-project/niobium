# Compatibility and migration v2

- **Status:** Normative standard-core contract.
- **Decision:** [ADR-0023](../adr/0023-standard-content-and-component-contracts.md).
- **Owners:** Compiler/product, capability library and runtime lifecycle maintainers.
- **Evidence:** [Acceptance v0.3](../acceptance-plan-v0.3.md).

## Independent versions

| Version or identity | Meaning |
|---|---|
| Authoring C ABI | Builder/handle/buffer calling contract, independent of guest ABI |
| Compiled product schema and runtime ABI | Runtime can decode and execute the fixed graph |
| Native image and measurement profiles | Assembler/runtime agree on carrier layout and byte binding |
| Component profile and WIT contract | Enabled execution features and selected function/value types |
| Library publication version and digest | Exact implementation selected by the product |
| Product `model_version` | Product model compatibility declared by the author |
| Call `state_version` | Concrete library-owned private-state representation |
| Host snapshot/plan schema and host ABI | Durable execution and recovery representation |
| `release_sequence` | Monotonic product publication order |

The pre-release reset permits explicit refusal of old formats. It does not permit
new releases to reinterpret installed data silently. No old manifest, author ABI
or Core Wasm state importer is required by this profile. Unknown durable formats
are refused before mutation and remain available to their owning runtime.

## Product and call transitions

Product model changes require a declared direct `from`/`to` edge to the published
model version. This edge authorizes the model transition; product libraries own
selection/layout conversion. It does not claim a separate host-invented model
converter. A missing edge refuses the update.

Every plan-producing call owns a stable call ID, library ID, interface/function
selector and state version, even when private state is absent. An existing call
cannot silently rebind to another library or selector. A new call starts without
private state. Explicit cross-library bridges need a separate contract.

Keeping a state version declares implementation compatibility with that state
representation. A changed version requires one applicable direct migration rule.
The rule fixes its ID, source/target versions, library, exported interface/function
and implementation digest. The compiler validates the fixed export and target
state type. The trusted evaluator executes the selected converter before planning
and returns a receipt for that exact rule.

The current converter ABI consumes a concrete value. A version change from absent
private state is refused even if a rule is declared; the host does not invent an
input or claim that a converter ran. Libraries that need a typed empty state can
persist one explicitly. Optional-state converter support requires its own versioned
interface and vectors.

Runtime inputs are independently checked against compiled WIT types. A migrated
product cannot bypass those types with an unused input or an incompatible value
retained from an earlier release.

## Immutable history

Applied call migration receipts retain the full rule identity, including the
implementation digest. Product migration history retains its identified edges.
Redeclaring an applied ID with a different definition is refused before guest
execution or content publication, including when no new conversion is selected.
Retired declarations need not remain in the new product; retained history is not
rewritten or discarded when a call clears state.

A compiler can check only history supplied as an input. The runtime additionally
checks the installation's durable history. Publisher catalog immutability and
remote upgrade authorization belong to the distribution/trust contract.

Fresh installation of a later release must initialize that release's declared
state representation. A successful 1-to-2 conversion alone does not prove that
fresh release 2 behaves correctly; both paths are acceptance cases.

## Atomicity and recovery

Migration has no direct machine effects. The host validates converted state,
normalizes desired resources and freezes them into the same plan. It prepares all
roots before a single coordinator decision. A failure before that decision retains
OLD; recovery after it completes NEW with matching resources, versions and history.
The [lifecycle contract](runtime-lifecycle-v2.md) owns the detailed boundaries.

Recovery replays durable host operations and content. It never reruns the converter,
resolves another library or evaluates author code. A runtime missing the required
plan format or primitive implementation must refuse before modifying that plan.

## Further compatibility work

Multi-edge paths, bridge releases, framework-format converters and state transfer
between call/library lineages remain explicit work packages. Each needs bounded
path selection, ambiguity refusal, fixed dependencies, immutable history and a
crash matrix. Core must not infer a bridge from display versions or acquire an
undeclared intermediate release. See [roadmap v0.3](../roadmap-v0.3.md).
