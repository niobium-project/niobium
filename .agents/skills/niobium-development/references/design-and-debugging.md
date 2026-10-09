# Design and debugging

## Design checklist

1. **Evaluation boundary?** Author source executes at build time. Fixed Wasm libraries compute runtime policy through explicit host authority. Application-owned business migration uses its own activation contract.
2. **Frozen result?** Planning combines compiled program, explicit inputs and observed state. Host effects and resulting state become durable before mutation; recovery never reruns guest policy.
3. **Ownership?** The installer owns `versions/`, the `current` pointer, the journal, and trust state; the app owns user data and runtime configuration. The installer does not write to the app data directory.
4. **Privilege?** Operations that need elevation must belong to the closed op set of `ipc-v1`; adding an op = changing the spec + broker + helper + negative tests.
5. **Transaction?** A new primitive specifies durable recovery semantics. The initial generation profile commits through a pointer swap; another profile requires an explicit contract and OLD-or-NEW evidence.
6. **Bounds?** Every loop, queue, retry, and read states its upper bound and timeout.
7. **Journey?** Who triggers the change, and what success, refusal, and waiting look like to the user; which N2 ID it maps to (N1 remains legacy). Name the states that must not be confused: `versions/<seq>` vs `current`, broker vs helper, UI snapshot vs journal.
8. **Identity?** Product/release, runtime template, program, library and artifact identities are distinct. The install root and selections come from validated bindings and installed state. Never infer them from a display name or the process cwd.
9. **Failure?** For each new state: what is durable, and how recovery (`RecoverIncompleteTransaction`, implemented as `transaction.recover` in `libs/transaction/recovery.zig`) reaches OLD or NEW. An unknown outcome (lost helper, kill mid-op, dropped download) stays unknown until it is reconciled from the journal.

## Debugging process

1. **Pin the reproduction**: a failure identifies its case and failpoint; replay the owning lane and inspect its `.evidence/<suite>/<UTC>/` record. Write down what you observed separately from what you suspect.
2. **Find the first anomaly first**: read the journal (`<root>/journal/*.jsonl`) in record order; the first record that deviates from the spec is near the root cause. Fix that deviation, not a later symptom.
3. **Crash records**: `<root>/logs/crash-<UTC>.json` contains the phase, tx-id, and stack addresses; resolve them against symbols from `zig build -Doptimize=ReleaseSafe`.
4. **Do not rerun to get green**: treat flakiness as a real bug first; add `-Dtsan` for concurrency issues, switch to a controllable clock for timing issues.
5. **After the fix**: turn the reproducing input into a test (sim seed, fuzz corpus, malicious fixture), and check the neighbouring cancel, crash, replay, and partial-write paths.
6. **Mitigation is not a fix**: if the change only reduces the symptom, say so and name the root cause that remains.

## Common symptoms

| Symptom | Check first |
|---|---|
| After recovery `current` points to a nonexistent version | Whether staging is fsynced before commit; whether journal `ready_to_commit` precedes the pointer swap |
| rename occasionally fails on Windows | Antivirus/indexer locks; whether the executor uses bounded backoff retry |
| TUF verification fails after the clock is set back | Whether expiry is compared with a monotonic clock; whether `trust/state.json` persists the highest version |
| UI stutters | Whether the engine runs on the UI thread; whether a snapshot is held too long |
| X11 window does not appear | Whether a connection setup reply parse error is swallowed; `DISPLAY` and `XAUTHORITY` |
