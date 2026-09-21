# MACHINERY-NOTES — bend-loops on its first real campaign (refactor-oracle)

Rough edges in `bend-loops/bendloop.py` observed while running campaign #1. bendloop.py
was run AS-IS: nothing in it was changed. Workarounds live in the campaign repo's
own files. Severity: **H** = silently wrong result or wasted campaign, **M** = extra
work or cost, **L** = cosmetic.

These notes are kept outside the campaign repo while the loop runs, because the loop owns
that working tree (see #6).

## Before launch (setup + smoke tests)

1. **[H] The loop's commands inherit the operator's PATH and interpreter.** On this
   machine, bare `python3` resolves to a venv without scikit-learn, so the natural contract
   (`python3 eval/evaluate.py`) fails at baseline. Workaround: `/usr/bin/python3` is pinned
   in every contract command and in the proposer prompt. Fix: let the contract declare the
   interpreter/env, or document that commands run in the caller's env.
2. **[H] `judge_cmd` gets no evidence.** bendloop computes `diff = git diff` right before the
   judge and then never uses it. The judge gets only `LOOP_OBJECTIVE` and `LOOP_STATE`: no
   diff, no validation log, no candidate metric. `git diff` would also miss untracked
   files: a new `model/foo.py` would be invisible. Workaround: judge.py re-runs validate
   and evaluate itself and builds its own diff (tracked + untracked). That doubles the gate
   cost per judged candidate (about 10 s here). Fix: pass `LOOP_DIFF_FILE`,
   `LOOP_VALIDATION_LOG` and `LOOP_CANDIDATE` in env.
3. **[M] The proposer's stdout is discarded.** Only `rc` reaches the journal (and only on
   error). Its reasoning and measured claims are lost. Workaround: `tee runs/proposer-<ts>.txt`.
4. **[M] `LOOP_STATE` has no history.** It carries only `{best_metric, direction, iteration}`,
   not the prior attempts or the judge's reject reasons, so a one-shot proposer can repeat a
   rejected idea. Workaround: the proposer prompt points at the journal. Fix: include the last N
   journal entries in `LOOP_STATE`.
5. **[H] `forbidden_paths` is a denylist only.** A proposal that adds a new root file
   (`hack.py`, `conftest.py`, `sitecustomize.py`) passes the harness check. Workaround:
   validate.py enforces a `model/`-only allowlist from inside the gate, and the contract
   also forbids `judge.py`, `prompts` and `objectives`. Fix: an `editable_paths` allowlist.
6. **[M] The target repo is the loop's exclusive workspace.** Any operator edit mid-run is
   `git checkout -- . && git clean -fd`'d on the next reject, or swept into the next
   accept's `git add -A`. Notes, reports and tools must live elsewhere during the run.
7. **[L] `repeats` is wasted on a deterministic metric.** repeats=3 runs evaluate.py three
   times per candidate (~3 s each here) for an identical number. That is harmless, but the
   contract can't say "deterministic, run once" without lying about `repeats`.
8. **[H] Timeouts crash the loop.** `sh()` doesn't catch `subprocess.TimeoutExpired`. A
   proposer that exceeds `agent_timeout` (or a hung judge or bench) raises out of
   `run_contract`. The loop dies mid-iteration with a dirty tree and no journal entry for that
   iteration. Workaround: generous timeouts (agent 2700 s, judge 1800 s).
9. **[L] Two judge policies.** bendloop's `JUDGE_POLICY` is speed-oriented ("concrete
   performance mechanism", "speed gates"). Non-speed objectives need an addendum.
   judge.py imports `JUDGE_POLICY` and appends a campaign addendum that reframes "mechanism"
   as generalization. In the smoke test GLM applied both coherently.
10. **[M] bendq has no add-claim or status command.** It only indexes markdown under
    `docs/omen/**`, `demos/kernels/*.md` and `power/**`. Workaround: claims are written as
    `docs/omen/refactor-oracle-claims.md` in the campaign repo, then `bendq.py index`.
11. **[H] Proposer isolation is honor-system.** The proposer is an agent with a full shell
    in the campaign dir. It *could* read `data/holdout.jsonl` and tune to it: the eval
    sandbox protects the model at run time, not the proposer at write time. Defenses in
    place: the prompt forbids it, the judge is told to distrust holdout-shaped constants, and
    the shuffled-label control catches arms that don't learn from train. None of these
    catches a proposer who *read* the holdout and chose train-learned features to fit it.
    Fix: run the proposer in a sandbox/worktree without the holdout file.
12. **[M] The judge runs only on "improved" candidates.** Non-improving candidates are
    rejected without review. That is cheap, but nobody inspects a proposal that games the
    validator without moving the metric, and a "no-change" proposer is never looked at.
13. **[H] A proposer commit bypasses every gate.** bendloop detects changes with
    `git status --porcelain`. If the proposer runs `git commit`, the tree is clean, the
    iteration counts as "no-change", and the unvalidated commit stays on HEAD. Nothing checks
    that HEAD didn't move. Workaround: the proposer prompt forbids committing. Fix: record
    HEAD before `proposer_cmd` and reset or reject if it moved.
14. **[H] The proposer CLI trap (in the campaign's own proposer script, not bendloop).**
    `claude -p --allowedTools 'A,B' "<prompt>"` fails: `--allowedTools` is variadic and
    eats the positional prompt. The smoke test caught it. Unfixed, every iteration would
    have been `proposer-error`, and patience=4 would have ended the campaign in 4 no-op
    iterations with no hint beyond `rc=1`. Workaround: prompt on stdin. bendloop angle
    (**M**): proposer-error journals only `rc`, not stderr, so this failure mode is opaque
    from the journal.
15. **[L] `--dry-run` tests little.** With no proposer, every dry iteration is "no-change".
    It proves the baseline validate+bench gates run (13.6 s here) and that patience counts
    no-change, but it never exercises validate/bench/judge on a candidate. The baseline
    metric is printed but not journaled.
16. **[L] The selftest was the only prior run.** Before this campaign the journal dir held
    only `selftest.jsonl`, so this is the first contact with a real proposer and judge.
17. **[M] The shuffled-label gate I first shipped was too loose.** One shuffle at a
    `|auc-0.5| <= 0.10` tolerance let a mildly leaky arm through. It was tightened before
    launch to the mean of 3 shuffles at 0.06 (commit 1f4442f). Not a bendloop issue: a note
    on how much of a campaign's integrity lives in the validator the operator writes.

Smoke-test receipts: GLM judge on an empty diff returned a correct fail-closed REJECT
("the diff is empty ... mechanism unexplained"). Latency was 46.5 s total, 36.9 s of it
in GLM. `runs/judge-1789971225.json`. Dry run: `journals/refactor-oracle-dryrun.jsonl`.

## During the run

(observations appended below as the loop runs)

Loop launched 2026-09-21 01:16:06 local (06:16:06Z) (bendloop.py AS-IS, contract
`bend-loops/objectives/refactor-oracle.toml`). Baseline re-measured by the loop: 0.6567.

- **iter 1: ACCEPT, 0.6567 -> 0.6667 (+1.5%).** The NB char-n-gram arm was swapped for LR over
  the signed log of the tree's 7 structural features. The iteration took 3.0 min end to end (proposer start to commit). The judge
  took 19.2 s end to end (GLM 11.0 s), and its reasoning was on point. It noted the removed
  arm was keyed to Rust surface syntax. Rough edges exposed:
  - **[H] The loop cannot tell +1.5% from noise.** AUC SE at n=485 is ~0.025, so +0.010 is
    ~0.4 SE (unpaired; the paired commit-bootstrap CI is in LOOP-REPORT). `min_relative_delta` is the only significance gate and 1% sits far under the
    noise floor. JUDGE_POLICY asks for a "significant measured improvement", but nothing
    computes significance and GLM took the delta at face value. Fix: a paired bootstrap
    (or DeLong) CI in the bench, and a contract field for it.
  - **[H] The bench is the holdout, and the proposer holds the bench.** The proposer
    reported it tried 3 configurations against `eval/evaluate.py` (holdout AUC) and kept the
    best, and flagged the +1.5% as "mildly optimistic". That is adaptive overfitting
    *within* an iteration, invisible to bendloop, and it compounds across iterations.
    The loop has no notion of a proposer-visible dev split vs a sealed test split.
  - [L] The static scan in validate.py caught the word "holdout" in a docstring and failed the
    proposer's first validation. Crude but safe. The proposer self-corrected in the same
    iteration.
  - [M] The accept commit's author is `loop <loop@local>` and its message is only the metric
    delta. The mechanism, the judge verdict and the proposer narrative are not in git; they
    are only in the journal plus the campaign's own `runs/` receipts.
  - [L] The journal's `reason` is `jout[-1500:]`, the tail of the judge output. Long judge
    replies lose their first line (the verdict) and the start of the reasoning in the journal.
- **iter 2: no-change (stale 1/4), ~4.3 min.** The proposer tried 3 ideas on the holdout, none
  beat 0.6667, and it reverted all three. On its own it built a train-only temporal CV and
  screened more variants there before touching the holdout. It left a useful negative
  result: "adding count features raises in-era CV 0.735->0.765 and lowers holdout twice:
  the gap is era shift, not capacity."
  - **[H] The loop's memory drops exactly this.** The journal records `{"verdict":
    "no-change"}` and nothing else. The proposer wrote "don't repeat this pattern" for the
    next iteration, but the next proposer only sees `LOOP_STATE` + journal, so that lesson
    exists only in the campaign's tee'd `runs/`, which the prompt doesn't point at.
    Confirms #4 in practice: a one-shot proposer loop without carried-over findings will
    re-explore dead ends.
  - [M] Operator can't fix the prompt mid-run: `prompts/` is a forbidden path, so an operator
    edit would show up as the *proposer's* forbidden change on the next iteration and be
    reset, costing that iteration. Mid-run steering has no channel.
  - [L] "no-change" still costs a full proposer run (~4 min, the most expensive step) and
    counts toward patience the same as a validation failure. Reasonable, but the journal
    can't distinguish "tried and honestly found nothing" from "proposer crashed silently
    with rc=0".
- **iter 3: no-change (stale 2/4), ~2.3 min.** Three ideas, all below 0.6667 on the holdout.
  - **[H] Observed: the dead end was repeated.** Idea 1 of iter 3 ("split ident/num/op deltas
    into gone/new counts") is idea 1 of iter 2 ("split ident_delta and op_delta into
    lost/gained counts"), re-implemented and re-measured (holdout 0.6524 vs 0.6483 last
    time). Iter 2's warning never reached iter 3 because the journal said only `no-change`.
    This is #4 turning into wasted budget: a third of this iteration went to a known loser,
    and a holdout measurement was spent on it.
  - [M] The proposer again confirmed the core science: train CV (all .rs) does not predict
    the holdout (TS/C/JS). No in-train signal can validate cross-language transfer, so
    every selection step leans on the holdout, and each "no-change" iteration still burns
    up to 3 holdout looks.
- **iter 4: ACCEPT, 0.6667 -> 0.6752 (+1.3%), ~2.8 min.** It added `bracket_imbalance`
  (|net bracket depth of removed − added lines|, summed over ()/{}/[]). The judge took 71.5 s
  (GLM 65.4 s, vs 11 s on iter 1: GLM latency varies 6x run to run).
  - **[H] The metric rewards gaming the synthetic half.** The gain is all in pos|neg_mut
    (0.6749 -> 0.6914). pos|neg_commit, the real-history question, is flat (0.6586 ->
    0.6590). The feature detects an artifact of the mutation operator (a dropped line that
    carried a bracket), not a behavior change a real commit would make: real feature commits
    always parse. The proposer said so itself ("the gain lands where the mechanism
    predicts, in neg_mut"). The judge accepted, calling it "a parseability invariant",
    and did not weigh that half the metric is synthetic. This is not a bendloop bug. It is
    a contract gap: one scalar metric, no per-slice floor or guard. A contract field like
    `guard_regex` (the "pos|neg_commit must not drop" kind) would let the loop say "improve X
    without regressing Y".
  - [+] Proposer discipline improved without being asked: it screened three more ideas on
    train temporal CV *only* and took just one to the holdout.
- **iter 5: no-change (stale 1/4), ~3.2 min.** Of its three ideas, two went to the holdout
  and lost.
  - [H] **The repeat again.** "Rate features: ident/num/op_delta ÷ total changed tokens" is
    iter 3's idea 2 ("divide the token deltas by total changed tokens"): 0.6518 now vs
    0.6388 then, both losers. That makes 2 repeated dead ends in 4 iterations.
  - [+] The proposer explicitly refused to p-hack: "stopped here rather than keep testing
    variants against the holdout until one happened to clear +1%." The loop's incentive
    (bare +1% threshold, holdout as bench) points the other way. The honesty came from the
    prompt and the model, not the machinery.
- **iter 6: ACCEPT, 0.6752 -> 0.6929 (+2.6%), ~2.2 min.** It added `lone_drop` (a diff block
  deleting exactly one line) and `token_swap` (a 1:1 line replacement differing in one
  operator/literal/bool token).
  - **[H] Mutation-operator detectors.** These two features are close to one-to-one detectors
    for the dataset's own mutation operators (`drop`, `op`/`const`/`bool`). The generator,
    `tools/build_dataset.py`, is readable by the proposer: forbidden to edit, not to read,
    and the prompt describes the operators. The gain is again all synthetic: pos|neg_mut
    0.6914 -> 0.7275, pos|neg_commit 0.6590 -> 0.6586. Since iter 1 the real-history slice
    has not moved (0.6586 -> 0.6590 -> 0.6586). It is not holdout leakage, and the prior is
    defensible: isolated one-token edits rarely are refactors. But it is teaching to the
    generator, and the scalar metric can't tell.
  - **[H] Judge factual error, accepted anyway.** GLM wrote "with gains on both holdout
    contrast pairs (0.6586 / 0.7275)". False: neg_commit went *down* 0.0004. The judge
    can't know, because it gets the candidate's per-slice numbers but only the best's
    scalar. judge.py passes `best_metric` from `LOOP_STATE`, and bendloop never stores the
    best's full bench output. It filled the gap by asserting a gain. Fix (both layers):
    bendloop should keep the accepted run's bench output and hand it to the judge; the judge
    prompt should ask for a slice-by-slice before/after.
  - **[M] Judge depth varies wildly per call.** GLM latency across the 4 calls: 36.9 s, 11.0 s,
    65.4 s, **1.6 s**. The 1.6 s reply is the one with the factual error and garbled prose
    ("the propositional-structure remains an interpretable decision tree"). OpenRouter
    routes `z-ai/glm-5.3` to whichever provider is up, with or without reasoning. My
    judge.py receipts don't record the serving provider or token usage, so I can't prove the
    routing. bendloop has no notion of judge quality: any reply starting "ACCEPT" is an
    ACCEPT. Fix: pin the provider (`provider.order` + `allow_fallbacks:false`) and log
    `usage` and provider per call.
- **iter 7: no-change (stale 1/4), ~1.4 min.** Three single-feature ideas, all below 0.6929.
  - [H] **Third repeat.** `new_idents` + `lost_ident_frac` is iter 2's idea 2
    (`novel_idents`/`vanished_idents` as fractions), split in two. `abs_net` is iter 5's
    "|net| term in the LR", which was CV-neutral there. This time all three went straight
    to the holdout (3 looks), with no train-CV screen first.
  - Running tally of holdout looks (from the proposers' own reports): iter 1: 3, iter 2: 3,
    iter 3: 3, iter 4: 1, iter 5: 2, iter 6: 1, iter 7: 3, for **16 looks, 3 winners**. 3 of
    the 13 losers re-ran an earlier holdout loser (and `abs_net` re-ran an earlier CV loser).
    The accepted chain is the max over 16 correlated tries, so its holdout number is
    optimistically biased.
- **iter 8: no-change (stale 2/4), ~4 min.** Three ideas: scale-free rates (0.6403),
  identifier-abstracted line shapes (0.6733), and standardising the LR inputs (0.6976, +0.68%,
  under the gate). Four more screened on a train-only temporal split and never taken to the
  holdout.
  - [+] **Best proposer discipline so far.** It screened on train first, used 3 holdout
    looks, and gave a clean diagnosis: "ideas 1 and 2 gained 0.4-0.9% on the train-only
    split, then lost on the holdout." It also named the real lever ("a way to use `net`
    without hurting neg_mut") and flagged idea 3 as ride-along material, not a proposal.
  - [H] Idea 1 is the **third run** of the rate idea (iters 3 and 5; a 4th follows in iter 10). The journal records only
    `{"verdict": "no-change"}`, with no content, so the proposer can't see it was tried.
  - [M] The 1% gate threw away the one tidy improvement of the run: standardisation is
    principled, +0.68%, and costs no complexity. Under a fixed relative threshold, small
    real gains are unshippable alone. A proposer then has to bundle them with a second idea,
    which breaks "one focused change".
  - Tally: 19 holdout looks, 3 winners.
- **iter 9: no-change (stale 3/4), ~1.5 min.** Tried a rename-tolerant `token_swap`
  (0.6913), `novel_idents` (0.6941, +0.2%) and `abs_net` (0.6658).
  - [H] **This is the whole content-free-journal failure, clearly visible.** `novel_idents` is
    now on its 3rd run (iters 2, 7, 9) and `abs_net` on its 3rd (iters 5, 7, 9). Each proposer
    ends with a careful "do not repeat" list, and the next proposer never sees it, because
    bendloop discards proposer stdout and the journal holds only `{"verdict":"no-change"}`.
    Iterations 7-9 spent about 60% of their holdout looks re-measuring known losers. Fix: a
    "tried & failed" digest in LOOP_STATE (the last N proposer summaries), or have the
    journal store the proposer's final message.
  - [+] The proposer again refused the obvious gaming move ("making the model lean harder on
    signed net would be tuning to the holdout").
  - Tally: 22 holdout looks, 3 winners.
- **iter 10: no-change (stale 4/4), ~5.6 min, then patience exhausted.** Tried token-delta
  shares (0.6659), `vocab_net` (0.6600; the 4th vocabulary-novelty variant after iters 2, 7
  and 9) and degree-2 LR interactions (0.6894). About ten more were screened on train
  grouped-CV only.
  - [+] It found the root cause of the plateau that nobody else found: "train is 100% `.rs`,
    so train data cannot validate transfer to other languages". A temporal split inside train
    shows no era shift (0.751 vs 0.758 grouped CV). The whole shift is language, and no
    train-only screen can see it. That is why iters 2-10 kept seeing "CV up, holdout down".
  - [+] It also spotted that adding any column reshapes the depth-4 tree (model bytes
    4160 -> 3704/3848), so the tree arm is unstable to feature additions. It suggested a
    fixed tree feature set with new features going to the LR only. That is untested.
  - Tally: **25 holdout looks, 3 winners** over the campaign.

## After the run

- **Stop: patience, not the timebox.** Iters 7-10 were 4 no-changes in a row, so the loop
  stopped at iter 10/12 with `rc=0`, in **30 m 51 s wall** (06:16:06Z -> 06:46:57Z). That is
  far inside the ~3 h budget. Patience worked exactly as specified. But every "stale" iter
  was a proposer self-revert, not a loop reject, so patience here measured "the proposer
  gave up 4 times", with no visible content (see iter 9).
- **[H] The loop's reject paths never fired live.** Across 10 iterations there were 0
  validation-fails, 0 below-threshold benches, 0 judged-REJECTs and 0 forbidden-path hits.
  Every candidate the loop saw was a proposer-pre-screened winner. The proposer runs the
  bench (= the holdout) itself and only leaves a winner in the tree, so the loop's gates
  confirm rather than filter. The accept/reject machinery has still only been exercised by
  `--selftest`, the dry-run and my pre-launch judge smoke test (a REJECT on a
  deliberately-bad candidate). Fix: give the proposer a proposer-side metric (e.g. a
  grouped-CV score on train) and keep the holdout loop-only. Then the loop's gate would
  actually gate.
- **[M] The journal truncates the judge's reply from the front.** `bendloop.py:117` stores
  `jout[-1500:]`: the *last* 1500 chars. For iters 1 and 4 the GLM reply was longer, so the
  stored `reason` starts mid-sentence ("t arm's weights were…", "vector — the sum…") and the
  first line (`ACCEPT`/`REJECT`, the part the verdict is parsed from) is gone. Only iter 6's
  short reply (the 1.6 s one) survived intact. The verdict field is still right, but the
  stored rationale has no head. Fix: `jout[:1500]`, or head+tail.
- **[M] The journal has no per-iteration cost or timing** (no wall time for
  proposer/validate/bench/judge, no token usage). I reconstructed per-iter wall times from
  the `runs/proposer-<ts>.txt` filenames that `propose.sh` writes, which are not bendloop's.
  Judge latencies came from my own judge.py receipts.
- **Tolerance of a non-compile target: fine.** Nothing in bendloop assumed a compiler. A
  metric regex over a Python evaluator plus shell commands for validate/bench/judge was all
  it needed. The rough edges were all around the proposer (CLI flags, stdout discarded,
  commits bypassing gates) and the judge (evidence, policy duplication), not the target
  type.
