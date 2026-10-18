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
# dump_translations.sh PROBLEM_LIST OUT_DIR -- translate each problem with both
# builds, saving $OUT/<mangled path>.A and .B for cross_feed.sh and freevars.py.
set -u
L=${1:?need a problem list}
D=${2:?need an output directory}
BIN_A=${BIN_A:?set BIN_A}
BIN_B=${BIN_B:?set BIN_B}

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
JOBS=${JOBS:-$_cores}

# The TPTP library is not part of this repository and there is no portable
# place to look for it, so the default below is only where it sits on the
# machine this was written on.  Every problem path is relative to its root, so
# a wrong root is not one missing file but every run failing -- check it here,
# once, and name TPTP_DIR in the message so the fix is obvious.
TPTP=${TPTP_DIR:-$HOME/Projects/TPTP/TPTP-v9.3.1}
[ -d "$TPTP" ] || { echo "no TPTP library at $TPTP -- set TPTP_DIR to the root of a TPTP release" >&2; exit 2; }

# All four of the caller's paths are made absolute before the cd below,
# because after it a relative one quietly means something else: the list would
# be looked for inside the TPTP library, the dumps written into it, and
# neither build found at all -- and the problem paths a list holds are
# relative to that same root, so nothing complains.  mkdir runs in the
# caller's directory, so the directory created and the directory written have
# to be made to agree.  The list and the output directory are checked here, so
# those two can be normalised by entering them; the builds are not, so they
# are only prefixed, and an already absolute path is left untouched.
[ -r "$L" ] || { echo "cannot read the problem list $L" >&2; exit 2; }
L=$(cd "$(dirname "$L")" && pwd)/$(basename "$L")
mkdir -p "$D" || { echo "cannot create the output directory $D" >&2; exit 2; }
D=$(cd "$D" && pwd) || exit 2
case $BIN_A in /*) ;; *) BIN_A=$PWD/$BIN_A ;; esac
case $BIN_B in /*) ;; *) BIN_B=$PWD/$BIN_B ;; esac

cd "$TPTP" || { echo "cannot enter the TPTP library at $TPTP -- set TPTP_DIR" >&2; exit 2; }
xargs -a "$L" -d'\n' -P "$JOBS" -I{} env BIN_A="$BIN_A" BIN_B="$BIN_B" D="$D" bash -c '
  p=$0; k=$(printf "%s" "$p" | tr / _)
  ( ulimit -t 300 -s 200000; exec timeout 400 "$BIN_A/tptp_to_ladr" ) < "$p" > "$D/$k.A" 2>/dev/null
  ( ulimit -t 300 -s 200000; exec timeout 400 "$BIN_B/tptp_to_ladr" ) < "$p" > "$D/$k.B" 2>/dev/null
' {}
echo "dumped $(ls "$D" | wc -l) files"
