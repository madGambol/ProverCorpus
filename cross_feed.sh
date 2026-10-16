#!/bin/bash
#
# cross_feed.sh BASELINE.tsv CURRENT.tsv  -- attribute a capability change to
#                                           the INPUT or to the PROVER.
#
# WHY.  When two builds differ in both the translator and the prover, a
# problem that one answers and the other does not has two possible causes and
# the A/B cannot tell them apart.  A corrected translation is a DIFFERENT
# problem, usually a harder one, so losing it is not a regression -- the old
# build was answering a formula the input never asked for.  A slower prover on
# the same formula is a regression.
#
# So run all four combinations of {baseline, current} translation x
# {baseline, current} prover on each problem that changed hands:
#
#   neither prover answers the CURRENT translation   -> the input changed
#   the baseline prover answers it and ours does not -> the prover regressed
#   the current pipeline answers it this time        -> it was noise
#
# Applied to the 205 prover9 losses in the first capability A/B of this tree,
# this said 186 input, 13 prover, 6 noise -- and the 13 bisected to one commit
# (R1 in ../Prover9Mace4/FIXES.md).  Without the split, the headline was a
# 134-answer regression; with it, 13.
#
# Needs the two translations dumped per problem as $D/<mangled path>.{A,B};
# dump_translations.sh does that.
set -u
A=${1:?need the baseline tsv}
B=${2:?need the current tsv}
BIN_A=${BIN_A:?set BIN_A}
BIN_B=${BIN_B:?set BIN_B}
D=${D:?set D, the directory of dumped translations}
SECS=${SECS:-10}
MEM_KB=${MEM_KB:-4000000}
JOBS=${JOBS:-40}
PROG=${PROG:-prover9}
HERE=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' 0 1 2 3 15

win='$7=="PROVED"||$7=="MODEL"||$7=="EXHAUSTED"'
awk -F'\t' "\$1==\"$PROG\" && $win {print \$NF}" "$A" | sort -u > $W/a
awk -F'\t' "\$1==\"$PROG\" && $win {print \$NF}" "$B" | sort -u > $W/b
comm -23 $W/a $W/b > $W/lost
n=$(wc -l < $W/lost)
echo "$n $PROG problems lost; 4 combinations each"
[ "$n" -eq 0 ] && exit 0

: > $W/out
awk '{printf "%s\tA\tA\n%s\tA\tB\n%s\tB\tA\n%s\tB\tB\n",$0,$0,$0,$0}' $W/lost | shuf > $W/work
cd "${TPTP_DIR:-$HOME/Projects/TPTP/TPTP-v9.3.1}" || exit 2
xargs -a $W/work -d'\n' -P "$JOBS" -I{} \
  env BIN_A="$BIN_A" BIN_B="$BIN_B" D="$D" SECS="$SECS" MEM_KB="$MEM_KB" \
      OUT=$W/out "$HERE/cross_feed_one.sh" '{}'

awk -F'\t' 'function w(v){return (v=="PROVED"||v=="EXHAUSTED")}
  { v[$1 $2 $3]=$4; p[$1]=1 }
  END {
    for (k in p) {
      ba=w(v[k "BA"]); bb=w(v[k "BB"])
      if (!bb && !ba)   c="INPUT"
      else if (!bb)     c="PROVER"
      else              c="NOISE"
      printf "%s\t%s\t%s/%s/%s/%s\n", c, k, v[k "AA"], v[k "AB"], v[k "BA"], v[k "BB"]
      t[c]++
    }
    printf "\nINPUT %d (the corrected translation defeats both provers)\n", t["INPUT"]+0
    printf "PROVER %d (the baseline prover answers the corrected input, ours does not)\n", t["PROVER"]+0
    printf "NOISE %d (the current pipeline answered it this time)\n", t["NOISE"]+0
  }' $W/out | sort
