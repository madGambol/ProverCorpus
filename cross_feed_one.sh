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
# $1 = "problem<TAB>xlate(A|B)<TAB>prover(A|B)"  -> problem xlate prover verdict
set -u
IFS=$'\t' read -r p x pr <<< "$1"
k=$(printf '%s' "$p" | tr / _)
in=$D/$k.$x
case $pr in A) bin=$BIN_A ;; B) bin=$BIN_B ;; esac
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
printf 'assign(max_seconds,%s).\nassign(max_megs,2000).\n' "$SECS" > $t/opt
out=$( ulimit -v "$MEM_KB"; ( ulimit -t $((SECS+15)); exec timeout $((SECS*8+120)) "$bin/prover9" -f $t/opt "$in" ) 2>&1 )
rc=$?
echo "$out" | grep -qE 'Exiting with [1-9][0-9]* proof' && rc=0
case $rc in 0) v=PROVED;; 2) v=EXHAUSTED;; 3) v=MAX_MEGS;; 4) v=MAX_SECONDS;; 1) v=FATAL;;
  102) v=SIGSEGV;; 124) v=WALL_KILL;; 137|152) v=CPU_KILL;; *) v=OTHER_$rc;; esac
printf '%s\t%s\t%s\t%s\n' "$p" "$x" "$pr" "$v" >> "$OUT"
