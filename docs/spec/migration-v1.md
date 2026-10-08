# Compatibility and migration v1

- **Status:** Normative target; implementation evidence is in [N2 acceptance](../acceptance-plan-v0.2.md).
- **Decision:** [ADR-0022](../adr/0022-installer-dsl-and-aot-toolchain.md).

## Version ownership

| Version | Owner | Compatibility meaning |
|---|---|---|
| Program `schema` | Program image protocol | Runtime can decode the published program |
| `runtime_abi` | Host protocol | Runtime provides the required host interfaces |
| Library `abi` | Capability library protocol | Host and guest agree on calling conventions |
| Product `model_version` | Product author | Installed product model has the expected meaning |
| Instance `state_version` | Capability implementation | Guest can interpret its persisted state |
| Host plan/state format | Runtime lifecycle | Recovery can interpret durable records |
| `release_sequence` | Product release authorization | Release ordering, separate from model shape |

An application version or database version does not substitute for any of these
values. The pre-release architecture reset requires no import bridge from the old
Niobium v1 formats. Public formats introduced under this contract require explicit
compatibility behavior on subsequent changes.

## Product-declared transitions

The product program declares permitted model transitions as identified `from` and
`to` edges. Each library instance separately declares its state transitions. The
compiler checks IDs, forward version movement and unique source versions.
Runtime validates the applicable path against the actual installed versions.

Persisted state belongs to an instance within its library identity. The initial
profile rejects rebinding an existing instance to a different library ID, even
when the state versions are equal or a version transition is declared. A new
instance ID starts with empty state. Cross-library state transfer requires a
separate future contract.

A library implementation digest may change while its library ID and state version
remain stable. Keeping that version declares that the new implementation can read
the existing state format; an incompatible format requires a declared migration.
The guest ABI version describes calling conventions, not state compatibility.

Equal versions within the same library identity require no migration. Different
versions require one direct declared edge to the target version in
the initial executable profile. A missing path is a refusal before mutation. Neither
display-version ordering nor a newly default-selected component creates a path.
Version-skipping is allowed only when the declared edge explicitly covers it.

The initial wire contract supports direct transitions and explicit refusal
through absent edges. Every edge targets the containing product or instance
version. Chained transition orchestration belongs to the follow-on compatibility
work package. Automatic acquisition of bridge releases is outside the
first executable profile. The product owns any bridge requirement; the later
bridge contract must name the exact trusted intermediary and revalidate every
leg. Core must not choose a bridge by guessing compatible application versions.

Product model edges authorize transition to the published target model. Product
libraries own any selection and resource-identity conversion; the initial edge
record does not execute a separate model converter. Library state
conversion executes the frozen guest's `nb_migrate_v1` before planning. The
runtime cannot manufacture a valid converter from an ID rename or a version
number alone.

## Durable migration record

Migration IDs identify immutable rules within a product or library lineage.
Persisted receipts use owner `@product` for product-model transitions and the
instance ID for library state. The discriminator cannot collide with instance
IDs because their alphabet excludes `@`. A
release fixes the associated implementation digest. A changed rule needs a new
identity; reusing an applied ID with different bytes is rejected when compared
with retained history. The compiler can verify published history only when that
history is supplied as an authenticated input.

Planning records the source and target versions, migration IDs and implementation
digests, selected path, old state identity and resulting state bytes. Migration
evaluation has no direct machine effects. Its output enters the same durable plan
as resource changes.

Crash recovery follows the host plan rather than rerunning migrations. Before
commit both deployment and state remain OLD; after commit both reach NEW.
Execution failure, fuel exhaustion or an invalid resulting state leaves no
partially accepted transition.

## Framework compatibility

A runtime must either decode a persisted host format, migrate it through a
declared framework converter, or reject it before mutation. A framework converter
is versioned framework code and has recovery tests. It is independent of the
product's promise to support an application upgrade.

Unknown journal or plan schemas preserve the durable files and report the required
compatible runtime. The runtime never truncates unknown data merely to make a new
install proceed. Changes to recovery data need tests using prior-format fixtures.

## Acceptance

- `N2-MIG-01`: declared product model 1-to-2 transition succeeds; absent/ambiguous paths fail before mutation.
- `N2-MIG-01`: library state 1-to-2 conversion feeds planning; failure preserves old state.
- `N2-COMPAT-01`: applied migration identity/digest mismatches and unsupported host formats are refused.
- `N2-BRIDGE-01`: product-declared bridge acquisition validates every leg and never bypasses release trust.
- `N2-REC-01`: crash points never leave the model/state version ahead of active resources.
