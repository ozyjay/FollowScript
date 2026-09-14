# Alignment engine

## Online tracking model

`ScriptAlignmentEngine` is a deterministic, framework-neutral online sequence tracker. Each recognition update scores candidate script ranges, keeps the best candidate for each endpoint, and retains a beam of up to seven endpoints in `AlignmentState`. The next update combines lexical evidence with a transition score instead of treating each transcript independently.

Tokenisation treats punctuation as a word boundary and excludes it from matching. This applies to ASCII and Unicode punctuation, including hyphens, dashes, colons, slashes, brackets and sentence marks. Apostrophes may remain inside a source token so contractions retain one source range, but are removed from its normalised matching form. Original punctuation remains in the display text and source mapping.

`estimatedTokenIndex` is the responsive estimate used for highlighting. `committedTokenIndex` is the stable monotonic anchor used for scrolling. An estimate requires confidence of `0.46`. A local commit requires `0.64`; global reacquisition requires `0.66`, while a distant jump requires `0.74`, at least three recognised tokens and distinctive evidence. Partial estimates retain the existing one-token lag; final results use the matched endpoint.

## Evidence score

The recognition window remains the last 16 non-filler tokens. Candidate lengths are within four tokens of that window. Lexical evidence combines:

```text
0.38 × normalised edit similarity
+ 0.25 × LCS / longer sequence
+ 0.17 × LCS / recognised sequence
+ 0.20 × distinctiveness-weighted coverage
```

Distinctiveness uses a within-script IDF-like weight: `1 + 0.28 × log((token count + 1) / (word frequency + 1))`. Rare words therefore resolve repeated/common wording more strongly without making common words useless. When multiple ASR hypotheses are supplied, the strongest confidence-weighted lexical observation contributes. `AlignmentObservation` also reserves optional phonetic tokens for a future lightweight implementation; they are not scored yet.

## Transitions and timing

Candidate evidence contributes 84% and the transition model 16% when an anchor exists. Staying is cheap, small forward moves are preferred, and progressively larger omissions/skips incur `0.012` per token. Distant global jumps add `0.12`. When audio time is available, movement beyond the estimated speaking distance plus four tokens receives an additional penalty. The engine starts at 2.6 tokens/second and smooths observed committed progress, clamped to 1–5.5 tokens/second.

Repetition is represented by keeping the current/nearby beam hypotheses and a low cost for staying. Automatic candidate ranges remain forward-only from the committed anchor, preserving the safety rule that stale recognition cannot pull the prompt backwards. A user-selected anchor remains the explicit way to move backwards.

## Reacquisition and safety

Tracking searches only the next 80 tokens. Two poor updates enter reacquisition and expand the search from the committed position to the end of the script. Tentative and committed distant movement share the distinctive-evidence guard, so a weak repeated phrase cannot flash the highlight elsewhere or move the viewport. A local update cannot advance beyond its recognised-token count plus four tokens; a genuine larger omission must first trigger reacquisition.

## Replay evaluation

`AlignmentReplayMetrics` summarises labelled sequences with mean/max absolute estimated-position error, false jumps and updates spent reacquiring. Deterministic fixtures cover normal progress, omissions, recognition errors, repetition, repeated phrases, false jumps, forward reacquisition, alternate hypotheses and timing-constrained movement. Recorded device transcripts can use the same frame sequence without importing Speech types.

## Complexity and limitations

With recognition window `W ≤ 16`, length tolerance `T = 4`, beam width `K = 7`, local span `B ≤ 81` and remaining tokens `N`, work is approximately `O(B × T × W²)` locally and `O(N × T × W²)` during reacquisition. The score is lexical and heuristic rather than a calibrated probability. Phonetic matching is an interface seam only. Tuning changes must update deterministic fixtures and this document.
