#!/bin/bash
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
export BIN_DIR="${BIN_DIR:-/home/chris/Projects/Prover9Mace4/bin}"
export TPTP_SECS="${TPTP_SECS:-300}"
MEM_KB="${MEM_KB:-12000000}"      # 12 GB: calibrated so legitimate runs do not fail
WALL="${WALL:-900}"              # and no slot held longer than 15 min
H=/home/chris/Projects/TPTP/results-prover9mace4/cap2_one.sh
prog="${1%%	*}"; p="${1#*	}"
ulimit -v "$MEM_KB"
exec timeout "$WALL" "$H" "$prog" "$p"
