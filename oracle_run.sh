#!/bin/bash
# One TPTP problem, both provers, against a given build.  Emits the TSV that
# cap2_one.sh defines; the verdict column carries UNSOUND when a prover
# contradicts the problem's SZS status.
export BIN_DIR="${BIN_DIR:-$(cd "$(dirname "$0")/../Prover9Mace4/bin" 2>/dev/null && pwd)}"
export TPTP_SECS="${TPTP_SECS:-20}"
H=${RUN_ONE:-$(cd "$(dirname "$0")" && pwd)/run_one.sh}
for prog in prover9 mace4; do "$H" "$prog" "$1"; done
