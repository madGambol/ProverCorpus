#!/bin/bash
#
# baseline_ab.sh -- the capability A/B: same TPTP sample, same budget,
#                   baseline against current, INTERLEAVED.
#
# WHY INTERLEAVED, AND NOT ONE BUILD THEN THE OTHER.  CPU time is not
# load-invariant: it measures time on core, and under memory-bandwidth and
# cache contention a process does less work per on-core second.  Measured on
# this machine, the same binary on the same input took 20.48, 18.95, 10.87 and
# 10.14 CPU seconds across four reps as load varied -- a 2x spread with no
# code difference at all.  Running one build to completion and then the other
# would hand them different load conditions and attribute the difference to
# the code.  So both builds' runs go into one queue, alternating, and every
# run of either build sees the same average contention.
#
# WHY A MEMORY CAP ON BOTH SIDES.  The baseline predates M9-M13, so its cell
# table, negprop index and ground-clause generation are all unbounded; an
# uncapped sweep of it is what exhausted this machine's swap and cost a
# reboot.  Both sides therefore run under the same cgroup with swap forbidden
# and the same per-run address-space cap.  The cap is part of the experimental
# condition, applied identically, and is reported with the result.  Baseline
# crashes and fatals are counted as categories rather than prevented: a prover
# that cannot be run under a memory budget is worse than one that can, and the
# table should show it.
#
# jobs x per-run cap must fit the cgroup budget.  32 x 4 GB = 128 GB under a
# 160 GB ceiling.  Getting this wrong (12 GB x 64 = 768 GB under 160 GB) had
# the kernel OOM-kill the driver and end a 5,171-run sweep at 1,236 rows.
#
# Usage: baseline_ab.sh BIN_A BIN_B OUT_A OUT_B [SAMPLE] [SECS] [JOBS]

set -u
A=${1:?need the baseline bin dir}
B=${2:?need the current bin dir}
OUTA=${3:?need the baseline output tsv}
OUTB=${4:?need the current output tsv}
SAMPLE=${5:-$HOME/Projects/prover9-corpus/oracle_sample.txt}
SECS=${6:-10}
JOBS=${7:-32}
MEM_KB=${MEM_KB:-4000000}
CGROUP_MAX=${CGROUP_MAX:-160G}
HERE=$(cd "$(dirname "$0")" && pwd)
ONE=${RUN_ONE:-$HERE/run_one.sh}
TPTP=${TPTP_DIR:-$HOME/Projects/TPTP/TPTP-v9.3.1}

for p in "$ONE" "$A/prover9" "$B/prover9"; do
  [ -x "$p" ] || { echo "cannot execute $p" >&2; exit 2; }
done
[ -r "$SAMPLE" ] || { echo "cannot read $SAMPLE" >&2; exit 2; }

# worker: "side<TAB>prog<TAB>path" -> one row appended to that side's file
cat > "$HERE/.ab_one.sh" <<'EOF'
#!/bin/bash
set -u
line=$1
side=${line%%	*}; rest=${line#*	}
prog=${rest%%	*}; p=${rest#*	}
case $side in A) bin=$BIN_A; out=$OUT_A ;; B) bin=$BIN_B; out=$OUT_B ;; *) exit 0 ;; esac
row=$( ulimit -v "$MEM_KB"; BIN_DIR="$bin" TPTP_SECS="$SECS" timeout "$WALL" "$H" "$prog" "$p" 2>/dev/null )
[ -n "$row" ] && printf '%s\n' "$row" >> "$out"
EOF
chmod +x "$HERE/.ab_one.sh"

touch "$OUTA" "$OUTB"
work=$(mktemp) || exit 2
trap 'rm -f "$work"' 0 1 2 3 15

# RESUMABLE.  A row's first field is the prover and its last is the problem
# path, which with the side is exactly the key the work list is made of, so
# the remaining work is computable from the output.  Without this a driver
# killed at hour six costs the whole run -- which is how a 5,171-run sweep
# ended at 1,236 rows when a cgroup OOM-killed its xargs.
{
  awk -F'\t' '{print "A\t" $1 "\t" $NF}' "$OUTA"
  awk -F'\t' '{print "B\t" $1 "\t" $NF}' "$OUTB"
} | sort -u > "$work.done"

awk '{ printf "A\tprover9\t%s\nB\tprover9\t%s\nA\tmace4\t%s\nB\tmace4\t%s\n", $0,$0,$0,$0 }' \
  "$SAMPLE" | sort -u > "$work.all"
comm -23 "$work.all" "$work.done" | shuf > "$work"
rm -f "$work.all" "$work.done"

total=$(wc -l < "$work")
have=$(( $(wc -l < "$OUTA") + $(wc -l < "$OUTB") ))
echo "$total runs left of 35968 ($have already recorded), $JOBS jobs, ${SECS}s CPU, ${MEM_KB}KB cap, cgroup $CGROUP_MAX"
echo $$ > "$(dirname "$OUTA")/ab.pid"

systemd-run --user --scope -q -p "MemoryMax=$CGROUP_MAX" -p MemorySwapMax=0 \
  env BIN_A="$A" BIN_B="$B" OUT_A="$OUTA" OUT_B="$OUTB" \
      SECS="$SECS" MEM_KB="$MEM_KB" WALL=$((SECS * 8 + 120)) H="$ONE" \
  bash -c "cd '$TPTP' && xargs -a '$work' -d'\\n' -P $JOBS -I{} '$HERE/.ab_one.sh' '{}'"

echo "baseline rows: $(wc -l < "$OUTA")"
echo "current  rows: $(wc -l < "$OUTB")"
