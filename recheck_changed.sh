#!/bin/bash
#
# recheck_changed.sh BASELINE.tsv CURRENT.tsv [REPS] [JOBS]
#
# Re-run only the (prover, problem) pairs that changed hands between two
# builds, several times each, interleaved, and report whether each flip is
# STABLE or NOISE.
#
# WHY.  A one-shot A/B at a fixed time budget cannot distinguish "this build
# is slower on this problem" from "this problem's solve time straddles the
# limit".  Measured on this machine, the same binary on the same input varied
# 20.48 / 18.95 / 10.87 / 10.14 CPU seconds across four reps as load changed
# -- a 2x spread with no code difference.  At a 10-second budget a problem
# near the boundary will flip at random, and a handful of such flips is
# exactly what a capability A/B reports as a regression.
#
# So: each pair is run REPS times per build, the runs are interleaved so both
# builds see the same contention, and a flip only counts if it reproduces
# every time.
set -u
A=${1:?need the baseline tsv}
B=${2:?need the current tsv}
REPS=${3:-5}
JOBS=${4:-32}
BIN_A=${BIN_A:?set BIN_A}
BIN_B=${BIN_B:?set BIN_B}
SECS=${SECS:-10}
MEM_KB=${MEM_KB:-4000000}
HERE=$(cd "$(dirname "$0")" && pwd)
ONE=/home/chris/Projects/TPTP/results-prover9mace4/cap2_one.sh
TPTP=${TPTP_DIR:-$HOME/Projects/TPTP/TPTP-v9.3.1}
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' 0 1 2 3 15

win='$7=="PROVED"||$7=="MODEL"||$7=="EXHAUSTED"'
awk -F'\t' "$win {print \$1\"\t\"\$NF}" "$A" | sort -u > $W/a
awk -F'\t' "$win {print \$1\"\t\"\$NF}" "$B" | sort -u > $W/b
comm -13 $W/a $W/b | sed 's/^/gained\t/' >  $W/changed
comm -23 $W/a $W/b | sed 's/^/lost\t/'   >> $W/changed
n=$(wc -l < $W/changed)
echo "$n pairs changed hands; $REPS reps per build, interleaved"
[ "$n" -eq 0 ] && exit 0

cat > $W/one.sh <<'EOF'
#!/bin/bash
set -u
IFS=$'\t' read -r dir side prog p rep <<< "$1"
case $side in A) bin=$BIN_A ;; B) bin=$BIN_B ;; esac
row=$( ulimit -v "$MEM_KB"; BIN_DIR="$bin" TPTP_SECS="$SECS" timeout $((SECS*8+120)) "$H" "$prog" "$p" 2>/dev/null )
v=$(printf '%s' "$row" | awk -F'\t' '{print $7}')
printf '%s\t%s\t%s\t%s\t%s\n' "$dir" "$side" "$prog" "$p" "${v:-NOROW}" >> "$OUT"
EOF
chmod +x $W/one.sh
: > $W/out
awk -v r="$REPS" -F'\t' '{ for (i=1;i<=r;i++) { printf "%s\tA\t%s\t%s\t%d\n", $1,$2,$3,i; printf "%s\tB\t%s\t%s\t%d\n", $1,$2,$3,i } }' \
  $W/changed | shuf > $W/work

cd "$TPTP" || exit 2
BIN_A="$BIN_A" BIN_B="$BIN_B" SECS="$SECS" MEM_KB="$MEM_KB" H="$ONE" OUT="$W/out" \
  xargs -a $W/work -d'\n' -P "$JOBS" -I{} env BIN_A="$BIN_A" BIN_B="$BIN_B" SECS="$SECS" \
     MEM_KB="$MEM_KB" H="$ONE" OUT="$W/out" $W/one.sh '{}'

echo
printf '  %-7s %-8s %-34s %-22s %-22s %s\n' DIR PROG PROBLEM "baseline wins/reps" "current wins/reps" VERDICT
awk -F'\t' -v reps="$REPS" '
  function isw(v) { return (v=="PROVED"||v=="MODEL"||v=="EXHAUSTED") }
  { k=$1 SUBSEP $3 SUBSEP $4; if ($2=="A") { na[k]++; if (isw($5)) wa[k]++ } else { nb[k]++; if (isw($5)) wb[k]++ } }
  END {
    for (k in na) {
      split(k, f, SUBSEP)
      a=wa[k]+0; b=wb[k]+0
      # a flip is stable only if it reproduces in every rep on both sides
      if ((a==na[k] && b==0) || (a==0 && b==nb[k])) verdict="STABLE"
      else verdict="NOISE"
      printf "  %-7s %-8s %-34s %-22s %-22s %s\n", f[1], f[2], f[3], a "/" na[k], b "/" nb[k], verdict
      tot[verdict]++
    }
    printf "\n  STABLE %d   NOISE %d\n", tot["STABLE"]+0, tot["NOISE"]+0
  }' $W/out | sort -k6,6 -k1,1
