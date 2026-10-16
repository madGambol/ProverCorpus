#!/bin/bash
# One TPTP problem, both provers, against a given build.  Emits the TSV that
# cap2_one.sh defines; the verdict column carries UNSOUND when a prover
# contradicts the problem's SZS status.
export BIN_DIR="${BIN_DIR:-/home/chris/Projects/Prover9Mace4/bin}"
export TPTP_SECS="${TPTP_SECS:-20}"
H=/home/chris/Projects/TPTP/results-prover9mace4/cap2_one.sh
for prog in prover9 mace4; do "$H" "$prog" "$1"; done
