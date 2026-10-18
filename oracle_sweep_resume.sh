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

# Default concurrency is derived, not fixed: one run per core, and no more
# than memory allows at the per-run ceiling.  A fixed number is wrong on every
# machine except the one it was tuned on -- 32 concurrent runs on a four-core
# laptop is eightfold oversubscription, and at this ceiling each it is an OOM
# kill partway through a sweep rather than a slow sweep.  It scales up as well
# as down, and an explicit argument or JOBS= still wins over both.
_cores=$( (nproc || getconf _NPROCESSORS_ONLN) 2>/dev/null || echo 1 )
_job_mb=800
_avail_mb=$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo 2>/dev/null)
if [ -n "${_avail_mb:-}" ] && [ "${_avail_mb:-0}" -gt 0 ] && [ "$_job_mb" -gt 0 ]; then
  _mem_jobs=$(( _avail_mb / _job_mb ))
  [ "$_mem_jobs" -lt 1 ] && _mem_jobs=1
  [ "$_mem_jobs" -lt "$_cores" ] && _cores=$_mem_jobs
fi
[ "$_cores" -lt 1 ] && _cores=1
JOBS=${3:-$_cores}
CGROUP_MAX=${CGROUP_MAX:-180G}
HERE=$(cd "$(dirname "$0")" && pwd)
RUNNER=$HERE/oracle_retry_capped.sh

# The TPTP library is not part of this repository and there is no portable
# place to look for it, so the default below is only where it sits on the
# machine this was written on.  Every problem path is relative to its root, so
# a wrong root is not one missing file but every run failing -- check it here,
# once, and name TPTP_DIR in the message so the fix is obvious.
TPTP_DIR=${TPTP_DIR:-$HOME/Projects/TPTP/TPTP-v9.3.1}
[ -d "$TPTP_DIR" ] || { echo "no TPTP library at $TPTP_DIR -- set TPTP_DIR to the root of a TPTP release" >&2; exit 2; }

[ -r "$FULL" ]    || { echo "cannot read $FULL" >&2; exit 2; }
[ -x "$RUNNER" ]  || { echo "cannot execute $RUNNER" >&2; exit 2; }
touch "$OUT"      || { echo "cannot write $OUT" >&2; exit 2; }

# Each pass cds into the TPTP library before appending to this file, so a
# relative path would land inside the library -- or, far more often, fail to
# open there and leave the pass having added nothing, which the loop below
# reads as "the driver did not survive" and answers by halving the job count.
# Make it absolute here, while the caller's directory is still current.
OUT=$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")

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
