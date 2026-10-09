# ADR-0016: Documentation lifecycle

- **Status:** Accepted
- **Date:** 2026-10-09

## Context

Duplicate versions and retired designs make it difficult to identify the current
contract. The draft needs one current owner for each topic; Git already records
previous versions.

## Decision

- Keep one current document per topic, without version suffixes in filenames.
  Preserve real interface versions in contract text and machine-readable schemas.
- Revise ADRs in place to state current decisions. Delete wholly invalid decisions.
  ADR numbers are never reused or renumbered.
- Retaining an older important technical design requires an item-specific decision.
  The user website's release builds and version selector remain an explicit exception.
- Preserve relevant acceptance IDs, evidence identities and original scopes. Older
  results never qualify changed contracts or executable bytes.
- [Documentation management](../development/docs-management.md) owns the workflow.

## Consequences

Readers see current contracts and procedures. Earlier text and removed decisions
remain available through Git history. Renames and deletions require a reference
sweep, bilingual synchronization and documentation checks.
