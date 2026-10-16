#!/bin/bash

#  Copyright (C) 2026 Chris Arena and Claude Opus 5, 2026-10-16.
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
# Capability probe for one TPTP problem, v2.
#   usage: run_one.sh <prover9|mace4> <problem path relative to TPTP root>
# Emits TSV: prog dom form status rating nforms verdict ms rc problem
#
# Run with cwd = TPTP distribution root so include('Axioms/...') resolves.
#
# Limits are CPU-time, not wall-clock.  prover9/mace4 enforce max_seconds
# against user CPU time, so a wall-clock guard turns CPU contention into
# spurious timeouts: an earlier run at 80-way parallelism on 80 cores had 39%
# of its "timeouts" killed by the wall guard rather than by the real limit,
# which silently understates what the prover can do.  ulimit -t is therefore
# the backstop, and the wall guard is set far enough out that it only catches
# a genuine hang.
BIN=${BIN_DIR:-$(cd "$(dirname "$0")/../Prover9Mace4/bin" 2>/dev/null && pwd)}
TFAIL=${TFAIL_DIR:-${TMPDIR:-/tmp}/p9-tfail}
prog="$1"; p="$2"
SECS=${TPTP_SECS:-30}
WALL=$(( SECS * 8 + 120 ))

emit() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
         "$prog" "$dom" "$form" "${status:--}" "${rating:--}" "${nforms:--}" \
         "$1" "${2:--}" "${3:--}" "$p"; }

dom=$(basename "$(dirname "$p")")
case "$p" in *+*) form=FOF ;; *-*) form=CNF ;; *) form=other ;; esac

# Fail loudly rather than skipping.  An unreadable problem once made a whole
# 35,824-run sweep report "no-oracle" on every line, which looked like a pass.
if [ ! -r "$p" ]; then status=-; emit unreadable; exit 3; fi

hdr=$(head -80 "$p")
status=$(printf '%s' "$hdr" | grep -m1 '^% Status' | sed -E 's/^% Status +: +//; s/ .*//')
rating=$(printf '%s' "$hdr" | grep -m1 '^% Rating' | sed -E 's/^% Rating +: +//; s/[ ,].*//')
nforms=$(printf '%s' "$hdr" | grep -m1 -E 'Number of (formulae|clauses)' \
         | sed -E 's/.*Number of (formulae|clauses) *: *//; s/[ (].*//')

[ -z "$status" ] && { emit no-status-header; exit 3; }
case "$status" in
  Theorem|Unsatisfiable|Satisfiable|CounterSatisfiable|ContradictoryAxioms) ;;
  Unknown|Open) emit no-oracle; exit 0 ;;
  *) emit unexpected-status; exit 3 ;;
esac

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# tptp_to_ladr's parser is recursive and exhausts the default 8MB stack on the
# largest problems -- it segfaults on 146 of them, mostly in CSR, where the
# included SUMO axiom sets are huge.  Left unset so the default configuration
# is what gets measured; the rework pass sets it to recover those problems.
if [ -n "${TPTP_STACK:-}" ]; then ulimit -s "$TPTP_STACK" 2>/dev/null || true; fi
if ! ( ulimit -t 120; exec timeout 300 "$BIN/tptp_to_ladr" ) < "$p" \
       > "$t/in" 2>"$t/terr"; then
  mkdir -p "$TFAIL"
  # Keep the reason so the failures can be grouped and reworked.
  { echo "== $p"; head -5 "$t/terr"; } \
    >> "$TFAIL/$(printf '%s' "$p" | tr / _).err" 2>/dev/null
  emit translate-fail
  exit 0
fi
# max_megs defaults to 500 in LADR, a 2009-era figure.  Left at the default it
# is the binding constraint on plenty of problems (ALG021+1 hits it in 4s), so
# the limit is raised here and reported, rather than silently measuring the
# default's ceiling and calling it the prover's capability.
printf 'assign(max_seconds,%s).\nassign(max_megs,%s).\n' "$SECS" "${TPTP_MEGS:-2000}" > "$t/opt"

start=$(date +%s%3N)
out=$( ( ulimit -t $((SECS + 15)); exec timeout "$WALL" "$BIN/$prog" -f "$t/opt" "$t/in" ) 2>&1 )
rc=$?
ms=$(( $(date +%s%3N) - start ))

if [ "$prog" = prover9 ]; then
  # A run can report "Exiting with N proof" and still exit 2 (SOS_EMPTY): it
  # found a proof and then used up the clause space.  Classifying on the exit
  # code alone recorded 87 such runs as EXHAUSTED, understating the solve
  # count, so a reported proof wins over the exit code.
  if echo "$out" | grep -qE 'Exiting with [1-9][0-9]* proof'; then rc=0; fi
  case $rc in
    0)   v=PROVED ;;        # MAX_PROOFS_EXIT, or a proof reported above
    2)   v=EXHAUSTED ;;     # SOS_EMPTY_EXIT: saturated with no proof
    3)   v=MAX_MEGS ;;
    4)   v=MAX_SECONDS ;;
    5)   v=MAX_GIVEN ;;
    6)   v=MAX_KEPT ;;
    1)   v=FATAL ;;
    102) v=SIGSEGV ;;
    124) v=WALL_KILL ;;
    137|152) v=CPU_KILL ;;
    *)   v="OTHER_$rc" ;;
  esac
  [ "$v" = PROVED ] && case "$status" in
    Satisfiable|CounterSatisfiable) v=UNSOUND ;;
  esac
else
  found=no
  case $rc in
    0|3|4|6) found=yes ;;   # MAX_MODELS / ALL_MODELS / MAX_SEC_YES / MAX_MEGS_YES
  esac
  echo "$out" | grep -qE 'Exiting with [1-9][0-9]* model' && found=yes
  if [ "$found" = yes ]; then v=MODEL
  else
    case $rc in
      2)   v=EXHAUSTED ;;   # no model at the sizes tried
      5)   v=MAX_SECONDS ;;
      7)   v=MAX_MEGS ;;
      1)   v=FATAL ;;
      102) v=SIGSEGV ;;
      124) v=WALL_KILL ;;
      137|152) v=CPU_KILL ;;
      *)   v="OTHER_$rc" ;;
    esac
  fi
  [ "$v" = MODEL ] && case "$status" in
    Theorem|Unsatisfiable|ContradictoryAxioms) v=UNSOUND ;;
  esac
fi
emit "$v" "$ms" "$rc"
