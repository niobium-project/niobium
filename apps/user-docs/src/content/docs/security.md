---
title: Security
description: Component authority, integrity and publisher trust, and vulnerability reporting.
tableOfContents:
  maxHeadingLevel: 2
---

## Current Component profile

The current installer packages a typed product model, fixed capability Components,
and content with checked identities. Author source executes during the build.
Libraries receive bounded typed inputs and explicit grants; they have no ambient
filesystem, network, process, or elevation authority.

The host validates desired resources and native access before freezing a durable
plan. Recovery uses that plan without reevaluating author code or Components.
See [authority and access](/concepts/privilege/) and
[transactions and recovery](/concepts/transactions/) for these boundaries.

## Integrity and publisher trust

A lock digest identifies input bytes. Setup image hashes check internal consistency;
self-declared hashes do not authenticate the publisher. The build trusts its author
source, selected dependencies, toolchain, and runtime publisher.

The [locked input contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/compiler-inputs.md)
and [setup image contract](https://github.com/niobium-project/niobium/blob/main/docs/spec/setup-image.md)
define these checks. Current execution evidence and outstanding signing,
notarization, and machine-scope work are on [Status and platforms](/status/).
Independent TUF trust tests do not establish current runtime integration.
