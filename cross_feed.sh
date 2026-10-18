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
# cross_feed.sh BASELINE.tsv CURRENT.tsv  -- attribute a capability change to
#                                           the INPUT or to the PROVER.
#
# WHY.  When two builds differ in both the translator and the prover, a
# problem that one answers and the other does not has two possible causes and
# the A/B cannot tell them apart.  A corrected translation is a DIFFERENT
# problem, usually a harder one, so losing it is not a regression -- the old
# build was answering a formula the input never asked for.  A slower prover on
# the same formula is a regression.
#
# So run all four combinations of {baseline, current} translation x
# {baseline, current} prover on each problem that changed hands:
#
#   neither prover answers the CURRENT translation   -> the input changed
#   the baseline prover answers it and ours does not -> the prover regressed
#   the current pipeline answers it this time        -> it was noise
#
# Applied to the 205 prover9 losses in the first capability A/B of this tree,
# this said 186 input, 13 prover, 6 noise -- and the 13 bisected to one commit
# (R1 in ../Prover9Mace4/FIXES.md).  Without the split, the headline was a
# 134-answer regression; with it, 13.
#
# Needs the two translations dumped per problem as $D/<mangled path>.{A,B};
# dump_translations.sh does that.
set -u
A=${1:?need the baseline tsv}
B=${2:?need the current tsv}
BIN_A=${BIN_A:?set BIN_A}
BIN_B=${BIN_B:?set BIN_B}
D=${D:?set D, the directory of dumped translations}
SECS=${SECS:-10}
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
JOBS=${JOBS:-$_cores}
PROG=${PROG:-prover9}
HERE=$(cd "$(dirname "$0")" && pwd)

# The TPTP library is not part of this repository and there is no portable
# place to look for it, so the default below is only where it sits on the
# machine this was written on.  Every problem path is relative to its root, so
# a wrong root is not one missing file but every run failing -- check it here,
# once, and name TPTP_DIR in the message so the fix is obvious.
TPTP=${TPTP_DIR:-$HOME/Projects/TPTP/TPTP-v9.3.1}
[ -d "$TPTP" ] || { echo "no TPTP library at $TPTP -- set TPTP_DIR to the root of a TPTP release" >&2; exit 2; }

# The caller's two bin directories and the dump directory are made absolute
# while the caller's directory is still current: the four combinations below
# run after a cd into the TPTP library, where a relative one names nothing --
# the dumped translations would be looked for inside the library and the
# provers would not be found at all, which reads as every lost problem being
# the input's fault.  An absolute path is passed through untouched.
case $BIN_A in /*) ;; *) BIN_A=$PWD/$BIN_A ;; esac
case $BIN_B in /*) ;; *) BIN_B=$PWD/$BIN_B ;; esac
case $D in /*) ;; *) D=$PWD/$D ;; esac

W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' 0 1 2 3 15

win='$7=="PROVED"||$7=="MODEL"||$7=="EXHAUSTED"'
awk -F'\t' "\$1==\"$PROG\" && $win {print \$NF}" "$A" | sort -u > $W/a
awk -F'\t' "\$1==\"$PROG\" && $win {print \$NF}" "$B" | sort -u > $W/b
comm -23 $W/a $W/b > $W/lost
n=$(wc -l < $W/lost)
echo "$n $PROG problems lost; 4 combinations each"
[ "$n" -eq 0 ] && exit 0

: > $W/out
awk '{printf "%s\tA\tA\n%s\tA\tB\n%s\tB\tA\n%s\tB\tB\n",$0,$0,$0,$0}' $W/lost | shuf > $W/work
cd "$TPTP" || { echo "cannot enter the TPTP library at $TPTP -- set TPTP_DIR" >&2; exit 2; }
xargs -a $W/work -d'\n' -P "$JOBS" -I{} \
  env BIN_A="$BIN_A" BIN_B="$BIN_B" D="$D" SECS="$SECS" MEM_KB="$MEM_KB" \
      OUT=$W/out "$HERE/cross_feed_one.sh" '{}'

awk -F'\t' 'function w(v){return (v=="PROVED"||v=="EXHAUSTED")}
  { v[$1 $2 $3]=$4; p[$1]=1 }
  END {
    for (k in p) {
      ba=w(v[k "BA"]); bb=w(v[k "BB"])
      if (!bb && !ba)   c="INPUT"
      else if (!bb)     c="PROVER"
      else              c="NOISE"
      printf "%s\t%s\t%s/%s/%s/%s\n", c, k, v[k "AA"], v[k "AB"], v[k "BA"], v[k "BB"]
      t[c]++
    }
    printf "\nINPUT %d (the corrected translation defeats both provers)\n", t["INPUT"]+0
    printf "PROVER %d (the baseline prover answers the corrected input, ours does not)\n", t["PROVER"]+0
    printf "NOISE %d (the current pipeline answered it this time)\n", t["NOISE"]+0
  }' $W/out | sort
