---
title: Glossary
description: Authoring, capability and deployment terms used by Niobium.
---

The canonical [GLOSSARY.md](https://github.com/niobium-project/niobium/blob/main/GLOSSARY.md) owns the domain vocabulary. Historical v1 pages retain local definitions of their manifest and engine interfaces.

| Term | Meaning |
|---|---|
| Author program | Build-time source constructing a typed product model |
| Compiler | Toolchain that validates the model, fixes dependencies and assembles setup |
| Compiled program | Immutable product representation consumed by runtime |
| Runtime | Independently built host for programs and capability libraries |
| Setup | Product installer containing runtime, program and fixed dependencies |
| Capability contract | Interface and lifecycle obligations for a domain capability |
| Capability library | Fixed implementation of capability contracts |
| Capability instance | Bound use of a library with separate inputs, resources and state |
| Host primitive | Versioned host mechanism with explicit authority and effects |
| Standard library | Official libraries using the same contracts as product libraries |
| Preset | Build-time composition of libraries and product conventions |
| Component / workload | Product-defined deployment unit / component selection for a task |
| Resource | Stable, owned entity managed through a capability |
| Frozen plan | Durable operations and content used for execution and recovery |
| Migration | Explicit conversion between product or library state versions |
| Bridge release | Product-declared intermediate step in an upgrade path |

[The roadmap](/roadmap/) identifies which parts belong to the executable baseline and which need subsequent implementation.
