---
name: niobium-development
description: The main work loop for the Niobium installer framework - design → contract → implement → verify → deliver. Read this skill first for any design, implementation, debugging, bug fix, acceptance, or documentation change, including work on the journal, crash recovery, the privilege helper, or acceptance IDs; it turns the constraints in AGENTS.md into executable steps and links to the detailed rules and anti-pattern table in references/.
---

# Niobium development main loop

AGENTS.md holds the constraints; this skill holds the steps. When the two conflict, AGENTS.md wins, and this skill must be corrected.

| Task | Read |
|---|---|
| Design, architecture change, bug root cause | [references/design-and-debugging.md](references/design-and-debugging.md) |
| Writing Zig code | [references/implementation.md](references/implementation.md), plus the `zig-0.17` and `zig-tiger-style` skills |
| Tests, acceptance status, evidence | [references/acceptance.md](references/acceptance.md) |
| New or replaced ADR, spec, roadmap, or other doc change | [docs-management](../../../docs/development/docs-management.md) |
| Risk scan before design, fix, or review | [references/anti-patterns.md](references/anti-patterns.md), only the rows that apply |
| UI, platform capability, security review | The sibling skill listed in AGENTS.md section 4 |

## 0. Orient

1. Identify the owner: author frontend, compiler, program/capability contract, Wasm library, runtime kernel, host primitive, platform, stdlib/preset, UI or legacy subsystem. Use ADR-0022, ADR-0023 and the module disposition table.
2. Read `build/modules.zig` to confirm the allowed import directions. If you need a new dependency, change it there first and state it in the PR description; `tools/check` rejects undeclared edges.
3. Find the active spec in `docs/README.md` and its ADRs. Retained v1 specs apply only to their named legacy subsystem. Changing a wire format = changing the spec + schema + tests, all three in the same commit.
4. Name the user-visible result and the acceptance ID it maps to. Do not re-ask choices that accepted ADRs or AGENTS.md already settle.
5. A docs, skill, or tooling change with no product case does not invent a product PASS. Run the repository documentation/check gates; use N2 IDs only for the behavior they actually cover.

Bug fixes follow the same loop: before patching, record the trigger sequence and the contract it breaks.

## 1. Design

- Write the failure scenarios before the success path: power loss, kill, disk full, locked file, UAC cancel, network reset, expired signature, rollback attack.
- Every durable state must define its recovery outcome in the owning lifecycle spec. The current Component profile uses `docs/spec/runtime-lifecycle-v2.md`; retained profiles keep their original specs. Describe the implementation in the architecture documentation and test the real persistence boundary.
- Product source executes at build time through a language SDK or Starlark. Runtime product policy belongs to fixed capability libraries using host-controlled primitives. Keep component/channel/layout conventions in stdlib or presets; business-data migration remains product-owned.
- See [references/design-and-debugging.md](references/design-and-debugging.md) for details.

## 2. Contract

- External JSON goes through `contracts.json.decodeStrict`, then the owning semantic validator (`program` for compiled programs). Wasm uses bounded profile validation plus full engine validation. Neither serialization accepts author expressions.
- Put new limits in `contracts.Limits`; do not scatter constants.
- Keep each public ABI header, implementation and consumer tests in sync. New authoring uses `api/c/compiler_v2.h`; guest contracts use `api/wit/` and the standard Component Model ABI. Retained author/runtime headers keep their historical scope. Read [authoring v2](../../../docs/development/authoring-v2.md) and [Component SDK](../../../docs/development/component-library-sdk.md) for the current lanes.

## 3. Implement

- Read the `zig-0.17` and `zig-tiger-style` skills. This repository's deviations and 0.17 pitfalls are in [references/implementation.md](references/implementation.md).
- Files internal to a module are not exposed: expose only through `pub` in `root.zig`.
- Every function ≤ 70 lines; every file ≤ 600 lines; beyond that, split into owner files by semantics, do not create `utils.zig`.

## 4. Verify

Pick the minimal set for the change, then run the full set:

| Change | Command |
|---|---|
| Any Zig | `zig build check test` |
| transaction / executor / platform | `zig build test:sim -Dseeds=2000` |
| Parser | `zig build test:fuzz` (and add the triggering sample to `tests/fuzz/corpus/`) |
| UI | `zig build test:golden`, with `-Dupdate=<component>` when needed; inspect `zig build ui:gallery` manually |
| CLI / engine | `zig build test:e2e test:c-smoke` |
| Size / dependencies | `zig build check:cross check:binary check:size` |
| Before delivery | `zig build verify --cache-poison=disallowed` |

Put the acceptance ID at the start of the test name. Current Component behavior uses N2 IDs and `docs/acceptance-plan-v0.3.md`; preserve earlier N1/N2 scopes and results. Run `zig build test:component test:author test:core` for current contracts; retained `aot-test aot-e2e` evidence does not establish Component-v2 completion. Details in [references/acceptance.md](references/acceptance.md).

## 5. Deliver

- Commit: `<type>(<scope>): English summary`, ≤ 300 net lines; `zig build check:commits`.
- The final report lists: commands actually run and their results, items not run and why, known limitations. Do not write "passed" without evidence.
- Keep the author's claim, tool evidence, and independent review apart. A review or a reading of the diff does not replace a command that ran.
- On a dirty tree, name what was tested, not only `HEAD`.
- If README or user-facing behaviour changed, update `README.zh.md` (AGENTS.md section 1) and the matching page in `apps/user-docs`.

## Anti-patterns

Check [references/anti-patterns.md](references/anti-patterns.md) first. If any row matches, stop and change the design.
