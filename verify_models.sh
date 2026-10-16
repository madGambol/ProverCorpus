#!/bin/bash
#
# verify_models.sh -- independently re-verify a model Mace4 reported.
#
# The sweep's MODEL verdict is Mace4's own exit code: it says "I found a
# model", and believing it is believing the thing under test.  This re-derives
# the model and checks it with two other programs: interpformat renders it,
# and clausetester evaluates every clause of the problem in it.  A model that
# does not satisfy every clause is a soundness violation of the worst kind,
# because it would be reported as a successful answer.
#
# Two details that are easy to get wrong, and silently:
#
#   * The clauses checked are the ones Mace4 actually SEARCHED, taken from
#     its "CLAUSES FOR SEARCH" block, not the problem file.  For an FOF
#     problem the file holds quantified formulas and clausetester wants
#     clauses, so checking the file would either fail or check the wrong
#     thing.
#
#   * Mace4 prints those clauses with Prolog-style variables (A, B, C).
#     LADR's default syntax makes A a CONSTANT, so feeding them back without
#     set(prolog_style_variables) gives "eval_term_ground, symbol not in
#     interpretation" -- which looks like a broken model rather than a
#     mis-parse.
#
# Usage: verify_models.sh <problem-path-relative-to-TPTP>
# Prints one line: OK / UNSATISFIED / NOMODEL / TRANSLATE-FAIL, and the path.
#
# Environment: BIN_DIR, SECS (CPU seconds, default 300), MEGS (default 2000).

set -u
B=${BIN_DIR:-/home/chris/Projects/Prover9Mace4/bin}
SECS=${SECS:-300}
MEGS=${MEGS:-2000}
p=${1:?need a problem path}

t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' 0 1 2 3 15

if ! "$B/tptp_to_ladr" < "$p" > "$t/in" 2>/dev/null; then
  echo "TRANSLATE-FAIL $p"; exit 0
fi

printf 'assign(max_seconds,%s).\nassign(max_megs,%s).\n' "$SECS" "$MEGS" \
  | cat - "$t/in" > "$t/full"
( ulimit -t $((SECS + 60)); "$B/mace4" -f "$t/full" > "$t/out" 2>&1 )

if ! grep -aq 'Exiting with [1-9][0-9]* model' "$t/out"; then
  echo "NOMODEL $p"; exit 0
fi

# The clauses Mace4 searched, with the variable style it printed them in.
{
  echo 'set(prolog_style_variables).'
  awk '/CLAUSES FOR SEARCH/,/end of clauses for search/' "$t/out" \
    | grep -avE '^=|^$|CLAUSES FOR SEARCH'
} > "$t/clauses"

"$B/interpformat" standard < "$t/out" > "$t/interp" 2>/dev/null
nmodels=$(grep -ac '^interpretation' "$t/interp")
if [ "$nmodels" -eq 0 ]; then
  echo "NOMODEL $p (mace4 claimed one but interpformat rendered none)"; exit 0
fi

out=$("$B/clausetester" "$t/interp" commands < "$t/clauses" 2>&1)
# "% interp N models A of B clauses." -- A must equal B for every interp.
bad=$(printf '%s\n' "$out" \
      | sed -nE 's/^% interp [0-9]+ models ([0-9]+) of ([0-9]+) clauses.*/\1 \2/p' \
      | awk '$1 != $2' | wc -l)
verdicts=$(printf '%s\n' "$out" | grep -c '^% interp')

if [ "$verdicts" -eq 0 ]; then
  echo "UNSATISFIED $p (clausetester gave no verdict: $(printf '%s' "$out" | grep -i fatal | head -n1))"
elif [ "$bad" -ne 0 ]; then
  echo "UNSATISFIED $p ($bad of $verdicts interpretations fail a clause)"
else
  echo "OK $p ($verdicts interpretation(s), all clauses satisfied)"
fi
