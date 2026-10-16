#!/bin/bash
#
# oracle_sweep_resume.sh -- run a prover/problem list to completion, resuming
#                           automatically if the driver is killed.
#
# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# A long sweep is bounded by a cgroup so that it can never again take the
# machine away from its owner:
#
#   systemd-run --user --scope -p MemoryMax=180G -p MemorySwapMax=0
#
# That works -- MemorySwapMax=0 forbids the spill-to-swap that caused a
# lockout, and the peak is capped.  But when a cgroup reaches MemoryMax the
# kernel kills a process inside it, and the process it picks is often the
# scope's own xargs rather than one greedy prover.  Killing the driver ends
# the whole sweep.  That is what happened: a 5171-run sweep stopped at 1236
# rows, with the journal reading
#
#   run-p55604.scope: A process of this unit has been killed by the OOM killer
#   run-p55604.scope: Consumed 3d 4h 56min CPU time, 180G memory peak
#
# The rows already written were perfectly good -- the TSV is append-only and
# holds one line per completed run -- so nothing was wrong with the data.  The
# only thing missing was something to start again from where it stopped.
#
# The underlying cause was arithmetic that never held: a per-run address-space
# cap of 12 GB times 64 concurrent jobs permits 768 GB against a 180 GB
# ceiling.  Those two numbers must be consistent, so this script also halves
# the job count each time the driver is killed, which converges on a count the
# budget can actually support instead of needing it guessed correctly up front.
#
# ---------------------------------------------------------------------------
# USAGE
#
#   oracle_sweep_resume.sh FULL_LIST OUT_TSV [JOBS]
#
#   FULL_LIST   lines of "prog<TAB>path" -- the complete intended run
#   OUT_TSV     append-only results; existing rows are kept and skipped
#   JOBS        starting concurrency (default 64)
#
# Environment passed through to the per-run script: TPTP_SECS, MEM_KB, WALL,
# BIN_DIR, MAX_MEGS.  CGROUP_MAX sets MemoryMax (default 180G).
# ---------------------------------------------------------------------------

set -u
FULL=${1:?need the full prog<TAB>path list}
OUT=${2:?need the output tsv}
JOBS=${3:-64}
CGROUP_MAX=${CGROUP_MAX:-180G}
HERE=$(cd "$(dirname "$0")" && pwd)
RUNNER=$HERE/oracle_retry_capped.sh
TPTP_DIR=${TPTP_DIR:-$HOME/Projects/TPTP/TPTP-v9.3.1}

[ -r "$FULL" ]    || { echo "cannot read $FULL" >&2; exit 2; }
[ -x "$RUNNER" ]  || { echo "cannot execute $RUNNER" >&2; exit 2; }
touch "$OUT"      || { echo "cannot write $OUT" >&2; exit 2; }

stalls=0
pass=0

while :; do
  pass=$((pass + 1))
  remaining=$(mktemp) || exit 2

  # A row's first field is the prover and its last is the problem path, which
  # is exactly the key the list is made of.  Anything already recorded is done.
  awk -F'\t' 'NR==FNR { done[$1 "\t" $NF] = 1; next }
              !($0 in done)' "$OUT" "$FULL" > "$remaining"

  todo=$(wc -l < "$remaining")
  have=$(wc -l < "$OUT")
  if [ "$todo" -eq 0 ]; then
    rm -f "$remaining"
    echo "sweep complete: $have rows, nothing left to run"
    exit 0
  fi

  echo "pass $pass: $have rows done, $todo to run, $JOBS jobs, MemoryMax=$CGROUP_MAX"
  before=$have

  systemd-run --user --scope -q \
      -p "MemoryMax=$CGROUP_MAX" -p MemorySwapMax=0 \
      bash -c "cd '$TPTP_DIR' && xargs -a '$remaining' -d'\\n' -P $JOBS -I{} '$RUNNER' '{}' >> '$OUT' 2>> '$OUT.err'"
  rc=$?

  after=$(wc -l < "$OUT")
  added=$((after - before))
  rm -f "$remaining"
  echo "pass $pass ended (rc=$rc), $added rows added"

  if [ "$added" -eq 0 ]; then
    stalls=$((stalls + 1))
    if [ "$stalls" -ge 3 ]; then
      echo "three passes in a row added nothing; stopping rather than looping" >&2
      exit 1
    fi
  else
    stalls=0
  fi

  # rc 0 with work left means xargs itself was killed, not that it finished.
  if [ "$rc" -ne 0 ] || [ "$added" -eq 0 ]; then
    if [ "$JOBS" -gt 8 ]; then
      JOBS=$((JOBS / 2))
      echo "driver did not survive; halving concurrency to $JOBS"
    fi
  fi
done
