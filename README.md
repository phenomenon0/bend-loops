# bend-loops — the proof-preserving research loop

We are in the Bend business. This is the machine that turns verified artifacts into
throughput. Adopted from Giulio's bend-sha256 loop (OBJECTIVE.md + ORCHESTRATOR.MD),
generalized to any of our targets.

## The three rails

1. **Objective contracts** (`objectives/*.toml`) — machine-readable: target dir, the
   validation gate, the benchmark command, the metric, direction, patience, deltas,
   forbidden paths. A contract is the *frozen rulebook* of one research campaign.
2. **The runner** (`bendloop.py`) — propose → validate → bench → judge → accept/reject,
   repeat until patience. The proposer is untrusted; the judge is independent,
   read-only, and policy-bound; nothing unvalidated ever commits.
3. **The evidence store** (`bendq.py`) — one queryable index of claims and their status
   (checked / conjecture / tested), so "what is proven" is a command, not archaeology.

## Doctrine (see RESEARCH-LOOP.md for the long form)

- **Proof first, then speed.** No optimization campaign on a target until its
  validation contract (vectors + proof gate where feasible) exists.
- **The proposer is untrusted evidence** (Giulio's rule). The judge inspects the
  diff, demands the mechanism, and rejects unproved fast paths.
- **Same gates, every iteration.** Validation and benchmark never change mid-campaign.
- **Stop rules, not vibes.** `patience` consecutive non-improvements ends the campaign.

## Run

    python3 bendloop.py selftest                 # prove the machinery end to end
    python3 bendloop.py run objectives/kernels-sha256.toml [--dry-run]
    bash smoke/smoke.sh                          # a real 2-iteration campaign in /tmp, v1.1 keys
    python3 bendq.py index <repo> && python3 bendq.py query "sha256 law"
    python3 bendq.py add --source <path> --status checked|conjecture|tested --claim "..."
    python3 bendq.py list                        # recorded claims, newest first

## Contract keys added in v1.1 (all optional — v1 contracts run unchanged)

- `editable_paths = ["src/", "f.py"]` — allowlist. Every changed file must sit under one
  of these prefixes, or the candidate is reset and journaled `forbidden`.
  `forbidden_paths` still applies inside the allowlist.
- `guard_slices = [{name, regex, direction, min_relative_delta}]` — secondary metrics the
  bench must also print. Each is checked against the value recorded at the current best;
  a breach rejects the candidate with reason `slice-guard: <name>` even if the headline
  metric improved. `direction` defaults to the contract's; `min_relative_delta` to 0.0
  (no regression); negative values allow some regression. Slice values go in the journal.
- `env = { KEY = "value" }` — merged over the operator's environment (the contract wins)
  for every loop command: validate, bench, proposer, judge. `${VAR}` expands against the
  operator's env. **Use it to pin interpreters** (e.g. `PATH = "/usr/bin:${PATH}"`,
  `BUN = "/path/to/bun"`): the gates must not depend on which shell launched the loop.
- `judge_policy_addendum = "..."` — appended to the built-in judge policy.
- `agent_timeout` / `judge_timeout` (seconds, as in v1) — a timeout in the proposer,
  validate, bench or judge now journals `<role>-timeout`, kills the command's whole
  process group, resets the tree and counts as a stale iteration; the loop continues.
  Any other exception resets the tree, journals `crash` with the traceback, exits 1.

## What the loop hands out (v1.1)

- **Judge env:** `LOOP_DIFF_FILE` (`journals/evidence-<name>-<iter>.diff` — status, tracked
  diff vs HEAD, untracked files in full), `LOOP_VALIDATION_LOG`
  (`journals/evidence-<name>-<iter>.vallog`), `LOOP_CANDIDATE`, `LOOP_BASELINE`,
  `LOOP_ITERATION`, `LOOP_JUDGE_POLICY` (policy + addendum). The judge reads these first.
- **`LOOP_STATE`** (proposer and judge) gains `objective_name` and `recent` — the last ≤8
  journal entries (verdict, cand/best, first line of the reason) so the proposer stops
  retrying what already failed.
- **Proposer transcripts:** stdout+stderr of every proposer run, including a timed-out
  one, in `journals/proposer-<name>-<iter>.txt`; journal entries point at it (`proposer_out`).

## Changelog

- **v1.1** — fix what campaign #1 bent (NOTES-campaign-1.md): judge evidence files + env,
  `editable_paths`, timeouts journal instead of crashing (process-group kill), contract
  `env`, proposer transcripts, `LOOP_STATE.recent`, `guard_slices`,
  `judge_policy_addendum`, `bendq add/list`. Also: renames can't slip past
  forbidden/allowlist checks, resets clear staged changes, the journal keeps the head of
  the judge's reply. Journal schema additive only. `selftest` 15/15 + `smoke/smoke.sh`.
- **v1** — propose/validate/bench/judge/accept loop, selftest, bendq index/query.
