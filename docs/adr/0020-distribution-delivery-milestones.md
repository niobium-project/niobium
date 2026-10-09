# ADR-0020: Distribution delivery milestones

- **Status:** Accepted
- **Date:** 2026-10-09

## Context

Product authors need online, offline-file and self-extracting delivery profiles.
These profiles must preserve authority boundaries and delivered-byte identity.

## Decision

Online, complete offline-file and self-extracting installers remain planned
product/library profiles. [ADR-0022](0022-installer-dsl-and-aot-toolchain.md) and
[ADR-0023](0023-standard-content-and-component-contracts.md) own the compiler,
content, authority and transactional runtime boundaries.

This decision does not approve a container layout, platform qualification or
implementation. Every profile needs explicit signing order, limits, acquisition,
trust, freshness and recovery contracts. SFX adds no shell hooks, ambient native
plugins, generic executable packing or unrestricted elevated execution.

## Consequences

The [distribution backlog](../development/distribution-backlog.md) owns design
questions. Each milestone must qualify final delivered bytes on its declared
OS, architecture and scope. Independent TUF and extraction tests cannot establish
completion of a distribution profile.
