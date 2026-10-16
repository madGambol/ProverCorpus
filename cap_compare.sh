#!/bin/bash

#  Copyright (C) 2026 Chris Arena, 2026-10-16.
#  Written in collaboration with Claude Opus 5 (Anthropic).
#
#  This file is part of the Prover9/Mace4 regression corpus, the test
#  material for the Prover9Mace4 tree.  It is not part of William
#  McCune's LADR-2009-11A release; see LICENSING.md for what here is
#  his and redistributed unmodified.
#
#  This corpus is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License, version 2 --
#  the licence of the programs it tests, which say "version 2" with no
#  later-version clause.
#
#  It is distributed in the hope that it will be useful, but WITHOUT
#  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
#  or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
#  License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this corpus, in COPYING; if not, write to the Free
#  Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
#  MA 02110-1301 USA.
#
# cap_compare.sh BASELINE.tsv CURRENT.tsv -- the differential scoreboard.
#
# oracle_scoreboard.sh gives an absolute figure for one build.  This gives the
# comparison: the same categories side by side, and -- the part that actually
# answers "was the work worth it" -- which PROBLEMS changed hands.  A net
# figure can hide equal numbers of gains and losses, and the losses here are
# expected and real: M9, M10 and M12 make Mace4 honour max_megs where it used
# to exceed it, so a problem the baseline answered by overrunning its ceiling
# is now refused.  That trade-off has to be visible, not averaged away.
#
# Soundness is reported per build, because the baseline predates every fix and
# a false proof there that is absent here is the strongest claim available.
set -u
A=${1:?need the baseline tsv}
B=${2:?need the current tsv}
for f in "$A" "$B"; do [ -r "$f" ] || { echo "cannot read $f" >&2; exit 2; }; done

echo "=== runs recorded ==="
printf '  baseline %6d    current %6d\n' "$(wc -l < "$A")" "$(wc -l < "$B")"

echo
echo "=== verdict mix, every run ==="
printf '  %-16s %9s %9s %9s\n' VERDICT baseline current delta
join -a1 -a2 -e 0 -o 0,1.2,2.2 \
  <(awk -F'\t' '{print $7}' "$A" | sort | uniq -c | awk '{print $2"\t"$1}' | sort) \
  <(awk -F'\t' '{print $7}' "$B" | sort | uniq -c | awk '{print $2"\t"$1}' | sort) \
  2>/dev/null | while read -r v na nb; do
    printf '  %-16s %9s %9s %+9d\n' "$v" "$na" "$nb" "$((nb - na))"
  done

echo
echo "=== definite answers, first-order problems with a usable SZS status ==="
for prog in prover9 mace4; do
  for side in A B; do
    f=$A; [ "$side" = B ] && f=$B
    awk -F'\t' -v prog="$prog" '
      $1==prog && ($3=="CNF"||$3=="FOF") &&
      ($4=="Satisfiable"||$4=="CounterSatisfiable"||$4=="Theorem"||$4=="Unsatisfiable"||$4=="ContradictoryAxioms") {
        tot++
        if ($7=="PROVED"||$7=="MODEL"||$7=="EXHAUSTED") win++
      }
      END { printf "%d %d\n", win+0, tot+0 }' "$f"
  done | {
    read -r wa ta; read -r wb tb
    printf '  %-8s baseline %5d/%-5d (%5.1f%%)   current %5d/%-5d (%5.1f%%)   %+d\n' \
      "$prog" "$wa" "$ta" "$([ "$ta" -gt 0 ] && echo "scale=1;100*$wa/$ta" | bc || echo 0)" \
      "$wb" "$tb" "$([ "$tb" -gt 0 ] && echo "scale=1;100*$wb/$tb" | bc || echo 0)" "$((wb - wa))"
  }
done

echo
echo "=== which problems changed hands (the net figure can hide this) ==="
answered() {  # answered <file> -> "prog<TAB>path" for each definite answer
  awk -F'\t' '$7=="PROVED"||$7=="MODEL"||$7=="EXHAUSTED" {print $1"\t"$NF}' "$1" | sort -u
}
answered "$A" > /tmp/.cap_a.$$; answered "$B" > /tmp/.cap_b.$$
trap 'rm -f /tmp/.cap_a.$$ /tmp/.cap_b.$$' 0
printf '  gained by current (baseline could not): %s\n' "$(comm -13 /tmp/.cap_a.$$ /tmp/.cap_b.$$ | wc -l)"
printf '  lost by current  (baseline could):     %s\n' "$(comm -23 /tmp/.cap_a.$$ /tmp/.cap_b.$$ | wc -l)"
printf '  answered by both:                      %s\n' "$(comm -12 /tmp/.cap_a.$$ /tmp/.cap_b.$$ | wc -l)"
echo
echo "  --- gains, by how the baseline failed instead ---"
comm -13 /tmp/.cap_a.$$ /tmp/.cap_b.$$ | while IFS=$'\t' read -r prog path; do
  awk -F'\t' -v p="$prog" -v q="$path" '$1==p && $NF==q {print $7}' "$A"
done | sort | uniq -c | sort -rn | sed 's/^/    /'
echo "  --- losses, by what the current build does instead ---"
comm -23 /tmp/.cap_a.$$ /tmp/.cap_b.$$ | while IFS=$'\t' read -r prog path; do
  awk -F'\t' -v p="$prog" -v q="$path" '$1==p && $NF==q {print $7}' "$B"
done | sort | uniq -c | sort -rn | sed 's/^/    /'

echo
echo "=== SOUNDNESS, per build ==="
for side in "baseline $A" "current $B"; do
  set -- $side
  n=$(grep -ac UNSOUND "$2" || true); n=${n:-0}
  printf '  %-9s UNSOUND %s\n' "$1" "$n"
  [ "$n" -gt 0 ] && grep -a UNSOUND "$2" | awk -F'\t' '{print "      "$1" "$4" "$7" "$NF}' | head -n 20
done

echo
echo "=== crash and fatal rate, which is a capability question too ==="
for side in "baseline $A" "current $B"; do
  set -- $side
  printf '  %-9s SIGSEGV %-5s FATAL %-5s of %s runs\n' "$1" \
    "$(awk -F'\t' '$7=="SIGSEGV"{c++}END{print c+0}' "$2")" \
    "$(awk -F'\t' '$7=="FATAL"{c++}END{print c+0}' "$2")" \
    "$(wc -l < "$2")"
done
