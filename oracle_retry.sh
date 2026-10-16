#!/bin/bash
# Re-run ONE prover on ONE problem at a longer limit.  Input is "prog<TAB>path",
# so only the prover that actually timed out is re-run -- a problem already
# answered cannot change its answer by being given more time.
export BIN_DIR="${BIN_DIR:-$(cd "$(dirname "$0")/../Prover9Mace4/bin" 2>/dev/null && pwd)}"
export TPTP_SECS="${TPTP_SECS:-300}"
H=${RUN_ONE:-$(cd "$(dirname "$0")" && pwd)/run_one.sh}
prog="${1%%	*}"; p="${1#*	}"
exec "$H" "$prog" "$p"
