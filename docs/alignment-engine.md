# Alignment engine

## Online tracking model

`ScriptAlignmentEngine` is a deterministic, framework-neutral online sequence tracker. Each recognition update scores candidate script ranges, keeps the best candidate for each endpoint, and retains a beam of up to seven endpoints in `AlignmentState`. The next update combines lexical evidence with a transition score instead of treating each transcript independently.

Tokenisation treats punctuation as a word boundary and excludes it from matching. This applies to ASCII and Unicode punctuation, including hyphens, dashes, colons, slashes, brackets and sentence marks. Apostrophes may remain inside a source token so contractions retain one source range, but are removed from its normalised matching form. The prompting copy collapses whitespace and inserts a missing single space when a period is immediately followed by an uppercase sentence start; this avoids changing decimals, filenames and conventional lower-case abbreviations. The editor's stored source remains unchanged, and token source ranges refer to the prepared prompting copy.

`estimatedTokenIndex` is the responsive estimate of the last spoken token. The view model presents the following token as the bright next-word cue when one exists. `committedTokenIndex` is the stable monotonic anchor used for scrolling. An estimate requires confidence of `0.48`. A local commit requires `0.64`; global reacquisition requires `0.66`, while a distant jump requires `0.74`, at least three recognised tokens and distinctive evidence. Confident multi-word partial and final results use the matched endpoint, avoiding an artificial one-word delay during faster delivery. A single-word partial retains a one-token lag so an ambiguous word cannot prematurely pull an established position forward.

## Evidence score

The recognition window remains the last 16 non-filler tokens. Candidate lengths are within four tokens of that window. Lexical evidence combines:

```text
0.38 × normalised edit similarity
+ 0.25 × LCS / longer sequence
+ 0.17 × LCS / recognised sequence
+ 0.20 × distinctiveness-weighted coverage
```

Distinctiveness uses a within-script IDF-like weight: `1 + 0.28 × log((token count + 1) / (word frequency + 1))`. Rare words therefore resolve repeated/common wording more strongly without making common words useless. When multiple ASR hypotheses are supplied, the strongest confidence-weighted lexical observation contributes. `AlignmentObservation` also reserves optional phonetic tokens for a future lightweight implementation; they are not scored yet.

### Streaming-ASR context overlap

Speech recognition commonly emits cumulative partial transcripts whose current 16-token window still contains words spoken before FollowScript's committed anchor. Candidate **endpoints** remain forward-only from the committed position, but the candidate range used for lexical scoring may begin behind the anchor by up to `recognised token count - 1` tokens. This allows the full cumulative recognition window to contribute evidence instead of forcing earlier recognised words to mismatch merely because scrolling has already advanced.

Only scoring context overlaps backwards. `estimatedTokenIndex`, `committedTokenIndex` and the displayed matched range remain monotonic: the displayed range is clamped to begin at or after the existing committed anchor. Stale recognition therefore cannot move the prompt backwards.

## Transitions, clustering and timing

Candidate evidence contributes 80%, the transition model 16% and the retained parent score 4% when an anchor exists. A forward candidate within one token of the recognised phrase length receives a `0.035` continuity bonus. Staying is cheap, while backward beam transitions lose `0.28` before the existing `0.10` per-token repetition penalty. Progressively larger forward omissions/skips incur `0.012` per token, and distant global jumps add `0.12`. When audio time is available, movement beyond the estimated speaking distance plus four tokens receives an additional penalty. The engine starts at 2.6 tokens/second and smooths observed committed progress, clamped to 1–5.5 tokens/second.

Candidate endpoints within three tokens of the selected endpoint are treated as one positional cluster. Ambiguity therefore compares the selected cluster against the strongest competing candidate outside that cluster rather than against the immediately adjacent runner-up. Nearby endpoints such as `290`, `291` and `292` express one location hypothesis; endpoints such as `455` and `467` remain separate competing locations.

While tracking locally, continuity gets one additional tie-breaker. If the raw best endpoint lies beyond the normal phrase-length progression window, but a candidate within `recognised token count + 1` positions of the committed anchor scores within `0.05`, FollowScript prefers that nearby candidate. This only applies in local follow mode. Global reacquisition still chooses from the full forward endpoint search and therefore remains able to recover after a genuine omission or skipped passage.

Repetition is represented by keeping the current/nearby beam hypotheses and a low cost for staying. Candidate endpoints remain forward-only from the committed anchor even when their lexical scoring ranges overlap earlier context. A user-selected anchor remains the explicit way to move backwards.

## Reacquisition and safety

Tracking searches only the next 80 candidate endpoints. Reacquisition is now driven by sustained evidence of **positional loss**, not by every low-confidence partial. A held local candidate is treated as plausible local persistence when its endpoint remains within the recognised-token count plus four tokens of the committed anchor and its raw score is at least `0.35`. Such a hold may place the presentation in the `uncertain` state, but it resets the positional-loss counter and remains in local search. This is intended for normal streaming refinements such as `H` → `Hold` → `Holdsworth` or partial word construction such as `anal` → `analysis`.

Two consecutive held updates that do not have plausible local evidence still enter reacquisition and expand endpoint search from the committed position to the end of the script. Empty recognition and the harmless wait for enough initial partial tokens do not count as positional loss once an anchor exists.

Tentative and committed movement beyond the recognised-token count plus four tokens requires at least three recognised tokens, confidence of `0.74`, and distinctive coverage—even when the candidate is less than 80 tokens ahead. This prevents a retained distant beam hypothesis and a single common partial such as “you'll” from moving the prompt. A local update cannot exceed the same advance budget; a genuine larger omission must first produce sustained positional disagreement, enter reacquisition and then provide distinctive evidence.

A candidate at least five tokens ahead is treated as ambiguous when the selected positional cluster leads the strongest distant cluster by less than `0.035`. Adjacent candidate endpoints no longer create false ambiguity by themselves. In local follow mode, the continuity preference described above can deliberately resolve a close contest in favour of the nearby cluster. There is still no absolute maximum forward jump: distinctive global reacquisition remains the mechanism for legitimate large catch-up movement.

## Decision trace

When “Log timestamped tracking info” is enabled in Settings, the `TrackingDecision` unified-log category records meaningful tracking decisions rather than only successful position changes. It logs advances, rejected/held updates, tracking-state or search-mode transitions, entry to and exit from reacquisition, and local continuity-preference decisions. Empty recognition and the harmless initial single-token partial wait are suppressed unless another meaningful transition occurs. The option remains off by default.

Each record separates the stages that were previously conflated:

- `raw_best` is the highest-scoring retained candidate before the local continuity tie-breaker.
- `selected_match` is the candidate endpoint selected by the alignment decision before commit lag/holdback.
- `cluster` is the three-token-radius positional neighbourhood around `selected_match` used for diagnostic interpretation.
- `distant_competitor` is the strongest displayed candidate outside that neighbourhood. `outsideTop3` means the engine calculated a cluster margin against a retained beam candidate that was not one of the three candidates printed in the compact log.
- `cluster_margin` is the selected positional cluster's score minus the strongest genuinely distant candidate used by the engine. `n/a` means no distant competitor was retained.
- `committed` is the stable scrolling anchor after any partial-result lag or hold.
- `adjustment` explains why `raw_best`, `selected_match` and `committed` differ. Values can include `continuityPreference`, `singleWordPartialLag`, `commitHoldback` and `hold`.
- `mode` is `local` or `global`; `tracking` is `tracking`, `uncertain` or `reacquiring`. `mode_transition` and `state_transition` make changes explicit.
- `event` summarises the significant occurrence as `advance`, `hold`, `continuityPreference`, `reacquisitionEnter` or `reacquisitionExit`.

The existing decision reasons retain their meaning. `localAdvanceTooLarge` means a short update attempted to move beyond its local budget; continued distinctive speech should allow global reacquisition. `distantJumpNeedsDistinctiveEvidence` means global search found a remote match without enough rare-word support. `ambiguousCandidates` means genuinely different script locations remain too close. `insufficientEvidence` means confidence or the applicable commit threshold was not met.

These diagnostic fields are observational only and do not alter thresholds, candidate scores, clustering, continuity preference, reacquisition or scrolling. The diagnostic cluster radius mirrors the standard engine radius so app logs are easy to read; alignment remains authoritative.

Tune conservatively through `ScriptAlignmentEngine.Configuration`, with a regression sequence for the observed transcript. Increase `minimumCandidateScoreMargin`, `distantJumpPenalty` or `backwardTransitionPenalty` to resist false movement; increase `forwardContinuityBonus` or, cautiously, `continuityPreferenceMargin` to favour nearby progression. `localPersistenceScoreFloor` controls how much lexical evidence a held nearby candidate needs before the update is treated as harmless local persistence rather than positional loss. Change `candidateClusterRadius` only with examples showing that nearby endpoints are being mistaken for separate locations. If genuine recovery freezes, reduce only the guard implicated by the trace and confirm repeated/common phrases still remain stable. Keep latency comparisons in Release on the same iPhone because Debug alignment timings are not representative.

## Replay evaluation

`AlignmentReplayMetrics` summarises labelled sequences with mean/max absolute estimated-position error, false jumps and updates spent reacquiring. Deterministic fixtures cover normal progress, omissions, recognition errors, repetition, repeated phrases, false jumps, forward reacquisition, alternate hypotheses, timing-constrained movement, cumulative recognition overlap and local partial persistence. Recorded device transcripts can use the same frame sequence without importing Speech types.

## Complexity and limitations

With recognition window `W ≤ 16`, length tolerance `T = 4`, beam width `K = 7`, local span `B ≤ 81` and remaining tokens `N`, work is approximately `O(B × T × W²)` locally and `O(N × T × W²)` during reacquisition. Backward scoring-context overlap does not expand the endpoint search span; clustering and the continuity tie-breaker operate only over the retained beam. The score is lexical and heuristic rather than a calibrated probability. Phonetic matching is an interface seam only. Tuning changes must update deterministic fixtures and this document.
