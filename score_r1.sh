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
# score_r1.sh -- score the post-R1 capability A/B, and set it against the
# pre-R1 one so the recovery is visible rather than asserted.
set -u
R=$HOME/Projects/prover9-corpus/results
P=$R/cap-r1-pristine.tsv
C=$R/cap-r1-current.tsv
P0=$R/cap-10s-pristine.tsv.gz
C0=$R/cap-10s-current.tsv.gz
W=$(mktemp -d); trap 'rm -rf "$W"' 0

zcat "$P0" > $W/p0; zcat "$C0" > $W/c0

echo "=== runs recorded ==="
printf '  pre-R1:  pristine %6d  current %6d\n' "$(wc -l < $W/p0)" "$(wc -l < $W/c0)"
printf '  post-R1: pristine %6d  current %6d\n' "$(wc -l < "$P")" "$(wc -l < "$C")"

echo
echo "=== verdict mix, every run ==="
printf '  %-15s %9s %9s %9s %9s\n' VERDICT pristine 'cur pre-R1' 'cur post-R1' 'R1 delta'
cut -f7 $W/p0 "$P" "$C" $W/c0 | sort -u | while read -r v; do
  [ -z "$v" ] && continue
  a=$(awk -F'\t' -v v="$v" '$7==v' $W/p0 | wc -l)
  b=$(awk -F'\t' -v v="$v" '$7==v' $W/c0 | wc -l)
  c=$(awk -F'\t' -v v="$v" '$7==v' "$C"  | wc -l)
  printf '  %-15s %9d %9d %9d %+9d\n' "$v" "$a" "$b" "$c" "$((c - b))"
done

win='$7=="PROVED"||$7=="MODEL"||$7=="EXHAUSTED"'
echo
echo "=== sound definite answers (first-order, usable SZS status) ==="
printf '  %-14s %9s %9s %9s\n' BUILD prover9 mace4 total
for lbl in pristine cur-pre-R1 cur-post-R1; do
  case $lbl in pristine) f=$W/p0;; cur-pre-R1) f=$W/c0;; *) f=$C;; esac
  p9=$(awk -F'\t' "\$1==\"prover9\" && ($win) {print \$NF}" "$f" | sort -u | wc -l)
  m4=$(awk -F'\t' "\$1==\"mace4\" && ($win) {print \$NF}" "$f" | sort -u | wc -l)
  printf '  %-14s %9d %9d %9d\n' "$lbl" "$p9" "$m4" "$((p9 + m4))"
done

echo
echo "=== WRONG ANSWERS (UNSOUND) ==="
for lbl in pristine cur-pre-R1 cur-post-R1; do
  case $lbl in pristine) f=$W/p0;; cur-pre-R1) f=$W/c0;; *) f=$C;; esac
  n=$(awk -F'\t' '$7=="UNSOUND"' "$f" | wc -l)
  printf '  %-14s %4d\n' "$lbl" "$n"
done

echo
echo "=== changed hands vs pristine, post-R1 ==="
awk -F'\t' "$win {print \$1\"\t\"\$NF}" "$P" | sort -u > $W/wp
awk -F'\t' "$win {print \$1\"\t\"\$NF}" "$C" | sort -u > $W/wc
awk -F'\t' "$win {print \$1\"\t\"\$NF}" $W/c0 | sort -u > $W/wc0
printf '  pre-R1 : %4d gained, %4d lost\n' \
  "$(comm -13 <(awk -F'\t' "$win {print \$1\"\t\"\$NF}" $W/p0 | sort -u) $W/wc0 | wc -l)" \
  "$(comm -23 <(awk -F'\t' "$win {print \$1\"\t\"\$NF}" $W/p0 | sort -u) $W/wc0 | wc -l)"
printf '  post-R1: %4d gained, %4d lost\n' \
  "$(comm -13 $W/wp $W/wc | wc -l)" "$(comm -23 $W/wp $W/wc | wc -l)"

echo
echo "=== R1's twelve ==="
for p in $(cat $HOME/Projects/prover9-corpus/cap_gate_problems.txt 2>/dev/null | head -0); do :; done
printf '  %-30s %-12s %-12s\n' PROBLEM 'pre-R1' 'post-R1'
for p in Problems/SWV/SWV558-1.010.p Problems/SWV/SWV543-1.010.p Problems/SWV/SWV547-1.010.p \
         Problems/SWB/SWB006-10.p Problems/SWB/SWB009-10.p Problems/SWB/SWB017-10.p \
         Problems/SWB/SWB022-10.p Problems/SWB/SWB025-10.p Problems/SWB/SWB032-10.p \
         Problems/SWX/SWX194-1.p Problems/SYN/SYN170-10.p Problems/SYN/SYN193-10.p; do
  b=$(awk -F'\t' -v p="$p" '$1=="prover9" && $NF==p {print $7}' $W/c0 | head -1)
  c=$(awk -F'\t' -v p="$p" '$1=="prover9" && $NF==p {print $7}' "$C"  | head -1)
  printf '  %-30s %-12s %-12s\n' "$(basename $p)" "${b:--}" "${c:--}"
done

echo
echo "=== losses still standing, post-R1: what current does instead ==="
comm -23 $W/wp $W/wc | while IFS=$'\t' read -r prog path; do
  v=$(awk -F'\t' -v g="$prog" -v p="$path" '$1==g && $NF==p {print $7}' "$C" | head -1)
  a=$(awk -F'\t' -v g="$prog" -v p="$path" '$1==g && $NF==p {print $7}' "$P" | head -1)
  echo "$prog $a -> $v"
done | sort | uniq -c | sort -rn | head -12
