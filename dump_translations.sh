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
# dump_translations.sh PROBLEM_LIST OUT_DIR -- translate each problem with both
# builds, saving $OUT/<mangled path>.A and .B for cross_feed.sh and freevars.py.
set -u
L=${1:?need a problem list}
D=${2:?need an output directory}
BIN_A=${BIN_A:?set BIN_A}
BIN_B=${BIN_B:?set BIN_B}
JOBS=${JOBS:-32}
mkdir -p "$D"
cd "${TPTP_DIR:-$HOME/Projects/TPTP/TPTP-v9.3.1}" || exit 2
xargs -a "$L" -d'\n' -P "$JOBS" -I{} env BIN_A="$BIN_A" BIN_B="$BIN_B" D="$D" bash -c '
  p=$0; k=$(printf "%s" "$p" | tr / _)
  ( ulimit -t 300 -s 200000; exec timeout 400 "$BIN_A/tptp_to_ladr" ) < "$p" > "$D/$k.A" 2>/dev/null
  ( ulimit -t 300 -s 200000; exec timeout 400 "$BIN_B/tptp_to_ladr" ) < "$p" > "$D/$k.B" 2>/dev/null
' {}
echo "dumped $(ls "$D" | wc -l) files"
