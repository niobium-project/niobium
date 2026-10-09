# Independent platform profile

- **Status:** Baseline

`libs/platform` and `libs/conformance` expose an independent file-backed integration
profile. It is not connected to the current Component runtime. Real deployment
and system-manager activation require separate authority and lifecycle contracts.

## Operations

The profile supports managed file creation, atomic replacement, directory-link
switching, no-follow removal, free-space queries and integration file lifecycle.
Integration lifecycle is prepare, activate, remove and discard, with explicit
ownership markers and rejection of foreign resources.

| Platform | File-backed integrations | Explicitly unsupported |
|---|---|---|
| macOS | Shortcut symlink and service plist | Dynamic file association, OS registration and launchctl activation |
| Linux | Desktop, MIME and unit files | systemctl activation, desktop/MIME cache refresh and application registration |
| Windows | Shortcut file and directory junction | Registry registration, associations and SCM services |

Machine-root redirection in tests is a file-profile exercise, not an elevated
installation qualification. The profile does not launch native elevation helpers,
application bootstrap programs or portable applications. Unsupported requests
return errors rather than silently succeeding.

## Validation and evidence

Identifiers and targets reject escaping paths, separators and platform-reserved
names. Native namespaces and directory links must retain correct no-follow
semantics. A stale directory link must never delete its target.

`libs/conformance` runs the independent profile with temporary owned locations.
Required capabilities cannot return unsupported. Verdicts are pass, unsupported,
not_run and fail; saved records use the [test-system contract](test-system.md).
[N1-AC-14](../acceptance-plan.md) retains its original evidence context; changed
profiles need fresh execution. Cross-compilation does not establish real OS support.
