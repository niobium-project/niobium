# Runtime publication package v2

- **Status:** Normative contract; execution qualification is recorded separately in [acceptance v0.3](../acceptance-plan.md).
- **Owner:** Compiler input resolution and native runtime publication.
- **Decision:** [ADR-0025](../adr/0025-baseline-cpu-runtime-publication.md).
- **Schema:** [runtime-package-v2](../../api/schema/runtime-package-v2.schema.json).

## Identity and declarations

A runtime package binds an explicit native CPU/ABI declaration and the supported
runtime profile to exact template bytes. It is a publisher output consumed through
the [input lock](compiler-inputs.md). It is independent of the author model,
guest WIT ABI and durable installation state.

| Field | Type | Usage |
|---|---|---|
| `schema` | Integer, exactly `2` | Required wire version |
| `version` | Nonempty UTF-8 string, at most 128 bytes | Matches both locked publication versions |
| `template_sha256` | 64 hexadecimal characters | Identity of the complete precompiled template |
| `template_bytes` | Integer, 1 through 16 GiB | Exact template length |
| `native_profile` | Versioned identifier from the table below | Required publisher CPU and ABI declaration |
| `profile` | [Runtime profile](program-image.md) | Target, contract versions and provided primitives |

Unknown fields, duplicate keys, unsupported versions and invalid profile/target
combinations fail closed. The complete JSON envelope is at most 1 MiB. Schema 1
packages have no minimum CPU declaration and are rejected; they are not upgraded
by assuming the publisher used baseline settings.

## Native CPU and ABI profiles

| Identifier | Native ABI | Minimum CPU configuration |
|---|---|---|
| `aarch64-macos-baseline-v1` | Darwin arm64 | Apple M1, as defined by the pinned Zig and Rust targets |
| `x86_64-linux-gnu-baseline-v1` | GNU x86-64 | x86-64 baseline, without mandatory AVX, SSE4a or SHA extensions |
| `x86_64-linux-musl-baseline-v1` | musl x86-64 | x86-64 baseline, without mandatory AVX, SSE4a or SHA extensions |
| `x86_64-windows-gnu-baseline-v1` | GNU Windows x86-64 | x86-64 plus Rust target requirements `cmpxchg16b`, `sse3` and `lahfsahf` |

These names describe versioned publication contracts, not build-host CPU models.
All native code generators and supplied archives must satisfy the selected
contract. Advanced instructions behind correct runtime feature detection are
permitted; unconditionally executed code must meet the declared minimum.
OS, loader, system-library and symbol-version prerequisites remain governed by
[ADR-0024](../adr/0024-native-runtime-dependency-qualification.md). No MSVC profile
is qualified. A new mandatory CPU feature requires a different profile identifier
and execution evidence.

## Publication and consumption

`runtime-package --native-profile ID` receives the declaration from the publisher's
explicit build configuration. The compiler checks the template's OS, architecture
and reserved descriptor, and binds the declaration to its measured digest. Native
headers cannot establish the instruction set used throughout an executable; this
command does not certify the truth of a CPU declaration or execute the target.

The publisher must retain effective Zig, Rust, C and Go target settings where
applicable, controlled flag/wrapper provenance, external archive identities and
final-byte execution evidence. A host SDK inventory records its executable and
static-library identities and requirements separately. A template's declaration
does not qualify an unrelated compiler, worker, witness or prebuilt signing tool.

Resolution verifies the locked metadata digest, the runtime's metadata dependency,
template digest/length, both publication versions and target agreement. Trusted
acquisition establishes publisher authority separately. Cross-host assembly
consumes the declared fixed template; it never substitutes the
assembler host's CPU features or executes the target to inspect capabilities.

## Validation

`N2-PROFILE-03` covers required declarations, unknown versions/profiles, target
mismatches and native/schema agreement. `N2-CPU-01` covers effective publication
settings and hostile ambient flags. `N2-CPU-02` executes exact transferred SDK and
setup bytes in a recorded CPU context lacking the original failing extensions.
Compilation, schema conformance and execution are separate evidence claims.
