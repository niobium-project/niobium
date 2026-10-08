# Niobium glossary

Canonical terms for the installation and distribution language defined by [ADR-0022](docs/adr/0022-installer-dsl-and-aot-toolchain.md). Historical v1 documents retain their local terminology.

## Authoring and distribution

**Author program**: Build-time source that constructs a product model through a language SDK or Starlark.
_Avoid_: installer script, manifest logic.

**Product model**: The typed description of a product's inputs, resources, capability bindings and compatibility policy.

**Compiler**: The toolchain that validates a product model, fixes its dependencies and produces a setup.

**Compiled program**: The immutable product representation consumed by the runtime.
_Avoid_: author manifest.

**Runtime**: The independently built execution host for compiled programs and capability libraries.

**Runtime profile**: A published runtime's supported host contracts, target and resource limits.

**Setup**: The final product installer containing a runtime, compiled program and fixed dependencies.

**Artifact**: Immutable product content identified independently from the runtime and capability libraries.

**Release**: A product publication with a fixed program and dependency set.

**Release sequence**: Product release ordering independent of display version and state model versions.

## Capabilities and policy

**Capability contract**: The interface and lifecycle obligations for an installation or distribution capability.

**Capability library**: An implementation of one or more capability contracts, bound into a product release.
_Avoid_: native plugin, runtime extension discovery.

**Capability instance**: One bound use of a library with its own inputs, resources and state.

**Host primitive**: A versioned mechanism with explicit authority and effects provided by the runtime.

**Standard library (stdlib)**: Official capability and authoring libraries using the same public contracts as product libraries.

**Preset**: A build-time composition of libraries and product conventions.

**Template**: A starting author project that a product developer can edit.

**Component**: A product-defined selectable deployment unit.

**Component family**: A product-defined group with common coexistence and selection rules.

**Workload**: A product-defined selection of components for a user task.

**Channel**: A product distribution policy that selects an authorized release.

## Deployment and compatibility

**Resource**: A stable, owned entity whose desired state is managed through a capability.

**Deployment plan**: A result computed from the compiled program, selected inputs and observed machine state.

**Frozen plan**: A durable deployment plan whose contents and host operations are fixed for transaction execution and recovery.

**Transaction**: An attempt to move owned resources and state from one consistent installation to another.

**Active**: The committed installation visible to product consumers.

**Recovery**: Reconciliation of interrupted host operations to the old or new consistent installation.

**Scope**: The authority boundary within which an installation manages resources.

**Migration**: An explicitly identified conversion between compatible versions of product or capability state.

**Bridge release**: A product-declared intermediate release required by an upgrade path.

**App Bootstrap**: A product activation protocol for application-owned initialization and business migration.

**Maintainer**: A retained runtime capable of managing an installed product and its recovery data.
