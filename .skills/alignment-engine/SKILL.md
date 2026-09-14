---
name: alignment-engine
description: Change FollowScript tokenisation, normalisation, matching, confidence, tracking, reacquisition, or alignment regression fixtures.
---

# Alignment engine

## Purpose and use

Use for changes under `FollowScript/Models`, `FollowScript/Alignment`, or alignment fixtures. Inputs are the intended behavioural change and representative recognition/script sequences. Outputs are deterministic implementation, regression coverage and current algorithm documentation.

## Conventions

- Preserve the original script and UTF-16 source ranges; matching uses normalised tokens.
- Keep `ScriptAlignmentEngine` deterministic, `Sendable`, and independent of Speech/UI types.
- Once an initial position exists, candidate endpoints and committed positions are forward-only. Scoring context may begin behind the committed anchor when needed to align a cumulative streaming-ASR window, but automatic alignment must never commit or display a matched endpoint behind the anchor.
- During tracking, bound endpoint search around the prior position. Enter global search only after sustained evidence of positional loss rather than ordinary low-confidence local partial refinement, and guard large jumps.
- Name and document tuning constants in `Configuration`; do not scatter literals.

## Workflow

1. Read `docs/alignment-engine.md` and the relevant tests/fixture.
2. Reproduce the behaviour with a deterministic failing test; use a sequential fixture for temporal problems.
3. Make the smallest algorithm or tuning change that addresses the evidence.
4. Run `swift test`, then build the iOS target.
5. Update `docs/alignment-engine.md` whenever behaviour, scoring or a constant changes.

## Validation checklist

- Source mapping and normalisation tests pass.
- Omissions, insertions, fillers, repetition, monotonic endpoints, streaming-ASR context overlap and forward skips remain covered.
- Plausible local partial refinement does not trigger global reacquisition by itself.
- Repeated implausible evidence can still trigger reacquisition.
- One weak update cannot trigger a distant jump.
- Local tracking does not rescore the entire script.
- Exact commands and results are reported.

## Common failures

Short fragments can inflate similarity; repeated phrases can defeat continuity; cumulative ASR context can be penalised if earlier recognised words are excluded from scoring; aggressively low thresholds can jump globally; aggressively high thresholds can freeze. Never hide a known regression by weakening an assertion without checking the intended token endpoint.
