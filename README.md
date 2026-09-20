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
    python3 bendq.py index <repo> && python3 bendq.py query "sha256 law"
