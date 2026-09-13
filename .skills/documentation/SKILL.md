---
name: documentation
description: Update FollowScript README, AGENTS guidance, architecture, behavioural, privacy, testing, decision, or project-local skill documentation.
---

# Documentation

## Purpose and use

Use when behaviour, architecture, workflow or privacy claims change. Inputs are implemented code and verified results. Outputs are concise documentation describing current reality, limitations and evidence.

## Workflow

1. Inspect the implementation and tests; do not document intended-only behaviour as complete.
2. Route details to the focused file under `docs/`; keep README useful as an entry point and AGENTS concise.
3. Use Australian English and consistent names from source.
4. Distinguish automated, simulator and physical-device verification.
5. Check links, commands, versions and tuning constants against the repository.

## Validation checklist

- Architecture and data-flow boundaries match source.
- Alignment constants and behaviour match `Configuration`.
- Privacy wording distinguishes guarantees from OS-dependent behaviour.
- Commands and supported versions are current.
- Limitations and unverified device behaviour are explicit.

## Common failures

Avoid aspirational claims, duplicated explanations that drift, stale test counts, undocumented tuning changes, and presenting an unrun checklist as verification.
