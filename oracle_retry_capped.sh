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
# One prover, one problem, at a longer CPU limit, with a HARD memory cap.
#
# WHY THE HARD CAP.  LADR's max_megs is enforced by counting palloc's own
# mallocs, and Mace4 allocates its model tables outside palloc -- a run with
# assign(max_megs,2000) was measured at 18.4 GB RSS, nine times its stated
# cap.  At 300 s Mace4 reaches domain sizes where that runs away.  Eighty such
# runs exhausted 7 GB of swap and made the machine unable to fork a login
# shell, which cost a reboot.  So the limit is ulimit -v, which the kernel
# enforces regardless of what LADR thinks it is using: malloc fails, LADR
# reports being out of memory, and the run ends cleanly instead of starving.
#
# Input is "prog<TAB>path".
export BIN_DIR="${BIN_DIR:-$(cd "$(dirname "$0")/../Prover9Mace4/bin" 2>/dev/null && pwd)}"
export TPTP_SECS="${TPTP_SECS:-300}"
MEM_KB="${MEM_KB:-12000000}"      # 12 GB: calibrated so legitimate runs do not fail
WALL="${WALL:-900}"              # and no slot held longer than 15 min
H=${RUN_ONE:-$(cd "$(dirname "$0")" && pwd)/run_one.sh}
prog="${1%%	*}"; p="${1#*	}"
ulimit -v "$MEM_KB"
exec timeout "$WALL" "$H" "$prog" "$p"
