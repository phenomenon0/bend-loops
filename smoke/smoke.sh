#!/usr/bin/env bash
# smoke — a real 2-iteration bendloop campaign in /tmp, driven through the CLI, using every v1.1 contract key.
#   iter 1: metric 100 -> 60 + a new untracked fast.py; the stub judge decides from $LOOP_DIFF_FILE -> ACCEPT
#   iter 2: metric 60 -> 40 but guard slice b drops 1.0 -> 0.5                              -> slice-guard reject
# The contract's env puts /usr/bin first on PATH: validation must run /usr/bin/python3, not the operator's python3.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; T=/tmp/bendloop-smoke
rm -rf "$T"; mkdir -p "$T/target"; rm -f "$HERE"/journals/smoke.jsonl "$HERE"/journals/{evidence,proposer}-smoke-*

cd "$T/target"
echo 100 > cost.txt; echo 1.0 > slice.txt
cat > bench.py <<'EOF'
print(f"median_ms={float(open('cost.txt').read())}")
print(f"slice_b={float(open('slice.txt').read())}")
EOF
cat > check.py <<'EOF'
import os, sys
print(f"validate ok via {sys.executable} SMOKE_TAG={os.environ.get('SMOKE_TAG')}")
EOF
git init -q; git add -A; git -c user.name=smoke -c user.email=smoke@local commit -qm base

cat > "$T/proposer.sh" <<'EOF'
st() { python3 -c "import json,os; s=json.loads(os.environ['LOOP_STATE']); print($1)"; }
it=$(st 's["iteration"]')
echo "smoke proposer iter $it objective=$(st 's["objective_name"]') recent=$(st '[e["verdict"] for e in s["recent"]]')"
if [ "$it" = 1 ]; then echo 60 > cost.txt; echo 'def fast(): pass' > fast.py; fi
if [ "$it" = 2 ]; then echo 40 > cost.txt; echo 0.5 > slice.txt; fi
EOF
cat > "$T/judge.sh" <<'EOF'
# stub judge: decides from the harness's evidence, never from the proposer's story
if grep -q '^+def fast' "$LOOP_DIFF_FILE" && grep -q 'validate ok' "$LOOP_VALIDATION_LOG" \
   && printf '%s' "$LOOP_JUDGE_POLICY" | grep -q 'SMOKE ADDENDUM'; then
  echo ACCEPT; echo "diff adds fast.py; validation ran; $LOOP_BASELINE -> $LOOP_CANDIDATE at iter $LOOP_ITERATION"
else echo REJECT; echo "evidence does not show fast.py"; fi
EOF
cat > "$T/smoke.toml" <<EOF
name = "smoke"
dir = "$T/target"
proposer_cmd = "bash $T/proposer.sh"
judge_cmd = "bash $T/judge.sh"
validate_cmd = "python3 check.py"
bench_cmd = "python3 bench.py"
metric_regex = "median_ms=([0-9.]+)"
direction = "min"
repeats = 1
patience = 3
max_iterations = 2
commit_prefix = "loop(smoke):"
forbidden_paths = ["bench.py", "check.py"]
editable_paths = ["cost.txt", "slice.txt", "fast.py"]
guard_slices = [{ name = "b", regex = "slice_b=([0-9.]+)", direction = "max", min_relative_delta = -0.05 }]
env = { PATH = "/usr/bin:\${PATH}", SMOKE_TAG = "pinned-by-contract" }
judge_policy_addendum = "SMOKE ADDENDUM: accept only a diff that adds fast.py."
EOF

python3 "$HERE/bendloop.py" run "$T/smoke.toml"
J="$HERE/journals/smoke.jsonl"
echo; echo "journal: $J"; cat "$J"
echo; echo "evidence + transcripts:"; ls -l "$HERE"/journals/{evidence,proposer}-smoke-*
echo; echo "evidence-smoke-1.diff:"; cat "$HERE/journals/evidence-smoke-1.diff"
echo; echo "evidence-smoke-1.vallog:"; cat "$HERE/journals/evidence-smoke-1.vallog"
echo; echo "proposer-smoke-2.txt:"; cat "$HERE/journals/proposer-smoke-2.txt"
echo; echo "target log:"; git log --oneline

python3 - "$HERE" <<'EOF'
import json, sys; from pathlib import Path
j = Path(sys.argv[1]) / "journals"
e = [json.loads(l) for l in (j / "smoke.jsonl").read_text().splitlines()]
checks = {
  "verdicts: judged-ACCEPT, accepted, rejected": [x["verdict"] for x in e] == ["judged-ACCEPT", "accepted", "rejected"],
  "iter 2 rejected by slice-guard: b, slices journaled": e[2].get("reason") == "slice-guard: b" and e[2]["slices"] == {"b": 0.5} and e[2]["best_slices"] == {"b": 1.0},
  "judge read the evidence diff (untracked fast.py in it)": "+def fast" in (j / "evidence-smoke-1.diff").read_text() and e[0]["reason"].startswith("ACCEPT"),
  "contract env pinned the interpreter": "via /usr/bin/python3 SMOKE_TAG=pinned-by-contract" in (j / "evidence-smoke-1.vallog").read_text(),
  "LOOP_STATE.recent reached iter 2's proposer": "recent=['judged-ACCEPT', 'accepted']" in (j / "proposer-smoke-2.txt").read_text(),
}
for k, ok in checks.items(): print(f"[smoke] {'PASS' if ok else 'FAIL'}  {k}")
sys.exit(0 if all(checks.values()) else 1)
EOF
