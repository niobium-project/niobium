Package: apple-codesign
Version: 0.29.0
Upstream: https://github.com/indygreg/apple-platform-rs
Release: https://github.com/indygreg/apple-platform-rs/releases/tag/apple-codesign/0.29.0
License: MPL-2.0 for apple-codesign; bundled dependency notices are in each archive's COPYING.
Integrity: toolchain.zon pins archive SHA-256 values, verified against published .sha256 files.
Use: host-side Mach-O ad-hoc signing after final product assembly.
Patches: none.

The fetched COPYING file accompanies the executable; upstream source and binaries
are not committed here. Product builds lock the exact signer executable as a tool
input and invoke its captured private copy. The upstream verify command does not
qualify ad-hoc signatures in this release. The image module verifies the supported
standard ad-hoc representation, and native qualification checks the same bytes
with Apple's codesign. Publisher CMS signatures, Developer ID and notarization
require their own qualified finalizer.
