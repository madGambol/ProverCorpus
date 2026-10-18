#!/bin/bash

#  Copyright (C) 2026 Chris Arena, 2026-10-16.
#  Written in collaboration with Claude Opus 5 (Anthropic).
#
#  This file is part of the Prover9/Mace4 regression corpus, the test
#  material for the Prover9Mace4 tree.  It is not part of William
#  McCune's LADR-2009-11A release; see LICENSING.md for what here is
#  his and redistributed unmodified.
#
#  This corpus is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License, version 2 --
#  the licence of the programs it tests, which say "version 2" with no
#  later-version clause.
#
#  It is distributed in the hope that it will be useful, but WITHOUT
#  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
#  or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
#  License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this corpus, in COPYING; if not, write to the Free
#  Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
#  MA 02110-1301 USA.
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
# The sample ships in this repository, so it is found next to this script
# rather than at one absolute path -- a clone works wherever it is put, and an
# explicit fifth argument still wins.
HERE=$(cd "$(dirname "$0")" && pwd)
A=${1:?need the baseline bin dir}
B=${2:?need the current bin dir}
OUTA=${3:?need the baseline output tsv}
OUTB=${4:?need the current output tsv}
SAMPLE=${5:-$HERE/oracle_sample.txt}
SECS=${6:-10}
MEM_KB=${MEM_KB:-4000000}

# Default concurrency is derived, not fixed: one run per core, and no more
# than memory allows at the per-run ceiling.  A fixed number is wrong on every
# machine except the one it was tuned on -- 32 concurrent runs on a four-core
# laptop is eightfold oversubscription, and at this ceiling each it is an OOM
# kill partway through a sweep rather than a slow sweep.  It scales up as well
# as down, and an explicit argument or JOBS= still wins over both.
_cores=$( (nproc || getconf _NPROCESSORS_ONLN) 2>/dev/null || echo 1 )
_job_mb=$(( MEM_KB / 1024 ))
_avail_mb=$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo 2>/dev/null)
if [ -n "${_avail_mb:-}" ] && [ "${_avail_mb:-0}" -gt 0 ] && [ "$_job_mb" -gt 0 ]; then
  _mem_jobs=$(( _avail_mb / _job_mb ))
  [ "$_mem_jobs" -lt 1 ] && _mem_jobs=1
  [ "$_mem_jobs" -lt "$_cores" ] && _cores=$_mem_jobs
fi
[ "$_cores" -lt 1 ] && _cores=1
JOBS=${7:-$_cores}
CGROUP_MAX=${CGROUP_MAX:-160G}
ONE=${RUN_ONE:-$HERE/run_one.sh}

# The TPTP library is not part of this repository and there is no portable
# place to look for it, so the default below is only where it sits on the
# machine this was written on.  Every problem path is relative to its root, so
# a wrong root is not one missing file but every run failing -- check it here,
# once, and name TPTP_DIR in the message so the fix is obvious.
TPTP=${TPTP_DIR:-$HOME/Projects/TPTP/TPTP-v9.3.1}
[ -d "$TPTP" ] || { echo "no TPTP library at $TPTP -- set TPTP_DIR to the root of a TPTP release" >&2; exit 2; }

for p in "$ONE" "$A/prover9" "$B/prover9"; do
  [ -x "$p" ] || { echo "cannot execute $p" >&2; exit 2; }
done
[ -r "$SAMPLE" ] || { echo "cannot read $SAMPLE" >&2; exit 2; }

# The caller's four paths are made absolute while the caller's directory is
# still current, because the queue below runs inside a cgroup that cds into
# the TPTP library first.  After that cd a relative bin directory names
# nothing, so every run comes back empty, and a relative output file is
# appended to inside the library instead of where the caller asked -- the -x
# check above passes either way, so neither leaves a mark.  An absolute path
# is passed through untouched; $PWD rather than cd+pwd because the two output
# files need not exist yet.
case $A in /*) ;; *) A=$PWD/$A ;; esac
case $B in /*) ;; *) B=$PWD/$B ;; esac
case $OUTA in /*) ;; *) OUTA=$PWD/$OUTA ;; esac
case $OUTB in /*) ;; *) OUTB=$PWD/$OUTB ;; esac

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
