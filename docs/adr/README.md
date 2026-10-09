# ADR index

Numbers are assigned once and never reused or renumbered. Template: title `# ADR-NNNN: ...`, fields **Status** and **Date** (plus `Supersedes` / `Superseded by` / `Amends` / `Amended by` when they apply), sections `Context` -> `Decision` -> `Consequences`. Statuses, and how to replace or amend a decision: [docs-management](../development/docs-management.md#adrs).

| Number | Title | Status |
|---|---|---|
| [0001](0001-repository-baseline-and-zig-only-toolchain.md) | Repository baseline and Zig-only toolchain | Accepted; amended by 0021, 0022, 0023 and 0027 |
| [0004](0004-tuf-profile.md) | Installer TUF profile v1 | Accepted; amended by 0022 |
| [0008](0008-shared-software-renderer.md) | Shared software renderer | Accepted; amended by 0022 |
| [0009](0009-zon-screen-ir-and-tokens-codegen.md) | ZON screen IR and tokens code generation | Accepted |
| [0010](0010-x11-now-wayland-deferred.md) | X11 on Linux first, Wayland deferred | Accepted |
| [0011](0011-third-party-fetch.md) | Versioned third-party fetch and patches | Accepted |
| [0012](0012-formal-methods-deferred.md) | Formal models deferred | Accepted |
| 0013 | Not assigned: merged into 0011 before the first public commit | - |
| [0014](0014-tier-based-platform-support.md) | Tier-based platform support | Accepted |
| [0015](0015-node-toolchain-for-user-docs.md) | Node.js toolchain for the user documentation site | Accepted; amended by 0017 |
| [0016](0016-documentation-lifecycle.md) | Documentation lifecycle | Accepted |
| [0017](0017-chinese-user-documentation.md) | Chinese user documentation | Accepted |
| [0020](0020-distribution-delivery-milestones.md) | Distribution delivery milestones | Accepted; amended by 0022 |
| [0021](0021-ci-evidence-transport.md) | CI evidence transport | Accepted |
| [0022](0022-installer-dsl-and-aot-toolchain.md) | Installer DSL and AOT toolchain | Accepted; amended by 0023 |
| [0023](0023-standard-content-and-component-contracts.md) | Standard content, component contracts and cross-host compilation | Accepted; amended by 0024, 0025 and 0026 |
| [0024](0024-native-runtime-dependency-qualification.md) | Native runtime dependency qualification | Accepted; amended by 0025 |
| [0025](0025-baseline-cpu-runtime-publication.md) | Baseline CPU targets for runtime publication | Accepted |
| [0026](0026-pinned-rust-component-wasm.md) | Pinned Rust for Component Wasm | Accepted |
| [0027](0027-zig-provisioned-host-tools.md) | Zig-provisioned Rust and Go for build and test | Accepted |

Numbers 0002, 0003, 0005, 0006, 0007, 0018 and 0019 are retired; their records
remain in Git history and their numbers must not be reused.
