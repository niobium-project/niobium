# Transaction model

The [runtime lifecycle](../spec/runtime-lifecycle.md) owns persistence and recovery.
`libs/kernel` validates ownership, freezes complete plans and prepares each root
before recording a durable coordinator decision. The [architecture overview](overview.md)
explains the current flow; [acceptance](../acceptance-plan.md) owns qualification.

Recovery before the decision retains OLD; recovery after it completes NEW on all
roots. Recovery consumes frozen content and host operations, without executing
libraries or resolving dependencies. Unknown state formats, incompatible products
and changed migration identities refuse before mutation. Product authors own
upgrade recognition and explicit migration policy.

Each root stages a complete generation and retains its content receipts. Cross-root
activation is not simultaneously visible, so recovery must converge to one complete
outcome. Modified and unrecorded user data cannot be removed as framework-owned
resources. Kill-point tests require OLD or NEW, never MIXED, across every root.
