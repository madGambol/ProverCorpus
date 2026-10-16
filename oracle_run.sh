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
# One TPTP problem, both provers, against a given build.  Emits the TSV that
# cap2_one.sh defines; the verdict column carries UNSOUND when a prover
# contradicts the problem's SZS status.
export BIN_DIR="${BIN_DIR:-$(cd "$(dirname "$0")/../Prover9Mace4/bin" 2>/dev/null && pwd)}"
export TPTP_SECS="${TPTP_SECS:-20}"
H=${RUN_ONE:-$(cd "$(dirname "$0")" && pwd)/run_one.sh}
for prog in prover9 mace4; do "$H" "$prog" "$1"; done
