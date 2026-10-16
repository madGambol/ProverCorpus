#!/bin/bash
#
# cap_gate.sh BIN_BASELINE BIN_CANDIDATE [SECS] [JOBS]
#
# The fast capability gate: the problems that have ever changed hands between
# the pristine 2009 release and this tree, run against two builds, interleaved.
# Fails if the candidate loses a problem the baseline answers.
#
# WHY THIS EXISTS.  Every other gate in this tree asks whether a build still
# does what the previous build did on inputs the tree already has.  R1 (see
# ../Prover9Mace4/FIXES.md) passed all of them -- tier1, tier2, the 174-run
# corpus A/B, the determinism harness, ASan+UBSan on 336 pairs, poison on 336,
# valgrind on 168 -- while costing thirteen TPTP problems, because a capability
# loss on problems none of those sets contain is invisible to all of them.  The
# full 8,996-problem A/B found it in about an hour; this list finds it in a few
# minutes, which is the difference between a gate that gets run per feature and
# one that gets run per release.
#
# The list is not a sample.  It is every (problem) that changed hands in the
# first capability A/B plus R1's thirteen, so it is enriched for exactly the
# problems whose outcome is sensitive to a change in the prover -- the ones near
# a limit, the ones whose search order matters, the ones that used to crash.
# Re-run baseline_ab.sh and add to it whenever something new changes hands.
#
# INTERLEAVED, because CPU time is not load-invariant: the same binary on the
# same input measured 20.48 / 18.95 / 10.87 / 10.14 CPU seconds across four
# reps as load varied.  A serial A/B attributes that to the code.
#
# DO NOT RUN THIS UNDER ANOTHER SWEEP, and do not run it at REPS=1.  The same
# twelve-problem list, same two builds, gave 1 lost and then 2 lost at REPS=1
# while an 8,996-problem A/B was saturating all 64 slots -- both figures noise,
# because a 10 s budget on a loaded machine is not the same budget.  Hence the
# default of two reps and the rule that a flip counts only if it reproduces in
# EVERY rep on both sides.  The load average is printed with the result so a
# surprising number can be read in context.
set -u
A=${1:?need the baseline bin dir}
B=${2:?need the candidate bin dir}
SECS=${3:-10}
JOBS=${4:-32}
MEM_KB=${MEM_KB:-4000000}
REPS=${REPS:-2}
HERE=$(cd "$(dirname "$0")" && pwd)
ONE=${CAP_ONE:-$HERE/run_one.sh}
TPTP=${TPTP_DIR:-$HOME/Projects/TPTP/TPTP-v9.3.1}
LIST=${CAP_LIST:-$HERE/cap_gate_problems.txt}

for p in "$A/prover9" "$B/prover9" "$ONE"; do
  [ -x "$p" ] || { echo "cap_gate: SKIP (cannot execute $p)"; exit 0; }
done
[ -d "$TPTP" ] && [ -r "$LIST" ] || { echo "cap_gate: SKIP (no TPTP library or problem list)"; exit 0; }

W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' 0 1 2 3 15
cat > $W/one.sh <<'INNER'
#!/bin/bash
set -u
IFS=$'\t' read -r side prog p rep <<< "$1"
case $side in A) bin=$BIN_A ;; B) bin=$BIN_B ;; esac
row=$( ulimit -v "$MEM_KB"; BIN_DIR="$bin" TPTP_SECS="$SECS" \
       timeout $((SECS*8+120)) "$H" "$prog" "$p" 2>/dev/null )
v=$(printf '%s' "$row" | awk -F'\t' '{print $7}')
printf '%s\t%s\t%s\t%s\n' "$side" "$prog" "$p" "${v:-NOROW}" >> "$OUT"
INNER
chmod +x $W/one.sh
: > $W/out
awk -v r="$REPS" '{ for (i=1;i<=r;i++) for (s="A"; s!="done"; s=(s=="A"?"B":"done")) {
      printf "%s\tprover9\t%s\t%d\n", s, $0, i; printf "%s\tmace4\t%s\t%d\n", s, $0, i } }' \
  "$LIST" | shuf > $W/work
echo "cap_gate: $(wc -l < "$LIST") problems, both provers, $REPS reps per build, ${SECS}s CPU, $JOBS jobs"
echo "cap_gate: load average now $(cut -d' ' -f1-3 /proc/loadavg) on $(nproc) cores -- a loaded machine makes a ${SECS}s budget mean less"
cd "$TPTP" || exit 2
xargs -a $W/work -d'\n' -P "$JOBS" -I{} \
  env BIN_A="$A" BIN_B="$B" SECS="$SECS" MEM_KB="$MEM_KB" H="$ONE" OUT=$W/out $W/one.sh '{}'

awk -F'\t' '
  function w(v) { return (v=="PROVED"||v=="MODEL"||v=="EXHAUSTED") }
  { k=$2 SUBSEP $3; if ($1=="A") { na[k]++; if (w($4)) wa[k]++ } else { nb[k]++; if (w($4)) wb[k]++ } }
  END {
    lost=0; gained=0
    for (k in na) {
      split(k, f, SUBSEP)
      a=wa[k]+0; b=wb[k]+0
      # only a flip that reproduces in EVERY rep on both sides counts
      if (a==na[k] && b==0) { printf "  LOST    %-8s %s\n", f[1], f[2]; lost++ }
      else if (a==0 && b==nb[k]) { printf "  gained  %-8s %s\n", f[1], f[2]; gained++ }
    }
    printf "\ncap_gate: %d lost, %d gained\n", lost, gained
    if (lost > 0) {
      print "cap_gate: FAIL -- the candidate loses a problem the baseline answers."
      print "  Before concluding the prover is slower, run cross_feed.sh: if the"
      print "  translation changed, the baseline was answering a different formula."
      exit 1
    }
    print "cap_gate: PASS"
  }' $W/out
