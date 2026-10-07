# Test lanes and evidence

| Lane | Content | Command | Part of verify |
|---|---|---|---|
| L0 static | fmt, ast-check, lint, check, check-docs, complexity, schema, size gate, binary lint | `zig build check`, `zig build size-gate` | Yes |
| L1 pure core | Per-module unit tests (SafeAllocator), resolver/planner/state machine on VirtualPlatform | `zig build test` | Yes |
| L2 faults and security | Crash injection at every kill point, `checkAllAllocationFailures`, TUF negative cases, malicious archives, seeded sim | `zig build test`, `zig build sim` | Yes (sim 500 seeds) |
| L2 concurrency | ThreadSanitizer | `zig build test -Dtsan` | Yes (macOS/Linux hosts) |
| L2 fuzz | Integrated fuzzer + `tests/fuzz/corpus` | `zig build fuzz` | No (on demand) |
| L3 platform contract | Host backend runs PlatformContract in a temporary root | `zig build test` | Yes |
| L4 scenarios | `examples/hello` online (local HTTP)/offline install → update → rollback release → repair → uninstall; UI golden | `zig build e2e`, `zig build golden` | Yes |
| L4 build API | `examples/hello` as a standalone package depending on this repository by path, producing an offline bundle with `build/sdk.zig` ([consuming](consuming.md)) | `zig build example` | Yes |
| L5 real OS | Parallels Windows 11, Ubuntu ARM64 | `zig build vm-smoke` | No; reports BLOCKED when unavailable |

## Selection and saved reports

The normative contract is [test-system-v1](../spec/test-system-v1.md); construction state and exit
criteria are in the [maintainer roadmap](../roadmap-v0.2.md#test-system-construction).

```sh
zig build test
zig build test "-Dsuite=conformance,e2e"
zig build test -Dsuite=e2e -Dcase=online-lifecycle
zig build test -Dsuite=sim -Dseeds=2000 -Dseed-start=42
zig build verify --cache-poison=disallowed
zig build evidence -Daction=validate -Dinput=.evidence/e2e/<execution>
zig build evidence -Daction=publish -Dinput=.evidence/e2e/<execution>
```

`test` defaults to unit and host conformance. Registered suites are `unit`, `conformance`, `e2e`,
`sim`, `golden`, `fuzz`, `c-smoke`. Stable case IDs are `host-user`, `host-machine`,
`online-lifecycle`, `repair-uninstall`, `offline-bundle`, `artifact-tampering`. Unknown/empty
selections fail. Quote comma-separated suite arguments in PowerShell. Case selection requires its suite; unselected cases do not claim a result.
`verify` rejects suite/case filters. Simulation accepts 1–100,000 seeds and a non-overflowing start.
`-Dtarget` changes compilation; native execution evidence still names the machine that ran it.
`-Dcoverage` retains kcov and `-Dtsan` retains the concurrency lane. The old `sim`, `e2e`, `golden`,
`fuzz` and `c-smoke` steps are aliases of the same execution nodes. VM execution stays explicit.
Run Windows e2e (including `verify`) in a disposable OS account: temporary home variables do not
redirect HKCU, and these CLI cases exercise the sample product's native uninstall registration.
Evidence-tool timeout/output regressions use stock Windows PowerShell as a bounded child fixture;
POSIX hosts use their standard shell utilities. The assertions and runner remain Zig.

Continuous fuzzing uses Zig's native protocol: `zig build fuzz -Dcontinuous-fuzz --fuzz` (or
`zig build test -Dsuite=fuzz -Dcontinuous-fuzz --fuzz=1000` for a bounded investigation). This
explicit mode bypasses the saved-run wrapper; ordinary `fuzz` records corpus replay. Native fuzz
exploration has no archived suite verdict and is not part of `verify`.

Each binary writes a uniquely named saved run under `.evidence/<suite>/`. `report.json` includes
separate stdout/stderr attachments and conformance/e2e case fragments. Other suites report the
binary's aggregate outcome. Incomplete runs retain NOT_RUN or the observed failure; evidence I/O
errors fail the build. To replay a simulation, use its saved seed count/start and tested revision.
Publication reads saved data and never executes tests. It requires the pinned AWS CLI and explicit
R2 configuration; testing and validation do not contact R2.

## Continuous integration

GitHub Actions on the public repository. The required check is `CI / linux`. A new commit on a pull request cancels the previous run for that ref. Pushes to `main`, the nightly verify, and the weekly host run are not cancelled.

| When | Job | Command |
|---|---|---|
| Every pull request and push to `main` | `linux-tests` | `zig build check` |
| Code, build, test, toolchain, workflow or unknown executable input | `linux-tests`, then advisory `coverage` | `zig build test -Dsuite=unit,conformance,e2e`, `zig build c-smoke`; coverage uses kcov |
| UI implementation or golden inputs | `linux-tests` | `zig build golden` |
| Code inputs above, manual dispatch, or `ci:hosts` | `windows`, `macos` | Selected native unit/conformance/e2e; macOS also ThreadSanitizer |
| Every CI run, even when a selected job failed or was cancelled | `linux` | Aggregate: changes and Linux must succeed; selected Windows/macOS must succeed; unselected jobs must be skipped |
| Daily or `ci:verify` | `verify` | `zig build verify --cache-poison=disallowed` on a fresh build cache |
| Weekly or `ci:hosts` | `windows`, `macos`, `arm-golden` | Existing host lanes and Linux arm64 golden |
| Every completed CI, Hosts or Nightly run, including forks and failures | `Evidence / publish` | Trusted default-branch Zig publisher, saved artifacts only |

`vm-smoke` and `fuzz` stay local. Copilot code review and the Codecov status are advisory. The debug `.zig-cache` is restored by OS and CPU architecture, saved only after a successful same-repository build, and is not used by the nightly verify. Fork pull requests restore that cache and do not write a new one.

## Evidence

- Test names start with an acceptance ID, for example `test "N1-INV-01: crash at every op recovers to OLD or NEW"`; `tools/check-docs` verifies that the ID exists in [acceptance-plan-v0.1](../acceptance-plan-v0.1.md).
- Catalog suites write structured runs to `.evidence/<suite>/<execution>/`; gallery and vm-smoke retain their existing evidence layouts.
- On failure, keep the first evidence; find the root cause first, and do not rerun until green.
- `zig build gallery` writes every catalog case and page (platform × theme × 100/200%) to `.evidence/ui-gallery/<UTC>/` with an `index.html`; it is for human review only and is not a gate.

## R2 deployment and recovery

Create a **private Standard** bucket (suggested name `niobium-test-evidence`); leave public access
and custom domains disabled. Use a separate administrator identity to apply
[the lifecycle configuration](../../.github/ci/r2-lifecycle.json). Its only expiry prefix is
`evidence/v1/`; `reports/v1/` and `release-evidence/v1/` must not match an expiry rule.
Do not apply it blindly over a shared bucket's rules.

Configure the GitHub environment `test-evidence`, restricted to the default branch:

| Kind | Name | Value |
|---|---|---|
| Variable | `R2_ENDPOINT` | The account's HTTPS S3 endpoint from the R2 dashboard |
| Variable | `R2_BUCKET` | The private Standard bucket |
| Secret | `R2_ACCESS_KEY_ID` | Bucket-scoped object read/write access key |
| Secret | `R2_SECRET_ACCESS_KEY` | Its secret; never put it in a report or repository file |

The publisher pins AWS CLI 2.27.49 and verifies the installer SHA-256 before installation. No
repository cache or downloaded executable enters the publisher. Opaque ZIPs are extracted by Zig
with path, count, size and output bounds. Run/attempt and fork provenance come from GitHub's API;
producer assertions remain test data and do not become trusted release certification.
The environment credentials map to AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY only for publication.
The approved transport exception is [ADR-0021](../adr/0021-ci-evidence-transport.md).

With administrator credentials in the deployment environment, use the pinned transport to apply
and read back the reviewed rules:

```sh
aws --endpoint-url "$R2_ENDPOINT" --region auto s3api put-bucket-lifecycle-configuration \
  --bucket "$R2_BUCKET" --lifecycle-configuration file://.github/ci/r2-lifecycle.json
aws --endpoint-url "$R2_ENDPOINT" --region auto s3api get-bucket-lifecycle-configuration \
  --bucket "$R2_BUCKET"
```

Before marking the archive supported, publish a saved test run, publish it again unchanged, then
check that a conflicting same-key body is refused and the original bytes remain. Interrupt one
publication after an attachment and replay it. List `reports/v1/` with `list-objects-v2 --max-keys 1
--no-paginate`; pass the returned continuation token until the listing is exhausted. Read objects
back and compare the saved sizes/digests. Confirm bucket privacy, Standard storage and lifecycle
readback separately with the administrator identity. Retain these results as deployment evidence.
The local protocol tests are not a substitute for these real service checks.

GitHub retains producer artifacts for 90 days. If publication fails, rerun `Evidence` with the
source `run_id` and `attempt` before those artifacts expire. It reuses saved evidence and leaves the
test verdict unchanged. A run with no artifacts still has GitHub run/job provenance; it must never
be presented as conformance PASS. The future viewer is a separate task.

## UI golden

- `zig build golden` compares `tests/golden/kit/**` and `tests/golden/screens/**` pixel by pixel, and compares the IR, display list and SemanticTree text snapshots of the macOS light pages.
- Rasterization happens entirely in software and stb_truetype is compiled with `-ffp-contract=off`, so the same golden is bit-identical on macOS, Linux aarch64 and Linux x86_64. `zig build test-cross` installs `suite-golden`; run `zig-out/cross-tests/<target>/suite-golden` from the repository root to recheck on the target machine.
- Waiting and concurrency use barriers, failpoints and a controllable clock, not sleep.

## Seeded sim

- `zig build sim -Dseeds=N -Dseed-start=S` runs seeds S…S+N-1 for every scenario; a failure prints the scenario name and seed.
- Reproduce: `zig build sim -Dseeds=1 -Dseed-start=<failing seed>`; the same seed produces the same fault sequence (`libs/platform/fault.zig`).
- Scenarios live in `tests/sim/scenarios.zig`; each scenario asserts only invariants (OLD or NEW, no leftover lock, replayable journal), not specific errors.

## Crash records

Shipping builds (`setup`, helper, `libdistribution`) use ReleaseSafe. `zig build cross` also uses ReleaseSafe rather than ReleaseSmall: the size gate measures the ReleaseSafe binary that is actually shipped. Linux (ELF) shipping builds carry no DWARF (`shippingStrip` in `build/targets.zig`): DWARF is about 10 MB of 13 MB, and Zig 0.17's `objcopy` cannot split it into a separate file; on macOS and Windows the debug info is not in the executable to begin with (object files, PDB). Linux crash record `addresses` therefore have to be symbolized with an unstripped build of the same commit (`zig build -Dtarget=<target> -Doptimize=ReleaseSafe`); whether the code addresses of the two are byte-identical has not been verified.

Both panics and native faults (POSIX `SIGSEGV`/`SIGBUS`/`SIGILL`/`SIGFPE`, Windows vectored exception handling) go through `libs/core/crash.zig`:

1. call the registered flush hook (journal written to disk);
2. write `crash-<YYYYMMDDTHHMMSSZ>.json` in the log directory;
3. hand off to the std default handler, which prints the stack and aborts.

Record fields:

| Field | Meaning |
|---|---|
| `schema` | Always 1 |
| `kind` | `panic` or `fault` |
| `message` | Panic message or signal name |
| `version`, `product` | Build version and product id |
| `phase` | Engine phase at crash time (`core.Phase`) |
| `tx_id` | Sequence number of the in-progress transaction, 0 for none |
| `time` | UTC time |
| `addresses` | Return addresses (hex strings), at most 32 |

On the next start, `RecoverIncompleteTransaction` runs first, and then the user is told what happened.
