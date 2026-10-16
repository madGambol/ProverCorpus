#!/bin/bash
#
# baseline_ab.sh -- the capability A/B this project did not have: the same
#                   TPTP sample, the same budget, pristine against current.
#
# WHY IT IS NEEDED.  Every sweep run here measured a fixed build, so the
# figures were absolute, not differential: "Prover9 answers 38.5% at 10 s"
# says nothing about whether this tree's work helped.  The claim that the
# work produced a better prover needs both sides measured the same way.
#
# WHAT TO EXPECT, and why.  The PF2-PF10 series cut startup on a large input
# from 157.53 s to 3.80 s.  At a fixed 10-second budget that should convert
# timeouts into answers on the big problems, because pristine spends the whole
# budget in preprocessing and never reaches a search.  That is the hypothesis;
# this measures it instead of assuming it.
#
# A DESIGN NOTE THAT IS ITSELF A RESULT.  Pristine cannot safely run this
# sweep: without M9-M12 its cell table, negprop index and ground-clause
# generation are all unbounded, which is what exhausted this machine's swap
# and cost a reboot.  So both sides run inside the same cgroup with swap
# forbidden and the same per-run address-space cap, and pristine's SIGSEGVs
# and FATALs are counted as categories rather than being prevented.  A prover
# that cannot be run under a memory budget is worse than one that can, and
# the table should show that rather than hide it.
#
# Usage: baseline_ab.sh BIN_A BIN_B OUT_A OUT_B [SAMPLE] [SECS] [JOBS]

set -u
A=${1:?need the baseline bin dir}
B=${2:?need the current bin dir}
OUTA=${3:?need the baseline output tsv}
OUTB=${4:?need the current output tsv}
SAMPLE=${5:-$HOME/Projects/prover9-corpus/oracle_sample.txt}
SECS=${6:-10}
JOBS=${7:-40}
MEM_KB=${MEM_KB:-12000000}
CGROUP_MAX=${CGROUP_MAX:-160G}
HERE=$(cd "$(dirname "$0")" && pwd)
ONE=/home/chris/Projects/TPTP/results-prover9mace4/cap2_one.sh
TPTP=${TPTP_DIR:-$HOME/Projects/TPTP/TPTP-v9.3.1}

[ -x "$ONE" ] || { echo "cannot execute $ONE" >&2; exit 2; }
[ -r "$SAMPLE" ] || { echo "cannot read $SAMPLE" >&2; exit 2; }

# one prover, one problem, one build -- capped the same way on both sides
cat > "$HERE/.ab_one.sh" <<'EOF'
#!/bin/bash
set -u
prog="${1%%	*}"; p="${1#*	}"
ulimit -v "$MEM_KB"
exec timeout "$WALL" "$H" "$prog" "$p"
EOF
chmod +x "$HERE/.ab_one.sh"

run() {   # run <bin> <out>
  bin=$1; out=$2
  : > "$out"
  # both provers for every problem, which is what the sample lines mean
  awk '{print "prover9\t" $0 "\nmace4\t" $0}' "$SAMPLE" > "$out.work"
  echo "  $(wc -l < "$out.work") runs against $bin"
  systemd-run --user --scope -q -p "MemoryMax=$CGROUP_MAX" -p MemorySwapMax=0 \
    env BIN_DIR="$bin" TPTP_SECS="$SECS" MEM_KB="$MEM_KB" WALL=$((SECS * 8 + 120)) \
        H="$ONE" \
    bash -c "cd '$TPTP' && xargs -a '$out.work' -d'\\n' -P $JOBS -I{} '$HERE/.ab_one.sh' '{}' >> '$out' 2>/dev/null"
  rm -f "$out.work"
  echo "  $(wc -l < "$out") rows written to $out"
}

echo "=== baseline: $A ==="
run "$A" "$OUTA"
echo "=== current: $B ==="
run "$B" "$OUTB"
echo "done; score with oracle_scoreboard.sh on each, and diff the categories"
