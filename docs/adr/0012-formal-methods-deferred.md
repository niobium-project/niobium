# ADR-0012: Formal models deferred

- **Status:** Accepted
- **Date:** 2026-10-07

## Context

The transaction/commit/recovery state machine suits TLA+ modeling, but TLC depends on Java, which violates [ADR-0001](0001-repository-baseline-and-zig-only-toolchain.md).

## Decision

- Formal model checking is deferred. Current kernel qualification uses frozen-plan
  fault tests and real process kills through `zig build test:kernel core:e2e`.
  These tests are not an exhaustive model proof.
- Re-evaluate when the state machine grows to concurrent transactions or maintainer self-update.

## Consequences

- The evidence is weaker than model checking; the acceptance plan marks how each related item is covered.
