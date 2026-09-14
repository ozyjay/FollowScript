# Alignment engine

## Representation and normalisation

`ScriptTokenizer` uses Unicode letter/number word boundaries and retains original token text, display text through the next token, a UTF-16 `NSRange`, index and paragraph number. The original `ScriptDocument.text` is never rewritten. Matching folds case and diacritics, canonicalises curly apostrophes, removes apostrophes/punctuation and ignores the fillers `ah`, `erm`, `hmm`, `like`, `uh` and `um` in recognition input.

The recogniser window is the last 16 non-filler tokens. This bounds work and weights current speech rather than stale transcript text.

## Matching

Each possible candidate ending is evaluated across lengths within four tokens of the recognition window. Similarity is:

```text
0.50 × normalised edit similarity
+ 0.30 × LCS / longer sequence
+ 0.20 × LCS / recognised sequence
```

This tolerates omitted, inserted and mistaken words while rewarding order and recognised-word coverage. Local candidates receive up to `0.10` continuity bonus, decaying with forward distance from the previous token.

Confidence scales the candidate score by evidence: `score × (0.62 + 0.38 × min(unique recognised tokens / 5, 1))`. Final results add `0.03`. Short fragments can therefore track, but provide less authority than a distinctive phrase.

## Tracking, uncertainty and reacquisition

Once a current token exists, candidate ranges must begin at that token or later. Tracked updates search from the current token through 80 tokens ahead, so alignment is monotonic and recognised wording from an earlier passage cannot move the prompt backwards. A local result below `0.48` is rejected. Confidence at or above `0.62` reports `tracking`; weaker accepted evidence reports `uncertain`.

The user can explicitly replace that anchor by tapping a prompt row and confirming Continue from here. The view model resets the alignment state to the first token in the selected row and restarts recognition to clear its cumulative transcript. Automatic matching is then monotonic from the new anchor; this is the only supported backward transition.

Two consecutive rejected updates move state to `reacquiring`. The following update searches from the current token to the end of the script; only initial acquisition searches the whole script. Global evidence must reach `0.66`; a distant jump also requires at least three recognised tokens. This prevents a single dubious update moving to another repeated phrase. Global candidates beyond the local look-ahead receive a small `0.03` penalty where a previous position exists.

If evidence is insufficient, position remains unchanged and the low-confidence counter advances. Empty input never moves position.

## Worked examples

For “The research demonstrates that cybersickness remains a significant challenge …” and “research demonstrates cybersickness remains a significant challenge”, edit/LCS agreement remains high despite omitted “the” and “that”, placing the endpoint at “challenge”.

If the script reads “We first examined attention. We then examined participant comfort. Finally, we considered confidence” and speech jumps to “finally we considered confidence”, two unrelated/weak updates first enter reacquisition. The distinctive four-token phrase can then pass the global threshold and move to the final sentence.

When “we begin together” occurs twice and the first occurrence is already behind the current token, only the later occurrence is eligible. A distant forward occurrence may require tracking loss and stronger global evidence.

## Complexity and limitations

With recognition window `W ≤ 16`, candidate length tolerance `T = 4`, local search span `B ≤ 81`, and remaining script length `N`, dynamic-programming comparison is approximately `O(B × T × W²)` while tracking and `O(N × T × W²)` during reacquisition. Storage per comparison is `O(W)`.

The current engine is lexical: homophones, heavy paraphrase and languages requiring specialised word segmentation are weak cases. Confidence is algorithmic, not a calibrated probability. Tuning changes must follow `.skills/alignment-engine/SKILL.md`, update this document and pass deterministic fixtures.
