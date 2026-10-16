#!/bin/bash
# Re-run ONE prover on ONE problem at a longer limit.  Input is "prog<TAB>path",
# so only the prover that actually timed out is re-run -- a problem already
# answered cannot change its answer by being given more time.
export BIN_DIR="${BIN_DIR:-/home/chris/Projects/Prover9Mace4/bin}"
export TPTP_SECS="${TPTP_SECS:-300}"
H=/home/chris/Projects/TPTP/results-prover9mace4/cap2_one.sh
prog="${1%%	*}"; p="${1#*	}"
exec "$H" "$prog" "$p"
