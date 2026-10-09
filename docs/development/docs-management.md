# Documentation management

Keep one current document per topic. Git history preserves earlier text and removed
decisions. [ADR-0016](../adr/0016-documentation-lifecycle.md) owns this rule;
[AGENTS.md](../../AGENTS.md) defines precedence.

## Current documents

| Kind | Contents | Maintenance |
|---|---|---|
| `adr/` | Current architecture decisions and reasons | Consolidate changes in place; delete invalid decisions |
| `spec/` | Active contracts | Update with the owning interface and tests |
| `architecture/` | Current implementation and review findings | Update with implementation changes |
| `development/`, `runbooks/` | Current procedures | Delete procedures for removed interfaces |
| `roadmap.md`, `acceptance-plan.md` | Current work and evidence scopes | Keep active obligations and exact evidence identities |

Do not add version suffixes to document filenames. Actual ABI, WIT, schema and
profile versions remain in their contracts. Keeping an older technical design
requires an explicit, item-specific maintainer decision. The website release
selector and historical release builds are an exception: they publish documentation
for released source trees rather than duplicate maintainer documents.

## Decisions and references

ADRs carry `Status` and `Date`. Use `Proposed`, `Accepted`, `Superseded` or
`Deprecated`; a superseded decision names its successor. Accepted ADRs may be
revised in place to state the latest decision. Delete a wholly invalid decision
and remove its references. Never reuse or renumber an ADR number.

Before removing or renaming a document, search its links in docs, skills, code,
tests and website pages. Update each reference to its actual current owner or
remove the obsolete assertion. Do not preserve an obsolete interface by adding a
redirect to an unrelated contract.

Acceptance IDs are never reused. Preserve still-relevant shared testing and
independent component obligations with their original scope. Historical PASS
records identify their tested source and context; they cannot establish completion
of a changed implementation. Delete retired product obligations from the current
plan, with their earlier records recoverable through Git.

## Maintainer and user documentation

`docs/` serves maintainers; `apps/user-docs` serves installer authors. Each fact
has one owner and other pages link to it. `README.zh.md` mirrors `README.md`, and
Chinese website pages mirror their English counterparts under ADR-0017.

Run `zig build check:docs` and the website build after changes. Check current
links, both locales, roadmap priorities and evidence scope. Do not mark a feature
usable merely because a source test or website build passed.
