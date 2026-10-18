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
# recheck_changed.sh BASELINE.tsv CURRENT.tsv [REPS] [JOBS]
#
# Re-run only the (prover, problem) pairs that changed hands between two
# builds, several times each, interleaved, and report whether each flip is
# STABLE or NOISE.
#
# WHY.  A one-shot A/B at a fixed time budget cannot distinguish "this build
# is slower on this problem" from "this problem's solve time straddles the
# limit".  Measured on this machine, the same binary on the same input varied
# 20.48 / 18.95 / 10.87 / 10.14 CPU seconds across four reps as load changed
# -- a 2x spread with no code difference.  At a 10-second budget a problem
# near the boundary will flip at random, and a handful of such flips is
# exactly what a capability A/B reports as a regression.
#
# So: each pair is run REPS times per build, the runs are interleaved so both
# builds see the same contention, and a flip only counts if it reproduces
# every time.
set -u
A=${1:?need the baseline tsv}
B=${2:?need the current tsv}
REPS=${3:-5}
BIN_A=${BIN_A:?set BIN_A}
BIN_B=${BIN_B:?set BIN_B}
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
JOBS=${4:-$_cores}
HERE=$(cd "$(dirname "$0")" && pwd)
ONE=${RUN_ONE:-$HERE/run_one.sh}

# The TPTP library is not part of this repository and there is no portable
# place to look for it, so the default below is only where it sits on the
# machine this was written on.  Every problem path is relative to its root, so
# a wrong root is not one missing file but every run failing -- check it here,
# once, and name TPTP_DIR in the message so the fix is obvious.
TPTP=${TPTP_DIR:-$HOME/Projects/TPTP/TPTP-v9.3.1}
[ -d "$TPTP" ] || { echo "no TPTP library at $TPTP -- set TPTP_DIR to the root of a TPTP release" >&2; exit 2; }

# The caller's two bin directories are made absolute while the caller's
# directory is still current: the reps below run after a cd into the TPTP
# library, where a relative one names nothing and every rep comes back empty
# -- which this script would report as NOISE on every pair, the one verdict
# that invites someone to dismiss a real regression.  An absolute path is
# passed through untouched.
case $BIN_A in /*) ;; *) BIN_A=$PWD/$BIN_A ;; esac
case $BIN_B in /*) ;; *) BIN_B=$PWD/$BIN_B ;; esac

W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' 0 1 2 3 15

win='$7=="PROVED"||$7=="MODEL"||$7=="EXHAUSTED"'
awk -F'\t' "$win {print \$1\"\t\"\$NF}" "$A" | sort -u > $W/a
awk -F'\t' "$win {print \$1\"\t\"\$NF}" "$B" | sort -u > $W/b
comm -13 $W/a $W/b | sed 's/^/gained\t/' >  $W/changed
comm -23 $W/a $W/b | sed 's/^/lost\t/'   >> $W/changed
n=$(wc -l < $W/changed)
echo "$n pairs changed hands; $REPS reps per build, interleaved"
[ "$n" -eq 0 ] && exit 0

cat > $W/one.sh <<'EOF'
#!/bin/bash
set -u
IFS=$'\t' read -r dir side prog p rep <<< "$1"
case $side in A) bin=$BIN_A ;; B) bin=$BIN_B ;; esac
row=$( ulimit -v "$MEM_KB"; BIN_DIR="$bin" TPTP_SECS="$SECS" timeout $((SECS*8+120)) "$H" "$prog" "$p" 2>/dev/null )
v=$(printf '%s' "$row" | awk -F'\t' '{print $7}')
printf '%s\t%s\t%s\t%s\t%s\n' "$dir" "$side" "$prog" "$p" "${v:-NOROW}" >> "$OUT"
EOF
chmod +x $W/one.sh
: > $W/out
awk -v r="$REPS" -F'\t' '{ for (i=1;i<=r;i++) { printf "%s\tA\t%s\t%s\t%d\n", $1,$2,$3,i; printf "%s\tB\t%s\t%s\t%d\n", $1,$2,$3,i } }' \
  $W/changed | shuf > $W/work

cd "$TPTP" || { echo "cannot enter the TPTP library at $TPTP -- set TPTP_DIR" >&2; exit 2; }
BIN_A="$BIN_A" BIN_B="$BIN_B" SECS="$SECS" MEM_KB="$MEM_KB" H="$ONE" OUT="$W/out" \
  xargs -a $W/work -d'\n' -P "$JOBS" -I{} env BIN_A="$BIN_A" BIN_B="$BIN_B" SECS="$SECS" \
     MEM_KB="$MEM_KB" H="$ONE" OUT="$W/out" $W/one.sh '{}'

echo
printf '  %-7s %-8s %-34s %-22s %-22s %s\n' DIR PROG PROBLEM "baseline wins/reps" "current wins/reps" VERDICT
awk -F'\t' -v reps="$REPS" '
  function isw(v) { return (v=="PROVED"||v=="MODEL"||v=="EXHAUSTED") }
  { k=$1 SUBSEP $3 SUBSEP $4; if ($2=="A") { na[k]++; if (isw($5)) wa[k]++ } else { nb[k]++; if (isw($5)) wb[k]++ } }
  END {
    for (k in na) {
      split(k, f, SUBSEP)
      a=wa[k]+0; b=wb[k]+0
      # a flip is stable only if it reproduces in every rep on both sides
      if ((a==na[k] && b==0) || (a==0 && b==nb[k])) verdict="STABLE"
      else verdict="NOISE"
      printf "  %-7s %-8s %-34s %-22s %-22s %s\n", f[1], f[2], f[3], a "/" na[k], b "/" nb[k], verdict
      tot[verdict]++
    }
    printf "\n  STABLE %d   NOISE %d\n", tot["STABLE"]+0, tot["NOISE"]+0
  }' $W/out | sort -k6,6 -k1,1
