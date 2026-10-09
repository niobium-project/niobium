---
title: About the project
description: Why Niobium exists, who maintains it, and what support to expect.
---

Niobium is an independent open source installer framework maintained by one person in spare time. Maintenance is best effort, with a focused scope and a short platform list.

## Background

The project grew out of installer needs the author encountered while working at TongYuan, including internal, experimental and commercial products. Niobium is a general-purpose framework with no product-specific dependencies.

Niobium is maintained independently and is not part of TongYuan's commercial products. TongYuan provides no direct support or direction for the project.

## Maintenance strategy

- **Best effort, no service level.** There is one maintainer and no guaranteed response time for issues, pull requests or questions.
- **Explicit capability boundaries.** Products extend installers through language SDKs, Starlark and fixed Wasm capability libraries. The host controls machine authority, resource ownership and transaction recovery. See the [project overview](/).
- **Few platforms, done properly.** Effort goes to the Tier 1 platforms first; the tiers and the roadmap are on [Platform support](/platforms/).
- **Security reports** follow the process on [Security](/security/).

- **Early draft.** Not usable yet; no compatibility guarantees for framework APIs, formats, persistent state or tools. Breaking updates may happen at any time. External contributions are not accepted.
