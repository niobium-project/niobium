# Test lanes and evidence

The current product lane uses `zig build core:e2e`; current foundational contracts
use `test:core`, `test:component` and `test:author`. Independent UI, TUF, package
and platform tests retain their own scopes in [acceptance](../acceptance-plan.md).

| Lane | Content | Command |
|---|---|---|
| L0 | Static, documentation, schema, dependency and size checks | `zig build check`, `zig build verify` |
| L1 | Pure module and author tests | `zig build test test:core test:author` |
| L2 | Kill points, allocation failures, malicious archives and TUF inputs | `zig build test:kernel core:e2e test:fuzz` |
| L2 concurrency | ThreadSanitizer | `zig build test:tsan` |
| L3 | Independent file-backed platform profile | `zig build test` |
| L4 | Final installer lifecycle, migration, refusal and recovery | `zig build core:e2e` |
| L4 UI | Independent deterministic renderer snapshots | `zig build test:golden` |
| L5 | Actual target execution | Transferred-byte native witnesses, separately recorded |

## Selection and saved reports

The [test-system contract](../spec/test-system.md) owns execution and evidence.
`zig build test` runs the default registered selection. Unknown or empty selections
fail; case filters require their suite. `verify` rejects narrowing filters.
`-Dtarget` changes compilation, while an execution record names the host that ran it.

Use `zig build test:evidence -Daction=validate -Dinput=.evidence/<suite>/<execution>`
to validate a saved record. Publication uses `-Daction=publish` and does not execute
tests. Each run records source revision/dirty identity, binary digest, command,
exit status and bounded stdout/stderr. Incomplete records remain NOT_RUN or FAIL;
evidence I/O errors fail the build. Preserve the first failing record.

Continuous fuzzing is explicit and separate from bounded corpus replay:
`zig build test:fuzz -Dcontinuous-fuzz --fuzz`. It does not produce a saved suite
verdict or qualify a platform by itself.

## Continuous integration

GitHub Actions on the public repository. The required check is `CI / linux`. A new commit on a pull request cancels the previous run for that ref. Pushes to `main`, the nightly verify, and the weekly host run are not cancelled.

| When | Job | Command |
|---|---|---|
| Every pull request and push to `main` | `linux-tests` | `zig build check` |
| Code, build, test, toolchain, workflow or unknown executable input | `linux-tests` and advisory `coverage`, in parallel | `zig build test -Dsuite=unit,conformance`, `zig build test:author`; coverage uses kcov and does not restore the shared build cache |
| UI implementation or golden inputs | `linux-tests` | `zig build test:golden` |
| Code push to `main`, manual dispatch, or a pull request labeled `ci:hosts` | `windows`, `macos` | Selected native unit/conformance/e2e; macOS also ThreadSanitizer. Other pull requests skip these jobs |
| Every CI run, even when a selected job failed or was cancelled | `linux` | Aggregate: changes and Linux must succeed; selected Windows/macOS must succeed; unselected jobs must be skipped |
| Code pull request | `Linux SDK compile` | `zig build sdk:build` on Linux, using a cached engine archive and wasm32 guests when that cache hits. This compile is not native qualification and does not publish `core-sdk-*` artifacts. A cache miss builds those Rust outputs from source; a same-repository pull request then stores them |
| Documentation-only pull request or push to `main` | Core v2 required | The native, assembly and pull-request compile jobs stay skipped and the aggregate check succeeds |
| Push to `main`, or manual dispatch, when code changed | Native matrix, then assembly | From-source `zig build test:core sdk:build core:cross-tools` on Linux, macOS and Windows, then source-free assembly and delivered-byte execution. Linux also fills the engine cache when that key is new |
| Daily or `ci:verify` | `verify` | `zig build verify --cache-poison=disallowed` on a fresh build cache |
| Weekly or `ci:hosts` | `windows`, `macos`, `arm-golden` | Existing host lanes and Linux arm64 golden |
| Every completed CI, Hosts or Nightly run, including forks and failures | `Evidence / publish` | Trusted default-branch Zig publisher, saved artifacts only |

`vm-smoke` and `fuzz` stay local. Copilot code review and the Codecov status are advisory. The debug `.zig-cache` is restored by OS and CPU architecture, saved only after a successful same-repository build, and is not used by the nightly verify. Cargo `wasmtime-target` and `guest-target` directories are removed before that save. Coverage runs beside `linux-tests` and does not restore this build cache. Fork pull requests restore that cache and do not write a new one. The Core pull-request compile checks that Linux can link `sdk:build` with a cached engine. A same-repository miss stores that engine for the next run. Three-OS execution and delivered bytes remain on the `main` qualification.

## Evidence

- Test names start with an acceptance ID, for example `test "N1-INV-01: crash at every op recovers to OLD or NEW"`; `tools/check-docs` verifies that the ID exists in [acceptance-plan-v0.1](../acceptance-plan.md).
- Catalog suites write structured runs to `.evidence/<suite>/<execution>/`; gallery and vm-smoke retain their existing evidence layouts.
- On failure, keep the first evidence; find the root cause first, and do not rerun until green.
- `zig build ui:gallery` writes every catalog case and page (platform × theme × 100/200%) to `.evidence/ui-gallery/<UTC>/` with an `index.html`; it is for human review only and is not a gate.

## R2 deployment and recovery

The deployment uses the existing **private Standard** bucket `org-niobium-project-dev-assets`
in the US jurisdiction. Public access and custom domains remain disabled. Every archived run is
under `ci-evidence/YYYY-MM/`, using the source attempt's UTC month rather than the upload month.
Use a separate administrator identity to apply
[the lifecycle configuration](../../.github/ci/r2-lifecycle.json). Its only expiry prefixes are
`ci-evidence/YYYY-MM/evidence/v1/`; monthly `reports/v1/` and `release-evidence/v1/` paths must
not match an expiry rule. Merge these rules with existing bucket rules; never replace a shared
bucket's unrelated configuration. The checked-in horizon is October 2026–September 2027.
Renew that horizon annually before September ends. Publication fails when an ordinary object
lacks an expiry or a permanent object has one.

Configure the GitHub environment `test-evidence`, restricted to the default branch:

| Kind | Name | Value |
|---|---|---|
| Variable | `R2_ENDPOINT` | The bucket's jurisdiction-specific HTTPS S3 endpoint (`<account>.us.r2.cloudflarestorage.com` here) |
| Variable | `R2_BUCKET` | `org-niobium-project-dev-assets` |
| Secret | `R2_ACCESS_KEY_ID` | Bucket-scoped object read/write access key |
| Secret | `R2_SECRET_ACCESS_KEY` | Its secret; never put it in a report or repository file |

The publisher pins AWS CLI 2.27.49 and verifies the installer SHA-256 before installation. No
repository cache or downloaded executable enters the publisher. Opaque ZIPs are extracted by Zig
with path, count, size and output bounds. Run/attempt and fork provenance come from GitHub's API;
producer assertions remain test data and do not become trusted release certification. The trusted
checkout is pinned to the workflow event SHA. Metadata and ZIP downloads have enforced byte
caps; workflow-wide extraction budgets prevent many small artifacts from bypassing per-bundle
limits, and published extraction trees are removed before processing the next artifact.
The publisher writes a temporary mode-0600 AWS shared credentials file, removes the secret
environment variables before invoking Zig, and deletes the file when the step exits. AWS CLI
loads it through `AWS_SHARED_CREDENTIALS_FILE`; credential values never enter Zig's configure
cache. Local publication and live verification should likewise use a private AWS credentials
file, rather than passing secret environment variables to `zig build`.
The approved transport exception is [ADR-0021](../adr/0021-ci-evidence-transport.md).

With administrator credentials in the deployment environment, use the pinned transport to merge
the reviewed rules into the existing lifecycle configuration, apply the merged file, and read it
back. The example expects that reviewed merged file in `lifecycle-merged.json`:

```sh
aws --endpoint-url "$R2_ENDPOINT" --region auto s3api put-bucket-lifecycle-configuration \
  --bucket "$R2_BUCKET" --lifecycle-configuration file://lifecycle-merged.json
aws --endpoint-url "$R2_ENDPOINT" --region auto s3api get-bucket-lifecycle-configuration \
  --bucket "$R2_BUCKET"
```

Before marking the archive supported, publish a saved test run, publish it again unchanged, then
check that a conflicting same-key body is refused and the original bytes remain. Interrupt one
publication after an attachment and replay it. List `ci-evidence/YYYY-MM/reports/v1/` with
`list-objects-v2 --max-keys 1 --no-paginate`; pass the returned continuation token until the listing is exhausted. Read objects
back and compare the saved sizes/digests. Confirm bucket privacy, Standard storage and lifecycle
readback separately with the administrator identity. Retain these results as deployment evidence.
The local protocol tests are not a substitute for these real service checks.

With bucket-scoped object credentials in the environment and AWS CLI 2.27.49 in PATH, explicitly
run the live Zig checks:

```sh
zig build test -Dsuite=unit -Dr2-live=true
```

This flag enables only the evidence-tool live test; ordinary runs stay offline. It creates isolated
`fixture/archive` objects, verifies duplicate/conflicting writes and digest readback, resumes a
partial report-last publication, paginates object listings, and uploads then aborts an incomplete
multipart object. Protocol fixture reports have verdict NOT_RUN and do not certify conformance.
The actual unit outcome is saved normally; `environment` records `r2-live=1` for replay. The live
option requires unfiltered unit selection. Publication has at most four attachment transfers in
flight, each with separate scratch files; its report is uploaded after all transfers succeed.

GitHub retains producer artifacts for 90 days. If publication fails, rerun `Evidence` with the
source `run_id` and `attempt` before those artifacts expire. It reuses saved evidence and leaves the
test verdict unchanged. A run with no artifacts still has GitHub run/job provenance; it must never
be presented as conformance PASS. The future viewer is a separate task.

## UI golden

- `zig build test:golden` compares `tests/golden/kit/**` and `tests/golden/screens/**` pixel by pixel, and compares the IR, display list and SemanticTree text snapshots of the macOS light pages.
- Rasterization happens entirely in software and stb_truetype is compiled with `-ffp-contract=off`, so the same golden is bit-identical on macOS, Linux aarch64 and Linux x86_64. `zig build test:cross` installs `suite-golden`; run `zig-out/cross-tests/<target>/suite-golden` from the repository root to recheck on the target machine.
- Waiting and concurrency use barriers, failpoints and a controllable clock, not sleep.

## Crash and recovery qualification

Runtime and tool delivery use ReleaseSafe. Native fault and crash hooks belong to
`libs/core/crash.zig`; their presence is not a proof that an application installs
those hooks or persists a recoverable kernel plan. Actual recovery qualification
uses frozen-plan kill points in `core:e2e` and records OLD or NEW receipts.
