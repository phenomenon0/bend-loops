# LOOP-REPORT — refactor-oracle, bend-loops campaign #1

Run 2026-09-21, 06:16:06Z -> 06:46:57Z (30 m 51 s). `bendloop.py` ran as-is on
`objectives/refactor-oracle.toml`. The proposer is `claude -p` (claude-fable-5-1) and the judge
is GLM `z-ai/glm-5.3` via OpenRouter. The loop ran 10 iterations with 3 accepts and stopped on
**patience** (4 consecutive no-changes), not on the timebox.

## Verdict, in plain terms

**No, it can't tell you whether a refactoring preserves behavior.** What it learned is what a
refactor *looks like*. A hunk that reuses the removed lines' tokens, keeps brackets balanced, and
doesn't drop one isolated line or swap one operator scores high. That is a shape detector, not
an oracle:

- **On real history the dumb baseline won.** On the bend2 refactor-vs-feature/fix hunks the
  oracle scores AUC 0.659, against 0.778 for "net lines <= 0". That gap is significant (paired
  -0.120, 95% CI [-0.181, -0.062]). Caveat: that baseline partly leaks the label definition (see
  below), so the real-history slice is a weak test in both directions.
- **It only won on the half we generated ourselves.** Full-holdout AUC is 0.693, against 0.602
  for the best frozen baseline (paired +0.091, CI [+0.012, +0.181]). All of that margin comes
  from the synthetic mutants.
- **The loop's +5.5% relative gain (0.657 -> 0.693) is real but synthetic.** Against the seed,
  pos|neg_mut rose +0.066 [+0.036, +0.096] and pos|neg_commit moved +0.007 [-0.025, +0.036],
  which is nothing. All three accepts taught the model to detect the dataset's own mutation
  operators.
- **As a scout ranker it guesses everywhere.** It marked 0 of 58 upstream dedup zones
  confident. It also gives the same score (0.403) to a behavior-preserving dedup (identical twin)
  and a behavior-changing one (a twin that returns a different field and doesn't free the
  buffer).

Where it could still help: as a cheap, 4 KB, 0.15 ms pre-filter that flags *mechanical-break
shapes* (a lone dropped line, a one-token operator or constant swap, a bracket imbalance). A
mutant scores below its own parent 66.5% of the time. It is not a refactoring validator. The
honest answer to "can it refactor?" is no. The dumb baseline wins on the real question, and the
campaign's own metric hid that behind the synthetic half.

## Setup (frozen before the run)

| piece | what |
|---|---|
| data | `tools/build_dataset.py`, run once, hashes pinned in `eval/FROZEN.json`. One sample = one hunk (before, after). **pos** = hunks of commits with a refactor verb, no test file touched, and code LOC delta <= 0. **neg_commit** = hunks of commits with tests touched and (a feature/fix verb or LOC delta > 0). **neg_mut** = a pos hunk with one mutation (drop, op, const or bool). pos/neg_commit are balanced per file extension. |
| split | temporal at 2026-08-01. **train** = Rust-era bend, 1091 samples (364/364/363), 289 commits, 100% `.rs`. **holdout** = bend2 rewrite, 485 samples (162/162/161), 67 commits: .ts 416, .c 27, .js 24, .bend 18. |
| metric | `eval/evaluate.py` -> `oracle_auc` (holdout ROC AUC, all three kinds), plus per-kind AUCs and the frozen baselines (majority, random, diff size, net LOC). |
| guards | `eval/validate.py`: frozen hashes, split disjointness, scope (model/ only), a static escape scan, determinism, a **shuffled-label control** (mean of 3 shuffles must be within 0.06 of chance), and Jev limits (<= 1 MB, <= 5 ms median). `eval/worker.py` sandboxes the model: an audit hook blocks data/eval/tools/upstream reads, subprocesses and sockets. |
| judge | `judge.py`: re-checks scope, re-runs validate and bench, then asks GLM at temperature 0, **fail-closed**. The first line is ACCEPT or REJECT. The key is read by path and never printed. |
| contract | repeats 3, patience 4, min_relative_delta 0.01, max_iterations 12. forbidden: data, eval, tools, upstream, judge.py, prompts, objectives. |

**The net-LOC confound.** A pos commit needs code LOC delta <= 0 by construction, and a
neg_commit can qualify through delta > 0. Hunk-level net lines are not the same number as
commit-level delta, but they correlate, so part of net_loc's 0.778 on real hunks is the label
definition talking. It also points the wrong way on mutants (0.425), because a dropped
statement makes net lines go down.

## The run

Metric cells show `oracle_auc` (pos|neg_commit / pos|neg_mut). "Looks" is the number of
candidates the proposer measured on the holdout, as it reported them.

| iter | verdict | metric after | time | what | looks |
|---|---|---|---|---|---|
| base | — | 0.6567 (0.6518 / 0.6616) | — | seed: depth-4 tree over 7 structural features + NB over hashed char n-grams, 266 KB | — |
| 1 | **ACCEPT** +1.5% | 0.6667 (0.6586 / 0.6749) | 3.0 min | NB arm -> LR over the signed log of the tree's features (Rust surface syntax doesn't transfer). Model 266 KB -> 4 KB. | 3 |
| 2 | no-change | — | 4.4 min | split deltas into lost/gained counts, and more; found "train CV up, holdout down" | 3 |
| 3 | no-change | — | 2.3 min | repeated iter 2's idea 1, plus rate features | 3 |
| 4 | **ACCEPT** +1.3% | 0.6752 (0.6590 / 0.6914) | 2.8 min | `bracket_imbalance`: net bracket depth of removed vs added lines | 1 |
| 5 | no-change | — | 3.2 min | rate features again (iter 3's idea 2); refused to keep p-hacking | 2 |
| 6 | **ACCEPT** +2.6% | 0.6929 (0.6586 / 0.7275) | 2.2 min | `lone_drop` + `token_swap`: detectors for isolated one-line deletions and one-token swaps | 1 |
| 7 | no-change | — | 1.4 min | novel/lost identifiers (iter 2 again), `abs_net` (iter 5 again) | 3 |
| 8 | no-change | — | 4.1 min | rates (3rd time), line shapes, LR standardisation (+0.68%, under the gate) | 3 |
| 9 | no-change | — | 1.6 min | rename-tolerant swap, `novel_idents` (3rd), `abs_net` (3rd) | 3 |
| 10 | no-change -> **patience exhausted** | — | 5.7 min | token-delta shares, `vocab_net`, LR interactions; found that train is 100% `.rs`, so no train screen can validate language transfer | 3 |

- **Accepts:** 3, all judged ACCEPT by GLM (latencies 11.0 s, 65.4 s and 1.6 s).
- **Rejects:** 0 live. There were no validation-fails, no below-threshold benches, no judge
  REJECTs and no forbidden-path hits. The proposer measures the holdout itself and self-reverts
  losers, so the loop only ever saw pre-screened winners. The reject paths have only been
  exercised by `--selftest`, the dry run and the judge smoke test (a REJECT on an empty diff).
- **Patience:** iterations 7-10 were four no-changes in a row, so the loop stopped at 10/12
  with rc=0. Each "stale" iteration was a proposer that tried 2-3 ideas, found nothing that
  cleared +1%, and left the tree clean.
- **Holdout looks:** 25 in total, 3 winners. 9 of the losers re-ran an earlier loser,
  because the journal stores no content (see MACHINERY-NOTES). The accepted chain is the best
  of 25 correlated tries, so its point estimate is optimistically biased. The paired CI against
  the seed still excludes zero on the synthetic slice.

## The oracle vs the frozen baselines

`/usr/bin/python3 eval/evaluate.py` at HEAD:

```
arm                     auc  pos|neg_commit  pos|neg_mut  acc@0.5
majority             0.5000          0.5000       0.5000      nan
random(seed=0)       0.4920          0.4725       0.5115      nan
diff_size(-lines)    0.5463          0.5872       0.5052      nan
net_loc(-delta)      0.6023          0.7782       0.4253      nan
oracle               0.6929          0.6586       0.7275   0.6619
model_bytes=4160 (max 1048576) infer_ms_median=0.148 (max 5.0) train_s=0.06
oracle_auc=0.6929
```

Paired 95% CIs come from `tools/retrodict.py 6caa98b 086f4d1 1cf551f`, which uses 1000
resamples of holdout commits; each mutant travels with its parent's commit:

| slice | oracle | − net_loc | − seed (6caa98b) | − iter 1 | − iter 4 |
|---|---|---|---|---|---|
| full holdout | 0.6929 [0.640, 0.746] | **+0.091** [+0.012, +0.181] | **+0.036** [+0.010, +0.060] | +0.026 [+0.012, +0.040] | +0.018 [+0.006, +0.028] |
| pos vs neg_commit (real) | 0.6586 [0.588, 0.739] | **−0.120** [−0.181, −0.062] | +0.007 [−0.025, +0.036] | +0.000 [−0.021, +0.015] | −0.001 [−0.017, +0.011] |
| pos vs neg_mut (synthetic) | 0.7275 [0.675, 0.784] | +0.302 [+0.231, +0.393] | **+0.066** [+0.036, +0.096] | +0.053 [+0.036, +0.073] | +0.036 [+0.024, +0.051] |

Every accepted step moved only the synthetic row. The real row stayed flat from the seed to the
end.

## Retrodiction: bend2 refactor commits vs their sibling feature/fix commits

The model was trained on Rust-era history only. The threshold *t* = 0.268 was chosen on train
alone: commit-grouped 5-fold OOF, maximising balanced accuracy (OOF bal. acc 0.708, OOF AUC
0.750).

**Hunk level** (324 hunks, 162 refactor):

| rule | precision | recall | TP | FP | FN | TN |
|---|---|---|---|---|---|---|
| oracle @0.5 | 0.556 | 0.123 | 20 | 16 | 142 | 146 |
| oracle @train t=0.268 | 0.602 | 0.673 | 109 | 72 | 53 | 90 |
| net-LOC rule (net <= 0) | **0.687** | **0.852** | 138 | 63 | 24 | 99 |

**Commit level** (67 commits, 27 refactor; a commit's score is the mean of its hunk scores).
AUC: oracle 0.803, net-LOC 0.877.

| rule | precision | recall | TP | FP | FN | TN |
|---|---|---|---|---|---|---|
| oracle @0.5 | 1.000 | 0.074 | 2 | 0 | 25 | 40 |
| oracle @train t=0.268 | 0.590 | 0.852 | 23 | 16 | 4 | 24 |
| net-LOC rule (sum net <= 0) | **0.793** | **0.852** | 23 | 6 | 4 | 34 |

**Synthetic breaks** (161 mutants of holdout refactor hunks):

- 96.3% are caught at 0.5, but that is uninformative: the oracle also puts 88% of the *real*
  refactor hunks below 0.5, because its scores are compressed low (poor calibration across the
  era shift).
- At the train threshold, 61.5% are caught.
- A mutant scores strictly below its own parent 66.5% of the time (29 ties).
- By mutation kind, the mutant scored below its parent for drop 56/69, op 25/37, const 25/44
  and **bool 1/11**. The `token_swap` detector barely fires on bend2's bool flips.

**Most confident misses:**

- Feature/fix commits scored most refactor-like: `8d2b1ad5f3` 0.470 (re-lands PR #17 by
  restoring an earlier file text),
  `aba66ac06c` 0.431, `22870c54b3` 0.413.
- Refactor commits scored least refactor-like: `4dd1204320` 0.213 (a constant-table folding
  change), `368270a6b2` 0.231 (10 hunks of allocator restructuring), `2f22377a86` 0.251.

## Scout sample (`scout_sample.md`)

`tools/scout.py` scanned 332 top-level functions (4-30 lines) in the pinned upstream tree
(bend2/*.ts, bend2/effs/*.c|js, gates/*.ts, never bend2/bend.ts). It found 58 near-duplicate
pairs (token ratio >= 0.75, same arity). Each pair was rewritten as the obvious dedup: the later
twin's body becomes a call to the earlier twin. Each edit was scored on the full-train oracle
plus 10 commit-bootstrap retrains, and compared with a mutant of itself.

- **0/58 confident, 58/58 guessing.** Bootstrap agreement on the side of *t* ranged from 3/10 to
  8/10 and never reached 9. 25/58 sit above *t*; the top score is P = 0.418.
- **The ranking doesn't track payoff.** The correlation between P and lines saved is −0.02.
- **It cannot see semantics.** `tcp_recv_pack -> file_read_pack` (identical bodies, ratio 1.00)
  and `tcp_recv_pack -> file_size_pack` (ratio 0.82) both score 0.403. `file_size_pack` returns
  `io_done(e, w->word)` and never frees `w->data`, so the second edit would break `tcp_recv`
  (and leak).
- Every edit outscores its own mutant (+0.005 to +0.160). For these candidates the mutant was
  always `drop`, and dropping the one call line is an easy catch.
- The candidates are unverified sketches. The C `*_pack` helpers are `static` in separate
  files, so whether a cross-file call links depends on how `effs/*.c` are assembled, and
  nothing here compiles them. The zones themselves (the `effs` pack/run/close families: `tcp_recv`
  ≡ `file_read`, `socket_close` ≡ `listener_close` ≡ `file_close`, `udp_bind` ≈ `tcp_listen`)
  are real duplication worth a human look. The oracle adds nothing to finding them: the token
  ratio found them.

## The final model (HEAD `db8da76`, `model/oracle.py`)

It is a depth-4 decision tree plus a logistic regression over the signed log of 10 structural
features, with the score being the mean of the two arms. It is 4160 bytes, runs at 0.15 ms per
hunk, and trains in 0.06 s.

- **Tree (base arm):** the root split is `tok_overlap <= 0.59`, and tok_overlap carries 0.53 of
  the importance. After that come `op_delta` 0.12, `net` 0.12 and `ident_delta` 0.05. Read
  plainly: "the added lines reuse the removed lines' tokens, and few operators changed ->
  refactor". The tree never splits on `token_swap`, and `lone_drop` and `bracket_imbalance`
  each appear once, deep down.
- **LR (pair arm):** the largest weights are `bracket_imbalance` −2.51, `token_swap` −2.16,
  `tok_overlap` +1.38, `lone_drop` −1.03 and `num_delta` −0.78. The three mutation detectors
  the loop added live almost entirely in the LR.

## What bent, what held

**Held**

- **The freeze and the gates.** No forbidden-path change was attempted. Every accepted state
  passes `validate.py` (re-run at HEAD). The shuffled-label control, determinism and the Jev
  limits all held.
- **Loop mechanics.** One journal line per iteration. Commits land at exactly the accepted
  states. Patience fired as specified and the exit was clean. A non-compile target (a Python
  evaluator plus a metric regex) needed nothing special.
- **The Jev shape improved.** The model went from 266 KB to 4 KB with no loss.
- **Proposer honesty.** Every proposer reported measured numbers, per-kind AUCs and failed
  ideas. Two of them explicitly refused to keep testing variants against the holdout. That came
  from the prompt and the model, not from the machinery.

**Bent**

- **The proposer held the bench.** The bench *is* the holdout, and the proposer runs it: 25
  looks. The loop's gates confirmed winners and never filtered anything.
- **A scalar metric over a mixed contrast.** One number averaged a real contrast and a synthetic
  one, and the loop optimised the synthetic one (3 of 3 accepts). A per-slice guard in the
  contract would have caught it.
- **No significance.** The only gate was +1%, while the paired SE is ~0.01. It passed marginal
  steps and blocked a principled +0.68% step.
- **A content-free journal meant repeats.** `novel_idents` variants and rate features ran 4
  times each, `abs_net` 3 times. Every proposer wrote a "don't repeat" list, and none reached
  the next proposer.
- **The judge.** It got no before/after slice evidence and asserted a gain that didn't exist
  (iter 6). Its latency ranged 1.6-65 s depending on OpenRouter routing, unpinned and unlogged.
  The journal stores the *tail* of the judge's reply, so the verdict line is cut off.
- **Campaign-side fixes before launch.** The proposer needed its prompt on stdin, because
  `--allowedTools` is variadic and swallowed the positional prompt. It also needed a no-commit
  rule, because a proposer commit bypasses every gate. The shuffled-label gate had to be
  tightened.

All of these, with fixes, are in `MACHINERY-NOTES.md`. Nothing in `bendloop.py` was changed.

## Reproduce

```
/usr/bin/python3 eval/validate.py                          # guards, all PASS at HEAD
/usr/bin/python3 eval/evaluate.py                          # the metric line + baselines
/usr/bin/python3 tools/retrodict.py 6caa98b 086f4d1 1cf551f  # CIs, P/R, misses (~10 s)
/usr/bin/python3 tools/scout.py > scout_sample.md          # scout table (~15 s)
```

Receipts, all in `receipts/`: the loop's stdout (`loop-stdout.log`), a copy of the bendloop
journal (the original is gitignored in bend-loops), every judge verdict (`judge-*.json`, where
`judge-1789971225` is the pre-launch smoke test) and every proposer report
(`proposer-<start ts>.txt`, iters 1-10 in order), plus the retrodiction output and the final
model dump.
