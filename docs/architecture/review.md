# Architecture and maintenance review

The compiler/runtime graph separates build-time authoring, immutable product
assembly, Component execution and host-owned mutation. This is a useful foundation
for extending policy through libraries without extending kernel schema enums.
The draft still needs narrower shared interfaces and explicit component integration
boundaries. This review recommends follow-up changes; it does not implement them.

## Prioritized findings

| Priority | Finding and evidence | Recommendation |
|---|---|---|
| High | `libs/contracts/root.zig` exports unrelated TUF, IPC, UI, installation and platform integration contracts through one module. `build/modules.zig` gives broad access to this module. | Give each contract a semantic owner as actual runtime integrations emerge; keep limits and strict decoding small. Avoid another generic shared directory. |
| High | `build/modules.zig` allows process spawn for whole `apps/`, `tests/`, `tools/`, platform and privilege directories, and pointer casts for whole native bridge directories. | Restrict exceptions to concrete process/ABI owners when those paths change, retaining a reason and negative gate for each exception. |
| High | Independent trust, extraction, platform/helper and UI components have tests but no current runtime connection. Their public types can be mistaken for available installer features. | Require an explicit adapter, authority contract, failure vectors and final installer acceptance before documenting an integration as available. |
| Medium | The module graph uses both numerical `Layer` values and execution `Phase`. Current runtime transitive guards provide stronger isolation than a layer name alone. | Treat execution phase and declared imports as the primary boundary; review remaining broad imports before introducing new abstractions. |
| Medium | `libs/ui/screens` retains a presentation model separate from current typed kernel state. `apps/ui-gallery` demonstrates rendering, not installer lifecycle. | Design one typed UI/runtime adapter when UI delivery is undertaken, with CLI-equivalent operations and accessible semantics. |
| Medium | Shared test-system records qualify earlier source snapshots, while current product records qualify different contracts and bytes. | Preserve producer/source identities and test negative evidence validation; avoid transferring a component PASS to a product claim. |

## Directory and artifact ownership

[Repository layout](../development/repository-layout.md#apps-and-delivered-names)
owns app and artifact names. Compiler frontends and inspector worker belong to
one compiler product. SDK delivery is a separate user-consumable component;
runtime publication is independent of product assembly. UI gallery and docs are
explicit products rather than spare entrypoints. Libraries remain their semantic
implementation owners.

## Validation limits

This is a source and build-contract review. It does not establish performance,
real OS support, machine scope or final signing qualification. Current execution
results and exact limitations belong to [acceptance](../acceptance-plan.md).

## Package validation observations

Extracted C and Zig SDK consumers and the macOS runtime archive were exercised
on the dirty source snapshot recorded in
`.evidence/sdk-consumption/2026-10-09T12-34-01Z/metadata.json` and
`.evidence/runtime-package/2026-10-09T12-36-13Z/metadata.json`.
This closes the observed checkout-only packaging gap for those packages. It does
not establish additional-language SDKs, another target's consumer link, a full
installer matrix or release-signing qualification.
