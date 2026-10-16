#!/bin/bash
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
