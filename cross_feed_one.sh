#!/bin/bash
# $1 = "problem<TAB>xlate(A|B)<TAB>prover(A|B)"  -> problem xlate prover verdict
set -u
IFS=$'\t' read -r p x pr <<< "$1"
k=$(printf '%s' "$p" | tr / _)
in=$D/$k.$x
case $pr in A) bin=$BIN_A ;; B) bin=$BIN_B ;; esac
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
printf 'assign(max_seconds,%s).\nassign(max_megs,2000).\n' "$SECS" > $t/opt
out=$( ulimit -v "$MEM_KB"; ( ulimit -t $((SECS+15)); exec timeout $((SECS*8+120)) "$bin/prover9" -f $t/opt "$in" ) 2>&1 )
rc=$?
echo "$out" | grep -qE 'Exiting with [1-9][0-9]* proof' && rc=0
case $rc in 0) v=PROVED;; 2) v=EXHAUSTED;; 3) v=MAX_MEGS;; 4) v=MAX_SECONDS;; 1) v=FATAL;;
  102) v=SIGSEGV;; 124) v=WALL_KILL;; 137|152) v=CPU_KILL;; *) v=OTHER_$rc;; esac
printf '%s\t%s\t%s\t%s\n' "$p" "$x" "$pr" "$v" >> "$OUT"
