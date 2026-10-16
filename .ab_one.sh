#!/bin/bash
set -u
line=$1
side=${line%%	*}; rest=${line#*	}
prog=${rest%%	*}; p=${rest#*	}
case $side in A) bin=$BIN_A; out=$OUT_A ;; B) bin=$BIN_B; out=$OUT_B ;; *) exit 0 ;; esac
row=$( ulimit -v "$MEM_KB"; BIN_DIR="$bin" TPTP_SECS="$SECS" timeout "$WALL" "$H" "$prog" "$p" 2>/dev/null )
[ -n "$row" ] && printf '%s\n' "$row" >> "$out"
