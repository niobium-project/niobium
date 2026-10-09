# Installer and distribution feature ownership

This catalog maps the FC identifiers onto the DSL/AOT architecture
in [ADR-0023](adr/0023-standard-content-and-component-contracts.md). It is an
ownership and implementation-scope inventory. It does not assert product or
platform acceptance. The [roadmap](roadmap.md) owns scheduling; the
[acceptance plan](acceptance-plan.md) owns executed results.

The former B/C/I/X classification is retired here. A v1 contract or retained
implementation does not establish a v2 capability. Fixed official, product and
third-party Wasm libraries are supported extension mechanisms; ambient native
plugins and unrestricted privileged execution remain outside the contract.

## Read the ownership columns

| Owner | Responsibility |
|---|---|
| Core | Typed identity, dependency validation, budgets, lifecycle and compatibility mechanisms |
| H-content | Immutable trees, verified content references, acquisition and bounded derivation |
| H-machine | Truthful machine observations and typed machine-state resources |
| H-authority | Grants, scope, ownership, access and privilege boundaries |
| H-execution | Frozen operations, maintenance, verification and recovery |
| Stdlib | Replaceable libraries composing these mechanisms into reusable capabilities |
| Product | Product/distribution policy, application decisions and operator responsibility |
| Preset | Build-time conventions, templates, workloads and experience composition |
| Toolchain | Author SDKs, compiler, image assembly, publishing and qualification tools |

`Current slice` identifies existing code in a bounded area, not completion of the whole
row. `Independent component` identifies a separately tested component; it is not
a current runtime integration claim. `Planned` needs a public contract and implementation. `Shared` identifies
reusable framework tooling or rendering. `Excluded` identifies a current boundary,
not a ban on product-owned policy implemented through supported contracts.
Only acceptance records use PASS, FAIL, BLOCKED, NOT_RUN or DEFERRED.

A design link on a planned row is an interface/work-package owner, not a completed
normative contract. Every platform and user/machine scope needs its own evidence.
[Product journeys](design/product-journeys.md) connect these rows to composed
scenarios, negative vectors and parallel owners.

## Product definition

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-MOD-01 | Product identity, publisher and display version | Core + Product | Current slice | [Program](spec/program-image.md) | Does strict validation reject malformed or ambiguous identity? |
| FC-MOD-02 | Release sequence and minimum installer version | Core + Product | Current slice | [Program](spec/program-image.md) | Are incompatible or regressive releases rejected before mutation? |
| FC-MOD-03 | Required, default and optional components | Product + Preset | Current slice | [Program](spec/program-image.md) | Does GUI/CLI selection produce the same desired state? |
| FC-MOD-04 | Component groups and workload presets | Preset + Product | Planned | [Program](spec/program-image.md) | Can a workload expand into an explicit, reproducible selection? |
| FC-MOD-05 | Versioned dependencies, conflicts and replacements | Product + Toolchain | Planned | [Program](spec/program-image.md) | Are cycles, unsatisfied constraints and conflicts explained before download? |
| FC-MOD-06 | Architecture and platform payload selection | Product + Toolchain | Current slice | [Program](spec/program-image.md) | Is a missing target reported explicitly rather than substituted? |
| FC-MOD-07 | User and machine installation scopes | H-authority + Product | User slice; machine planned | [Access](spec/access-policy.md) | Does scope control paths and required privilege consistently? |
| FC-MOD-08 | Minimum OS, runtime and hardware prerequisites | H-machine + Product | Planned | [Program](spec/program-image.md) | Can preflight reject an incompatible host without executing product commands? |
| FC-MOD-09 | Multiple instances and versions installed side by side | Product + H-authority | Planned | [Program](spec/program-image.md) | Are identity, locks, integrations and update channels isolated? |
| FC-MOD-10 | Installed-state inventory and drift classification | Core + H-machine | Current slice | [Program](spec/program-image.md) | Can managed changes be distinguished from user-owned data? |
## Payload authoring and packaging

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-PKG-01 | Component construction and validation | Toolchain + Product | Current slice | [Content](spec/content-container.md) | Are entrypoints, executable declarations and payload layout validated? |
| FC-PKG-02 | Immutable artifacts addressed by digest | H-content | Current slice | [Content](spec/content-container.md) | Does every reference identify exact authorized bytes? |
| FC-PKG-03 | Deterministic unsigned payload generation | Toolchain + H-content | Current slice | [Content](spec/content-container.md) | Do identical inputs produce identical payload bytes? |
| FC-PKG-04 | File inclusion, exclusion and duplicate diagnostics | H-content + Toolchain | Current slice | [Content](spec/content-container.md) | Can authors inspect the exact file inventory before packing? |
| FC-PKG-05 | Content metadata and explicit deployment access | H-content + H-authority | Basic metadata/access slice | [Access](spec/access-policy.md) | Are source metadata, desired access, grant ceilings and effective target access checked separately? |
| FC-PKG-06 | Online, offline and embedded bundle generation | Stdlib + Toolchain | Embedded slice; remote planned | [Image](spec/setup-image.md) | Do each bundle's contents and source layout satisfy the contracts? |
| FC-PKG-07 | Mixed embedded and remote payload bundles | Stdlib + Product | Planned | [Content](spec/content-container.md) | Are source precedence and offline behavior explicit and trusted? |
| FC-PKG-08 | Existing native application and language bundle ingestion | Toolchain + H-content | Tree slice; native metadata planned | [Content](spec/content-container.md) | Can validated output from native builds, Electron or PyInstaller be packaged? |
| FC-PKG-09 | Native MSI, MSIX, PKG, DEB or RPM export adapters | Toolchain | Planned | [Content](spec/content-container.md) | Can each build-time adapter define ownership without competing updaters? |
| FC-PKG-10 | Compression, size and disk-budget reports | Toolchain | Planned | [Content](spec/content-container.md) | Are download, expansion, staging and retained-version costs separated? |
## Repositories and publishing

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-REL-01 | HTTP and local-directory repositories | Stdlib + H-content | Independent component | [TUF retained](spec/tuf-profile.md) | Do both sources enforce the same release trust contract? |
| FC-REL-02 | Signed stable, beta and nightly channels | Stdlib + Product | Independent component | [TUF retained](spec/tuf-profile.md) | Can channel metadata authorize only its delegated product targets? |
| FC-REL-03 | Metadata-only promotion of tested artifacts | Toolchain + Product | Planned | [Journey design](design/product-journeys.md) | Are promoted artifact bytes identical to the signed, tested bytes? |
| FC-REL-04 | Signed release notes and update notices | Product + Stdlib | Planned | [Journey design](design/product-journeys.md) | Are displayed notes bound to the selected release and safely rendered? |
| FC-REL-05 | Key generation, rotation and recovery workflows | Toolchain + Product | Planned | [Journey design](design/product-journeys.md) | Can a maintainer rotate keys without bypassing root authorization? |
| FC-REL-06 | Atomic repository publication and validation | Toolchain | Planned | [Journey design](design/product-journeys.md) | Can an interrupted publish expose only a valid old or new snapshot? |
| FC-REL-07 | Mirrors, CDN and object storage deployment | Product + Stdlib | Planned | [Journey design](design/product-journeys.md) | Does an untrusted transport remain unable to authorize new bytes? |
| FC-REL-08 | Percentage rollout and deployment cohorts | Product + Preset | Planned | [Journey design](design/product-journeys.md) | Are cohort decisions bounded, privacy-aware and reproducible? |
| FC-REL-09 | Withdrawn releases and authorized version rollback | Product + Core | Planned | [Journey design](design/product-journeys.md) | Can older application bytes be released under a new authorized sequence? |
| FC-REL-10 | Release retention, repository GC and audit inventory | Product + Toolchain | Planned | [Journey design](design/product-journeys.md) | Are artifacts needed by installed clients or offline media preserved? |
## Transfer and caching

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-NET-01 | Download length and digest validation | H-content + Stdlib | Build acquisition/cache slice | [Compiler](spec/compiler-frontends.md) | Are incomplete or modified bytes rejected before extraction? |
| FC-NET-02 | Component-selective download | Product + Stdlib | Independent component | [Independent component](README.md#independent-components) | Are only the resolved artifacts fetched? |
| FC-NET-03 | Verified cache reuse | H-content + Stdlib | Build acquisition/cache slice | [Compiler](spec/compiler-frontends.md) | Can corrupt cache entries ever be treated as valid payloads? |
| FC-NET-04 | Resume after interrupted download | H-content + Stdlib | Planned | [Journey design](design/product-journeys.md) | Is resumed content fully verified against the authorized target? |
| FC-NET-05 | Bounded retries, backoff and network timeouts | H-content + Core | Build acquisition/cache slice | [Compiler](spec/compiler-frontends.md) | Does every failure terminate within a defined retry and time budget? |
| FC-NET-06 | Proxy, authentication and custom trust-store policy | Product + H-authority | Planned | [Journey design](design/product-journeys.md) | Are credentials kept out of logs and never used to bypass release trust? |
| FC-NET-07 | Bandwidth limits and bounded parallel downloads | H-content + Stdlib | Planned | [Journey design](design/product-journeys.md) | Are limits enforced without starving cancellation or verification? |
| FC-NET-08 | Binary differential downloads with full-payload fallback | Toolchain + H-content | Planned | [Journey design](design/product-journeys.md) | Does reconstruction yield the exact authorized full-artifact digest? |
| FC-NET-09 | Cache quotas, GC and shared-cache isolation | Stdlib + H-authority | Planned | [Journey design](design/product-journeys.md) | Are in-use artifacts and other users' entries protected? |
| FC-NET-10 | Air-gapped freshness and offline update policy | Product + Stdlib | Planned | [Journey design](design/product-journeys.md) | Is expired metadata handled by an explicit policy without silent trust bypass? |
## Deployment lifecycle

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-LIF-01 | Fresh installation | Core + H-execution | Current slice | [Lifecycle](spec/runtime-lifecycle.md) | Does the installed state match the validated, frozen desired resource plan? |
| FC-LIF-02 | Installation discovery and status | H-machine + Core | Current slice | [Lifecycle](spec/runtime-lifecycle.md) | Are missing, installed and incomplete states distinguishable? |
| FC-LIF-03 | Component add, remove and selection modification | Product + Stdlib | Current slice | [Lifecycle](spec/runtime-lifecycle.md) | Can selections change while maintaining dependency and ownership rules? |
| FC-LIF-04 | Update and already-current no-op | Core + Product | Current slice | [Lifecycle](spec/runtime-lifecycle.md) | Does an unchanged release avoid machine mutation? |
| FC-LIF-05 | Integrity checking and repair | H-execution + Product | Drift/refusal slice; repair policy planned | [Lifecycle](spec/runtime-lifecycle.md) | Are damaged managed files repaired without deleting user data? |
| FC-LIF-06 | Uninstall and owned-integration cleanup | H-authority + H-execution | Owned files slice; integration retained | [Lifecycle](spec/runtime-lifecycle.md) | Are only framework-owned resources removed? |
| FC-LIF-07 | Portable Run with trusted cache reuse | Product + H-execution | Planned | [Planned](README.md#independent-components) | Does execution avoid installed-profile machine integrations? |
| FC-LIF-08 | Application coordination and files-in-use handling | H-machine + H-execution | Planned | [Lifecycle](spec/runtime-lifecycle.md) | Are running processes handled without forced data loss? |
| FC-LIF-09 | Restart requirements and reboot continuation | H-execution + Product | Planned | [Lifecycle](spec/runtime-lifecycle.md) | Can recovery distinguish pending restart from completed deployment? |
| FC-LIF-10 | App Bootstrap handoff and pending activation | Product + H-execution | Planned | [Host design](design/host-primitives-and-stdlib.md) | Does application failure preserve the documented committed state? |
## Transactions and recovery

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-TXN-01 | Durable journal and typed installation plan | Core + H-execution | Current slice | [Lifecycle](spec/runtime-lifecycle.md) | Can recovery reconstruct the transaction after process loss? |
| FC-TXN-02 | Staging isolation and active-version switching | H-content + H-execution | Current slice | [Lifecycle](spec/runtime-lifecycle.md) | Can writes affect active files before commit? |
| FC-TXN-03 | Precommit rollback and postcommit roll-forward | Core + H-execution | Current slice | [Lifecycle](spec/runtime-lifecycle.md) | Does every kill point recover to a contract-valid OLD or NEW state? |
| FC-TXN-04 | Idempotent apply, rollback and verification | H-execution | Current slice | [Lifecycle](spec/runtime-lifecycle.md) | Can interrupted recovery be repeated without duplicate effects? |
| FC-TXN-05 | Concurrent operation and cross-user exclusion | H-authority + Core | Owned-root locking slice | [Lifecycle](spec/runtime-lifecycle.md) | Can two users mutate one machine installation concurrently? |
| FC-TXN-06 | Cancellation and privilege-helper loss | Core + H-execution | Worker/cancel slice; elevation planned | [Lifecycle](spec/runtime-lifecycle.md) | Are interrupted operations resolved through journal recovery? |
| FC-TXN-07 | Disk-full, locked-file and permission fault recovery | H-execution | Current slice | [Lifecycle](spec/runtime-lifecycle.md) | Are original failure and recovery failure separately actionable? |
| FC-TXN-08 | Installed-state reconciliation after external damage | H-machine + H-execution | Current slice | [Lifecycle](spec/runtime-lifecycle.md) | Can metadata, active pointer and actual files disagree without false success? |
| FC-TXN-09 | Retained versions and transactional cleanup | H-execution + Product | Recovery cleanup slice; retention planned | [Lifecycle](spec/runtime-lifecycle.md) | Does GC preserve active, recovery-needed and policy-retained versions? |
| FC-TXN-10 | Cross-volume and interrupted platform-operation recovery | H-execution | Planned | [Lifecycle](spec/runtime-lifecycle.md) | Are copy, rename and integration boundaries covered by platform fault tests? |
## Operating-system integrations

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-OS-01 | Managed files and directories | H-content + H-execution | Current slice | [Content](spec/content-container.md) | Are writes and removals confined to the declared ownership boundary? |
| FC-OS-02 | Application shortcuts | H-machine + Stdlib | Independent component | [Independent component](README.md#independent-components) | Are platform-specific shortcuts maintained across update and uninstall? |
| FC-OS-03 | File associations | H-machine + Product | Independent component | [Independent component](README.md#independent-components) | Are platform limits and the user's default-handler choice respected? |
| FC-OS-04 | Application and uninstall registration | H-machine + Stdlib | Independent component | [Independent component](README.md#independent-components) | Does platform capability reporting match actual registration behavior? |
| FC-OS-05 | System services and user agents | H-machine + H-execution | Independent component | [Independent component](README.md#independent-components) | Are supported scopes explicit, with rollback and uninstall cleanup? |
| FC-OS-06 | URL and protocol handlers | H-machine + Product | Planned | [Host design](design/host-primitives-and-stdlib.md) | Are collisions, ownership and unregister behavior specified per platform? |
| FC-OS-07 | PATH and typed environment entries | H-machine + Stdlib | Planned | [Host design](design/host-primitives-and-stdlib.md) | Can uninstall remove only the entry this product owns? |
| FC-OS-08 | Login startup registration | H-machine + Product | Planned | [Host design](design/host-primitives-and-stdlib.md) | Is startup consent visible and removal ownership-aware? |
| FC-OS-09 | Scheduled tasks, firewall rules and privileged integrations | H-machine + H-authority | Planned | [Host design](design/host-primitives-and-stdlib.md) | Does each proposed capability get a closed contract and inverse operation? |
| FC-OS-10 | macOS bundles and Linux desktop/MIME integration | H-content + H-machine | Tree slice; OS registration planned | [Content](spec/content-container.md) | Can immutable native objects retain OS trust and desktop registration? |
## Developer experience

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-DX-01 | Prebuilt tools and a versioned build API | Toolchain | Current slice | [Compiler](spec/compiler-frontends.md) | Can a product team build an installer without building Niobium from source? |
| FC-DX-02 | Desktop, CLI, Electron, Python and service scaffolds | Preset | Planned | [Compiler](spec/compiler-frontends.md) | Does each generated example validate and complete a real install? |
| FC-DX-03 | Typed API completion and source diagnostics | Toolchain | Current slice | [Compiler](spec/compiler-frontends.md) | Does a compiler refusal identify the author object and available source span without changing semantic identity? |
| FC-DX-04 | One documented local packaging workflow | Toolchain | Current slice | [Compiler](spec/compiler-frontends.md) | Can a new author produce a validated installer from an example? |
| FC-DX-05 | Screen preview before release packaging | Toolchain + Stdlib | Planned | [Compiler](spec/compiler-frontends.md) | Does preview use the same renderer and valid product data? |
| FC-DX-06 | Plan preview and read-only validation | Core + Toolchain | Read-only compile slice | [Compiler](spec/compiler-frontends.md) | Can authors inspect effects without writes, elevation or application execution? |
| FC-DX-07 | Compiled model, content and installed-state comparison | Toolchain | Planned | [Compiler](spec/compiler-frontends.md) | Can an author identify which typed call, content identity or owned resource changes? |
| FC-DX-08 | CLI help, structured errors and stable exit codes | Core + Toolchain | Current slice | [Compiler](spec/compiler-frontends.md) | Do GUI, CLI and SDK expose compatible failure categories? |
| FC-DX-09 | CI examples, source maps and troubleshooting documentation | Toolchain | Current slice | [Compiler](spec/compiler-frontends.md) | Can pipeline failures be traced to product inputs and retained evidence? |
| FC-DX-10 | Schema migration and tool/runtime compatibility checks | Toolchain + Core | Current slice | [Compiler](spec/compiler-frontends.md) | Are breaking changes diagnosed before generating or deploying artifacts? |
## End-user experience

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-UX-01 | Welcome, options, progress, error and completion flows | Stdlib + Preset | Shared renderer; v2 binding planned | [UI contract](spec/ui-ir.md) | Does each view reflect engine-confirmed state? |
| FC-UX-02 | Component explanations, dependencies and size estimates | Product + Preset | Planned | [UI contract](spec/ui-ir.md) | Can the user understand the selected features and storage costs? |
| FC-UX-03 | Location selection and permissions/disk-space preflight | H-machine + Product | Planned | [UI contract](spec/ui-ir.md) | Does the installer explain problems before machine mutation? |
| FC-UX-04 | Honest phase progress, throughput and cancellability | Core + Stdlib | Planned | [UI contract](spec/ui-ir.md) | Are unknown estimates shown as unknown and cancellation boundaries explained? |
| FC-UX-05 | Recovery, retry, repair and support actions | Product + Stdlib | Planned | [UI contract](spec/ui-ir.md) | Does the error flow offer only actions valid for the recorded state? |
| FC-UX-06 | Maintenance and in-application update consent | Product + Preset | Planned | [UI contract](spec/ui-ir.md) | Can users distinguish download, apply, restart and activation states? |
| FC-UX-07 | Dark mode, high contrast, DPI and reduced motion | Stdlib | Shared renderer; v2 binding planned | [UI contract](spec/ui-ir.md) | Do appearance settings preserve legibility and interaction behavior? |
| FC-UX-08 | Keyboard access and assistive-technology bridges | Stdlib | Planned | [UI contract](spec/ui-ir.md) | Can screen readers and keyboard users complete the entire lifecycle? |
| FC-UX-09 | Localization, Unicode, IME, shaping and RTL layout | Stdlib | Planned | [UI contract](spec/ui-ir.md) | Are long translations and non-Latin input usable on each target? |
| FC-UX-10 | User-data retention and informed destructive choices | Product + H-authority | Ownership slice; consent policy planned | [Access](spec/access-policy.md) | Are application-owned data and framework-owned deployment files distinguished? |
## Customization and extension boundaries

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-CUS-01 | Product name, publisher, logo, accent and plain text | Product + Preset | Shared branding; v2 UI planned | [UI contract](spec/ui-ir.md) | Does invalid branding fail safely without affecting deployment semantics? |
| FC-CUS-02 | Closed, versioned theme choices | Stdlib + Preset | Planned | [Component](spec/capability-library.md) | Are token changes constrained by accessibility and size gates? |
| FC-CUS-03 | Programmable presets and templates over the typed author model | Preset + Toolchain | V2 mechanism; presets planned | [Component](spec/capability-library.md) | Can evaluated presets produce ordinary compiled products without shipping the author program? |
| FC-CUS-04 | Validated product and component presentation metadata | Product + Preset | Planned | [Component](spec/capability-library.md) | Can descriptions vary without executable markup or layout code? |
| FC-CUS-05 | Framework-maintained screens and component evolution | Stdlib | Planned | [Component](spec/capability-library.md) | Does each addition update UI contracts, semantics and goldens? |
| FC-CUS-06 | Typed policy defaults and enterprise branding | Product + Preset | Planned | [Component](spec/capability-library.md) | Are policy-controlled choices visible and still validated? |
| FC-CUS-07 | Fixed official and third-party Wasm capability libraries | Stdlib + Core | V2 mechanism; presets planned | [Component](spec/capability-library.md) | Can an independent standard Component control output without native runtime changes or added authority? |
| FC-CUS-08 | Selectable prebuilt runtime profiles and fixed library sets | Toolchain + Core | V2 mechanism; presets planned | [Component](spec/capability-library.md) | Are missing primitives refused, and are profile/library identities preserved without product-specific relinking? |
| FC-CUS-09 | Build-pipeline adapters and artifact exporters | Toolchain | Planned | [Component](spec/capability-library.md) | Can adapters run outside the installer without weakening its contracts? |
| FC-CUS-10 | App Bootstrap and host-application experience integration | Product + H-execution | Planned | [Host design](design/host-primitives-and-stdlib.md) | Does product logic stay in the application with the documented privilege boundary? |
## SDK and application integration

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-SDK-01 | Static and dynamic Distribution Core libraries | Core + Toolchain | Retained embedding scope | [Embedding retained](spec/authoring-c-abi.md) | Can hosts consume a versioned ABI without installer UI dependencies? |
| FC-SDK-02 | Update check, resolve, fetch, stage and commit | Core + Stdlib | Retained embedding scope | [Embedding retained](spec/authoring-c-abi.md) | Are call order, lock lifetime and no-op behavior tested through the public API? |
| FC-SDK-03 | Events, cancellation and structured error retrieval | Core + Toolchain | Retained embedding scope | [Embedding retained](spec/authoring-c-abi.md) | Are callback lifetimes and cancellation behavior defined and tested? |
| FC-SDK-04 | Portable resolution and execution | H-execution + Stdlib | Retained embedding scope | [Embedding retained](spec/authoring-c-abi.md) | Are process outcomes returned without hiding framework failures? |
| FC-SDK-05 | Node-API and Electron bindings | Toolchain | Planned | [Embedding retained](spec/authoring-c-abi.md) | Can packaged applications exercise the same engine and trust path? |
| FC-SDK-06 | Python, .NET, Rust, Go and C/C++ consumption examples | Toolchain | Zig/C/Starlark author slice | [Author ABI](spec/authoring-c-abi.md) | Do examples verify ABI layout, ownership and error handling? |
| FC-SDK-07 | Application-owned update scheduling and UI | Product | Planned | [Embedding retained](spec/authoring-c-abi.md) | Can the application control timing while the core controls deployment? |
| FC-SDK-08 | Host privilege and machine-scope policy | H-authority | Retained embedding scope | [Embedding retained](spec/authoring-c-abi.md) | Does an unprivileged library host receive the documented error? |
| FC-SDK-09 | Threading, reentrancy and API compatibility guarantees | Core + Toolchain | Single-thread author contract; embedding retained | [Author ABI](spec/authoring-c-abi.md) | Are unsupported concurrent calls rejected and binary compatibility checked? |
| FC-SDK-10 | Business activation, settings and data migration | Product | Planned | [Embedding retained](spec/authoring-c-abi.md) | Does application failure remain separate from machine-deployment success? |
## Enterprise administration

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-ADM-01 | Silent install, update, repair and uninstall | Product + H-execution | Headless lifecycle slice | [Lifecycle](spec/runtime-lifecycle.md) | Can operators complete the lifecycle with machine-readable outcomes? |
| FC-ADM-02 | Explicit license-agreement acceptance policy | Product + Preset | Planned | [Journey design](design/product-journeys.md) | Can unattended operation record the agreed document and applicable policy? |
| FC-ADM-03 | Desired component configuration import/export | Product + Toolchain | Typed inputs slice; fleet formats planned | [Program](spec/program-image.md) | Does a shared configuration reproduce selection across compatible hosts? |
| FC-ADM-04 | Channel pinning and update policy | Product + Stdlib | Planned | [Journey design](design/product-journeys.md) | Are application versions and authorized release sequences handled separately? |
| FC-ADM-05 | Managed offline repositories and air-gap provisioning | Product + Stdlib | Planned | [Journey design](design/product-journeys.md) | Can operators distribute validated media and refresh trust metadata? |
| FC-ADM-06 | Maintenance windows and restart deferral | Product | Planned | [Journey design](design/product-journeys.md) | Does external scheduling respect transaction and consent boundaries? |
| FC-ADM-07 | Device-management and package-manager integration | Product + Toolchain | Planned | [Journey design](design/product-journeys.md) | Are detection, exit-code and uninstall rules documented for each integration? |
| FC-ADM-08 | Fleet inventory and configuration-drift export | H-machine + Product | Planned | [Journey design](design/product-journeys.md) | Can operators consume local state without collecting application secrets? |
| FC-ADM-09 | Policy provenance and audit records | Product + Core | Planned | [Journey design](design/product-journeys.md) | Can an operator explain which policy authorized the deployed selection? |
| FC-ADM-10 | Multiuser and shared-machine deployment | H-authority + Product | Planned | [Journey design](design/product-journeys.md) | Are discovery, access control and integration ownership correct for every user? |
## Runtime security and trust

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-SEC-01 | Strict bounded compiled contracts and forbidden authority rejection | Core + Toolchain | Current slice | [Program](spec/program-image.md) | Do malformed data, unknown versions and unauthorized imports fail before mutation? |
| FC-SEC-02 | TUF signatures, delegation and target authorization | Stdlib + Core | Independent component | [TUF retained](spec/tuf-profile.md) | Can unauthorized release metadata or payloads reach deployment? |
| FC-SEC-03 | Rollback, freeze and metadata-mixing defenses | Stdlib + Core | Independent component | [TUF retained](spec/tuf-profile.md) | Are replayed or inconsistent trust states rejected? |
| FC-SEC-04 | OS publisher signatures and macOS notarization | Toolchain + Product | Image integrity slice; publisher planned | [Image](spec/setup-image.md) | Are signatures checked on the exact distributed native objects? |
| FC-SEC-05 | Root-confined extraction and archive-bomb defenses | H-content + H-authority | Current slice | [Content](spec/content-container.md) | Do malicious archives fail without writes outside staging? |
| FC-SEC-06 | Least privilege and closed helper operations | H-authority | User/worker slice; elevation planned | [Access](spec/access-policy.md) | Can malformed IPC or a lost helper cause unauthorized mutation? |
| FC-SEC-07 | Cache, staging and path-race attack resistance | H-authority + H-content | Current slice | [Content](spec/content-container.md) | Are attacker-controlled links, replacements and shared paths rejected? |
| FC-SEC-08 | Ownership-aware cleanup and integration collision policy | H-authority | Owned files slice; integrations retained | [Access](spec/access-policy.md) | Can update or uninstall overwrite another product's resources? |
| FC-SEC-09 | Redacted logs, minimal process environment and privacy policy | Core + Product | Planned | [Boundary](adr/0023-standard-content-and-component-contracts.md) | Are secrets and sensitive identifiers absent from retained diagnostics? |
| FC-SEC-10 | Threat model and independent security review | Toolchain + Product | Planned | [Boundary](adr/0023-standard-content-and-component-contracts.md) | Are trust boundaries reviewed separately from implementation claims? |
## Security scanning and release gates

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-SCAN-01 | Framework and native-dependency SAST/SCA | Toolchain | Planned | [Test system](spec/test-system.md) | Can source findings and dependency advisories be traced to shipped bytes? |
| FC-SCAN-02 | Application-payload dependency and vulnerability scanning | Product + Toolchain | Planned | [Test system](spec/test-system.md) | Are nested native, Electron and Python dependencies inventoried? |
| FC-SCAN-03 | SBOM generation, merge and export | Toolchain | Planned | [Test system](spec/test-system.md) | Are framework, embedded libraries and product payloads represented without identity loss? |
| FC-SCAN-04 | Open-source license and notice analysis | Product + Toolchain | Planned | [Test system](spec/test-system.md) | Are obligations, unknown licenses and notice omissions visible? |
| FC-SCAN-05 | Secret, credential and private-key scanning | Toolchain | Planned | [Test system](spec/test-system.md) | Does the gate reject credentials accidentally packaged in payloads or configs? |
| FC-SCAN-06 | Malware and sandbox checks of final signed artifacts | Product + Toolchain | Planned | [Test system](spec/test-system.md) | Is the scan tied to the distributed digest and is upload consent explicit? |
| FC-SCAN-07 | Binary hardening, signatures and dynamic-dependency inspection | Toolchain | Shared binary gates | [Test system](spec/test-system.md) | Do final binaries satisfy platform protection and dependency policies? |
| FC-SCAN-08 | Digest-bound reports and build-provenance attestations | Toolchain | Shared evidence tools; release policy planned | [Test system](spec/test-system.md) | Can altered reports, subjects or builder identities pass release verification? |
| FC-SCAN-09 | Gate policy, VEX and expiring finding exceptions | Product + Toolchain | Shared evidence tools; release policy planned | [Test system](spec/test-system.md) | Are exceptions attributable, scoped and expired without changing test outcomes? |
| FC-SCAN-10 | Post-release rescanning and offline advisory freshness | Product + Toolchain | Planned | [Test system](spec/test-system.md) | Can new advisories trigger action without modifying immutable artifacts? |
## Operations, compliance and support

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-OPS-01 | Structured phase events and installation logs | Core + Stdlib | CLI diagnostics slice; event binding planned | [Lifecycle](spec/runtime-lifecycle.md) | Can support distinguish trust, transport, filesystem and application failures? |
| FC-OPS-02 | Crash diagnostics and redacted support bundles | Core + Product | Planned | [Journey design](design/product-journeys.md) | Does export preserve useful evidence without disclosing secrets? |
| FC-OPS-03 | Opt-in telemetry, consent and retention controls | Product | Planned | [Journey design](design/product-journeys.md) | Can the product operate with telemetry disabled and consent revoked? |
| FC-OPS-04 | Release inventory and audit evidence retention | Product + Toolchain | Shared tool/evidence mechanisms | [Test system](spec/test-system.md) | Can installed releases be traced to signed artifacts and test reports? |
| FC-OPS-05 | Vulnerability disclosure and incident response | Product | Planned | [Journey design](design/product-journeys.md) | Are reporting, triage, withdrawal and recovery responsibilities explicit? |
| FC-OPS-06 | Maintainer key backup and disaster recovery | Product | Planned | [Journey design](design/product-journeys.md) | Can recovery restore authorized publication without recreating past artifacts? |
| FC-OPS-07 | Product entitlement and commercial-license integrations | Product | Planned | [Journey design](design/product-journeys.md) | Does application-owned activation avoid blocking transaction recovery? |
| FC-OPS-08 | Upgrade/uninstall user-data policy documentation | Product | Planned | [Journey design](design/product-journeys.md) | Can users predict data retention independently of deployment ownership? |
| FC-OPS-09 | Toolchain and dependency support lifecycle | Toolchain | Shared tool/evidence mechanisms | [Test system](spec/test-system.md) | Are upstream advisories and end-of-support dates assigned to maintainers? |
| FC-OPS-10 | Accessibility, legal and export/compliance evidence | Product | Planned | [Journey design](design/product-journeys.md) | Are jurisdiction-specific conclusions reviewed by the responsible operator? |
## Quality, portability and performance

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-QA-01 | Static, unit, fault, contract, scenario and real-OS lanes | Toolchain | Shared and v2 lanes | [Test system](spec/test-system.md) | Does each claimed capability identify the lane that actually ran? |
| FC-QA-02 | Install/update/repair/uninstall and portable scenario matrix | Toolchain | Current slice; full matrix planned | [Test system](spec/test-system.md) | Are online, offline and interrupted paths covered across profiles? |
| FC-QA-03 | Kill points, seeded simulation and malicious-input fuzzing | Toolchain + Core | Shared and v2 lanes | [Test system](spec/test-system.md) | Do recovery and parser invariants hold under repeated faults? |
| FC-QA-04 | OS/architecture/scope tiers and real-machine evidence | Toolchain | Shared and v2 lanes | [Test system](spec/test-system.md) | Are platform claims gated by actual contract and OS evidence? |
| FC-QA-05 | UI golden, accessibility and worst-case content coverage | Toolchain + Stdlib | Planned | [Test system](spec/test-system.md) | Are focus, scale, contrast and text overflow checked without blanket snapshot updates? |
| FC-QA-06 | Public ABI, schema and CLI compatibility tests | Toolchain | Current slice; full matrix planned | [Test system](spec/test-system.md) | Do older consumers retain their documented behavior? |
| FC-QA-07 | Installer size, memory, CPU and dependency budgets | Toolchain + Core | Current slice; full matrix planned | [Test system](spec/test-system.md) | Are budgets explicit and measured on release artifacts? |
| FC-QA-08 | Startup, download, extraction and recovery benchmarks | Toolchain | Planned | [Test system](spec/test-system.md) | Are phase costs measured for small, large and many-file payloads? |
| FC-QA-09 | Clean-host installation and final-byte release qualification | Product + Toolchain | Planned | [Test system](spec/test-system.md) | Are signed and notarized shipping artifacts tested rather than rebuilt substitutes? |
| FC-QA-10 | Cold-cache, warm-cache and constrained-environment tests | Toolchain | Planned | [Test system](spec/test-system.md) | Are low disk space, slow networks, offline hosts and unavailable dependencies covered? |
## Technology compatibility assessment

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-COMP-01 | Native C/C++/Rust/Go application payloads | Toolchain + H-content | Generic tree slice; product qualification planned | [Content](spec/content-container.md) | Do producer-built native objects survive packaging with identity and trust intact? |
| FC-COMP-02 | Electron payloads and a single update owner | Product + H-content | Generic tree slice; product qualification planned | [Content](spec/content-container.md) | Can the application avoid concurrent Squirrel/NSIS and Niobium maintenance? |
| FC-COMP-03 | PyInstaller onedir/onefile payloads | Product + H-content | Generic tree slice; product qualification planned | [Content](spec/content-container.md) | Are bootloader extraction, bundled libraries and privilege behavior qualified? |
| FC-COMP-04 | Qt applications independent of Qt IFW | Product + H-content | Generic tree slice; product qualification planned | [Content](spec/content-container.md) | Can native Qt application objects be deployed through Niobium contracts? |
| FC-COMP-05 | Existing NSIS/Inno/MSI installation migration | Product + H-authority | Planned | [Journey design](design/product-journeys.md) | Can discovery and ownership transfer occur without executing arbitrary old installers? |
| FC-COMP-06 | CMake/CPack and other producer build integration | Toolchain | Typed author/build slice | [Compiler](spec/compiler-frontends.md) | Can CI consume ordinary Niobium artifacts without runtime coupling? |
| FC-COMP-07 | .NET/Java/Python runtime prerequisites | Product + H-machine | Planned | [Journey design](design/product-journeys.md) | Are runtimes bundled or externally provisioned under explicit ownership? |
| FC-COMP-08 | Windows native formats and deployment coexistence | Product + Toolchain | Planned | [Journey design](design/product-journeys.md) | Are MSI/MSIX restrictions, ownership and update responsibility documented? |
| FC-COMP-09 | macOS app/DMG/PKG signing workflow coexistence | Product + Toolchain | Planned | [Journey design](design/product-journeys.md) | Does wrapping preserve the tested app signature and notarization result? |
| FC-COMP-10 | Linux package managers, AppImage and desktop coexistence | Product + Toolchain | Planned | [Journey design](design/product-journeys.md) | Is each package lifecycle owned by one manager with explicit interoperability? |
## Explicit exclusions

| ID | Capability | Owner | Current implementation scope | Contract/design owner | Acceptance question |
|---|---|---|---|---|---|
| FC-OUT-01 | Runtime author source and unrestricted command fields | Core | Excluded | [Boundary](adr/0023-standard-content-and-component-contracts.md) | Do author programs stay at build time, with no generic shell authority in compiled data? |
| FC-OUT-02 | Ambient native plugin discovery and arbitrary DLL loading | Core + H-authority | Excluded | [Boundary](adr/0023-standard-content-and-component-contracts.md) | Are fixed standard Wasm libraries distinguished from unrestricted native loading or ambient authority? |
| FC-OUT-03 | Unconstrained imperative preinstall/postinstall hooks | Core + H-execution | Excluded | [Boundary](adr/0023-standard-content-and-component-contracts.md) | Do libraries propose declared effects while recovery remains independent of guest or hook execution? |
| FC-OUT-04 | Arbitrary nested installer execution and custom elevated actions | H-authority + H-execution | Excluded | [Boundary](adr/0023-standard-content-and-component-contracts.md) | Can downloaded EXE/MSI packages become generic privileged operations? |
| FC-OUT-05 | HTML/CSS/QML/JavaScript product-defined installer layouts | Stdlib + Preset | Excluded | [Boundary](adr/0023-standard-content-and-component-contracts.md) | Does customization stay within the closed renderer and validated data model? |
| FC-OUT-06 | In-place rewriting of active artifacts or unsigned emergency updates | Core + H-authority | Excluded | [Boundary](adr/0023-standard-content-and-component-contracts.md) | Can any escape hatch bypass immutable artifacts or release trust? |
| FC-OUT-07 | Kernel ownership of product databases, language compilation or license servers | Product | Excluded | [Boundary](adr/0023-standard-content-and-component-contracts.md) | Are application semantics and producer compilation assigned to product libraries or producer tools? |
| FC-OUT-08 | Mandatory runtime cloud scanning or automatic private-payload upload | Product | Excluded | [Boundary](adr/0023-standard-content-and-component-contracts.md) | Can installation work without turning scanning services into release trust authorities? |

## Handoff and evidence

Every delivered slice links a versioned contract, actual implementation, positive
and negative scenario, platform/scope matrix and digest-bound evidence. Existing
FC IDs remain stable references; they are not acceptance IDs. No old evidence is
promoted into v2 coverage by changing this table.

Product-level dependency remediation, component families, workload expansion,
coexistence and native application wrapping remain library/preset decisions.
Machine observation reports what is known, absent or unsupported. Detection of a
shared SDK or external package does not adopt its files or authorize uninstall.
A native application, language bundle or installer-produced tree is an ordinary
fixed input; Niobium is not coupled to the producer's packer.

Release scanning, entitlement, enterprise scheduling and operator compliance
remain separate owners. Their integrations must preserve fixed artifact identity,
user consent and the runtime authority boundary. A scanner outage is never a
clean result, and publisher signing does not replace lifecycle qualification.
