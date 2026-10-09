# Niobium development conventions

Niobium is an installation and distribution DSL with an AOT compiler, a precompiled native runtime and host-controlled Wasm capability libraries ([ADR-0022](docs/adr/0022-installer-dsl-and-aot-toolchain.md)). This file holds the repository's hard constraints, forbidden patterns and review gates. Procedures live in `.agents/skills/`; contracts and trade-offs live in `docs/spec/` and `docs/adr/`. A requirement is stated once and linked, never copied in full to several places.

## 1. Rule precedence and sources of truth

Current explicit user instruction > this file > accepted ADRs > active versioned specs (listed in `docs/README.md`) > descriptive architecture documentation > general engineering practice. When you find a conflict, pause the affected change and record the conflict and a proposed ADR first; never change architectural semantics silently through code.

- `docs/source/` is the original architecture input, a read-only archive; current decisions are the ADRs and specs.
- `docs/implementation/YYYY-MM-DD-*.md` are optional implementation traces; they go stale and are not a source of truth.
- How each document kind changes and retires, including replacing an ADR: [docs-management](docs/development/docs-management.md) ([ADR-0016](docs/adr/0016-documentation-lifecycle.md)).
- Docs, skills, code comments and commit summaries are written in English. The only Chinese documents are [README.zh.md](README.zh.md), which must track [README.md](README.md), and the user site's Chinese pages, which mirror its English pages ([ADR-0017](docs/adr/0017-chinese-user-documentation.md)). APIs, code identifiers and JSON fields are English.
- The repository is public. It must not reference internal or private hosts, mirrors or internal organization namespaces (groups, repositories); `tools/check-docs` enforces part of this. Naming the author's employer in the project background ([About the project](apps/user-docs/src/content/docs/about.md)) is allowed.

## 2. Inviolable principles

[ADR-0022](docs/adr/0022-installer-dsl-and-aot-toolchain.md) owns the architecture direction, amended by [ADR-0023](docs/adr/0023-standard-content-and-component-contracts.md) for standard content, WIT and cross-host compilation, and by [ADR-0026](docs/adr/0026-pinned-rust-component-wasm.md) for the Component implementation language. These rules apply to every new feature:

1. **Author programs execute at build time.** Native-language SDKs and Starlark construct the same typed product model. Serialized program data is a compiler output.
2. **The compiler packages a complete precompiled runtime.** Product builds must preserve the template input and executable code sections, and must not relink or execute a target runtime. The host-independent image assembler and final signer change only the output image.
3. **Capability contracts bind libraries.** Official and product/third-party Wasm Components use the same WIT and upstream Canonical ABI implementation. No ambient WASI, filesystem, network, process or elevation authority is granted. The retained Core Wasm v1 ABI keeps its historical scope. Wasmtime, `wit-bindgen`, `wasm-tools` and libraries maintained in this repository stay on the pinned Rust implementations until a competing alternative is qualified ([ADR-0026](docs/adr/0026-pinned-rust-component-wasm.md)).
4. **Core provides mechanisms.** Product distribution, component selection, coexistence, channels and layout policies belong to libraries, presets and templates.
5. **Machine effects are transactional.** The host validates and freezes outputs before mutation; recovery uses durable plans and reaches only old-good or new-good.
6. **Compatibility is explicit.** Product migration/bridge policy belongs to the product. Framework and library state have independent versioned compatibility contracts.
7. **Release bytes are fixed.** Runtime, program, libraries and artifacts have distinct identities. Final signing and qualification apply to the delivered bytes.
8. **Content and authority are distinct.** Logical content uses the versioned POSIX pax profile. Archive modes do not grant access; explicit host access policies control installed resources. Unsupported native semantics must be rejected rather than approximated.

The pre-release reset does not require compatibility with old manifest/API/state formats. It does not waive compatibility checks for new product releases. Retained manifest/engine v1 specs and N1 product evidence describe the legacy implementation. Shared test-system evidence retains its own stated scope.

## 3. Repository boundaries and dependency direction

```text
apps/ process assembly (compiler, runtime, language/ABI adapters, legacy apps), no business logic
libs/ implementation; one owner directory per module
api/ machine-readable contracts (JSON Schema, C header, versioned WIT)
tools/ checks, generators and gates written in Zig
tests/ cross-module e2e, conformance, golden, fixtures
build/ the single source of truth for the build graph: modules.zig declares modules and allowed imports
third_party/ upstream sources pinned by deps.zon + PROVENANCE + patches + bindings; upstream files are fetched at build time, not committed
```

The target dependency direction is `apps → compiler/runtime → program/capability contracts → host/platform → core`. Build-time frontends never enter runtime. Capability libraries cannot import native host implementation modules. Standard-library and preset policy must not become global core enums or schema fields. Current module registrations and allowed imports are owned by `build/modules.zig`; [module boundaries](docs/architecture/module-boundaries.md) records the transition.

`ui/core` and `ui/kit` remain pure. The current standard UI uses contracts at its engine boundary; extending this UI does not authorize changes to the runtime/library ABI.
A module may only `@import` the modules `build/modules.zig` hands it, which the compiler enforces; `tools/check` additionally rejects relative `@import("../...")` across module directories. Do not create `shared/`, `common/`, `utils/` or `helpers/` grab-bag directories.

## 4. Starting a task

1. Read this file, then [docs/README.md](docs/README.md) to locate the relevant specs and ADRs.
2. For any design, implementation, debugging or acceptance work: read [.agents/skills/niobium-development/SKILL.md](.agents/skills/niobium-development/SKILL.md).
3. For writing or changing Zig code: read the `zig-0.17` and `zig-tiger-style` skills (under `.agents/skills/`); this repository's deviations are in section 5.
4. For installer UI, tokens, components and screens: read [niobium-ui-kit](.agents/skills/niobium-ui-kit/SKILL.md) and [niobium-native-look](.agents/skills/niobium-native-look/SKILL.md).
5. For a capability library, host primitive or platform backend: read [niobium-platform-capability](.agents/skills/niobium-platform-capability/SKILL.md). Which targets the project builds, gates and releases on is decided by the tiers in [ADR-0014](docs/adr/0014-tier-based-platform-support.md).
6. For review, security or boundary-related changes: review against the [review-niobium](.agents/skills/review-niobium/SKILL.md) checklist.
7. For technical prose, read the installed `technical-writing` skill; for terminology or decisions also read `domain-modeling`.
8. External GUI skills (`apple-hig`, `winui-app`, `gtk-ui-ux-engineer`) only provide design values and checklists; the SwiftUI/AppKit controls, WinUI 3/XAML/C#/MSIX and GTK/libadwaita they recommend do not change [ADR-0008](docs/adr/0008-shared-software-renderer.md).
9. For the build graph, step names, or host Rust/Go pins: read [niobium-build](.agents/skills/niobium-build/SKILL.md). The step catalog lives in [tooling](docs/development/tooling-and-rules.md).
10. For git hooks: read [niobium-build](.agents/skills/niobium-build/SKILL.md). Hook behavior stays in the zig build steps.

## 5. Zig rules

- Zig is pinned to 0.17.0 (`minimum_zig_version` in `build.zig.zon`). Use the `std.process.Init` main and an explicitly passed `std.Io`.
- Pass `Allocator` and `Io` explicitly; in `libs/`, container-level mutable `var`, `std.heap.page_allocator` and `c_allocator` are forbidden.
- Public functions use explicit error sets; `anyerror` is forbidden. Expected failures (IO, parsing, network, disk full, file locks, UAC cancel, timeouts) are always errors, never panics; panic/assert only express programmer invariants.
- Use `std.math.cast` for untrusted integers, not `@intCast`/`@truncate`; on untrusted data, `catch unreachable`, `orelse unreachable`, empty `catch {}` and `_ = call()` discards are forbidden.
- Every loop, queue and retry has a fixed upper bound; input sizes are bounded by `contracts.Limits`.
- The C ABI boundary exposes no Zig structs, allocators, error unions or slices; every `export fn` maps errors to status codes.
- Follow TigerStyle, with these deviations: function names keep Zig std camelCase; function bodies ≤ 70 lines and lines ≤ 100 columns; non-trivial functions in core modules have at least one entry assertion; compound assertions are split.
- `@cImport` was removed in 0.17: C dependencies use hand-written `extern` declarations in `third_party/<lib>/bindings.zig`.
- Release builds are ReleaseSafe; `@setRuntimeSafety(false)` is allowed only in small, fuzzed hot loops on the lint allowlist.

## 6. Tests, acceptance and gates

Test lanes: L0 static (check/lint/schema/size), L1 pure core (VirtualPlatform), L2 faults and security (crash injection, sim, fuzz, malicious input), L3 platform contract, L4 scenario e2e, L5 real OS (vm-smoke). Details: [docs/development/testing-lanes.md](docs/development/testing-lanes.md).

- Crash-injection invariant: after recovery from any kill point, `Active == OLD` or `Active == NEW`, never MIXED.
- No artifact can write outside the staging root through extraction.
- New standard-core evidence uses N2 IDs in [acceptance-plan-v0.3](docs/acceptance-plan-v0.3.md). Prior N2 and N1 records retain their original profiles and cannot establish new contract completion; shared test-system evidence retains its declared scope.
- Acceptance status uses only `PASS`/`FAIL`/`BLOCKED`/`NOT_RUN`/`DEFERRED`; without real evidence, never write "supported" or "passed".
- Compiling, mocks succeeding, screenshots and an agent's own claims do not constitute completion. Evidence goes to `.evidence/<suite>/<UTC>/`.
- Goldens are never updated wholesale: `zig build test:golden -Dupdate=<component>` must name a scope, and the diff is inspected in review.

## 7. Changes, commits and definition of done

- Commit and pull request rules: [Commits and pull requests](docs/development/commits.md).
- Hand-written patches target ≤ 300 net lines; more needs splitting or a stated reason. Hand-written files ≤ 600 lines (generated files, fixtures and third_party excepted).
- Never get a pass by disabling rules, widening ignores, deleting regression cases or updating snapshots wholesale; `// lint-allow(<rule>): <reason>` must state a reason, and the count is reported.
- When the same class of problem appears a second time, it must become a failing check: write the failing case first, then implement.
- Definition of done: implementation, contracts, docs and acceptance IDs are in sync; relevant tests have run; `zig build verify` passes or the blocker is recorded explicitly. The final report states the actual commands, results, what was not run and limitations.

## 8. Repository skills

| Skill | Purpose |
|---|---|
| `niobium-development` | Design → contract → implement → verify → deliver main loop, with the anti-pattern table |
| `niobium-build` | Root `zig build` steps, pinned Rust/Go, and git hooks |
| `niobium-ui-kit` | Installer UI components, tokens, screens and goldens |
| `niobium-native-look` | Map each platform's look and interaction conventions to tokens |
| `niobium-platform-capability` | Contract-first flow and crash pitfalls for new capabilities / platform backends |
| `review-niobium` | Security and boundary review checklist |
| `merge-prs` | Land labeled pull requests onto main as a linear signed history |
| `zig-0.17`, `zig-tiger-style` | External Zig language skills (pinned by `skills-lock.json`) |
| `apple-hig`, `winui-app`, `gtk-ui-ux-engineer` | External platform design references (values and checklists only); sources in [docs/development/tooling-and-rules.md](docs/development/tooling-and-rules.md#external-skills) |
