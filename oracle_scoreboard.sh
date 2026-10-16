#!/bin/bash

#  Copyright (C) 2026 Chris Arena and Claude Opus 5, 2026-10-16.
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
# Merge a base sweep with a longer-limit re-run and print the scoreboard.
#
#   oracle_scoreboard.sh BASE.tsv [RETRY.tsv]
#
# The re-run only covers runs that timed out in the base sweep, so the merged
# verdict for a (prover, problem) pair is the re-run's where one exists and the
# base's otherwise.  A problem already answered cannot change its answer by
# being given more time, which is why the re-run skips those.
#
# Inputs may be gzipped.  They are decompressed to temporary files rather than
# piped, because the merge below distinguishes the two inputs by FILENAME and
# process substitution would break that.  Reading a .gz directly is what this
# script used to do: awk scored the gzip bytes as text, reported "runs
# scored: 594" from binary noise, and then died dividing by a zero total.
set -u
base="${1:?usage: oracle_scoreboard.sh BASE.tsv[.gz] [RETRY.tsv[.gz] ...]}"
shift

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' 0 1 2 3 15

plain() {          # plain <path> -> echoes a path to uncompressed text
  case $1 in
    *.gz) out=$tmp/$(basename "${1%.gz}")
          gzip -dc -- "$1" > "$out" || { echo "cannot decompress $1" >&2; exit 2; }
          printf '%s' "$out" ;;
    *)    printf '%s' "$1" ;;
  esac
}

[ -r "$base" ] || { echo "cannot read $base" >&2; exit 2; }
base=$(plain "$base")

# Any number of re-runs.  There is one per prover now -- Prover9's 300 s pass
# and Mace4's -- and their keys are disjoint because the prover is part of the
# key, so the order among them does not matter.  Each still has to win over
# the base.
retries=""
for r in "$@"; do
  [ -r "$r" ] || { echo "cannot read $r" >&2; exit 2; }
  retries="$retries${retries:+,}$(plain "$r")"
done

awk -F'\t' -v retries="$retries" '
  BEGIN { n = split(retries, r, ","); for (i = 1; i <= n; i++) isretry[r[i]] = 1 }
  function key(p, f) { return p SUBSEP f }
  # the re-runs are read first, so they win over the base
  FILENAME in isretry { v[key($1,$10)] = $7; d[key($1,$10)] = $3; next }
  { k = key($1,$10); if (!(k in v)) { v[k] = $7; d[k] = $3 } }
  END {
    for (k in v) {
      split(k, a, SUBSEP); prog = a[1]; form = d[k]; verd = v[k]
      if (verd == "UNSOUND") { uns++; unsl = unsl "\n    " prog " " a[2] }
      if (form != "CNF" && form != "FOF") continue
      if (verd == "no-oracle") { no[prog]++; continue }
      tot[prog]++
      if (verd == "PROVED" || verd == "MODEL" || verd == "EXHAUSTED") {
        win[prog]++; anyw[a[2]] = 1
        if (verd == "PROVED") pr[prog]++
        else if (verd == "MODEL") mo[prog]++
        else ex[prog]++
      }
      else if (verd == "MAX_SECONDS" || verd == "CPU_KILL") to[prog]++
      else if (verd == "translate-fail") tf[prog]++
      else if (verd == "FATAL") fa[prog]++
      anyp[a[2]] = 1
    }
    printf "\n=== SOUNDNESS ===\n"
    printf "  runs scored: %d\n", length(v)
    if (tot["prover9"] + tot["mace4"] == 0) {
      printf "\n  NOTHING SCORABLE: %d rows read, but no CNF/FOF row with a\n", length(v)
      printf "  usable status.  Wrong columns, wrong file, or binary input?\n"
      exit 2
    }
    if (uns) printf "  UNSOUND:     %d  <- a prover contradicted the library:%s\n", uns, unsl
    else     printf "  UNSOUND:     0\n"
    printf "\n=== CAPABILITY, first-order problems (CNF + FOF) ===\n\n"
    printf "  %-30s %9s %9s\n", "", "prover9", "mace4"
    printf "  %-30s %9d %9d\n", "with a usable SZS status", tot["prover9"], tot["mace4"]
    printf "  %-30s %9d %9d\n", "proof found",            pr["prover9"]+0, pr["mace4"]+0
    printf "  %-30s %9d %9d\n", "model found",            mo["prover9"]+0, mo["mace4"]+0
    printf "  %-30s %9d %9d\n", "exhausted",              ex["prover9"]+0, ex["mace4"]+0
    printf "  %-30s %9d %9d\n", "= DEFINITE ANSWERS",     win["prover9"]+0, win["mace4"]+0
    printf "  %-30s %8.1f%% %8.1f%%\n", "= share",
      tot["prover9"] ? 100*(win["prover9"]+0)/tot["prover9"] : 0,
      tot["mace4"]   ? 100*(win["mace4"]+0)/tot["mace4"]   : 0
    printf "  %-30s %9d %9d\n", "out of time",            to["prover9"]+0, to["mace4"]+0
    printf "  %-30s %9d %9d\n", "translate-fail",         tf["prover9"]+0, tf["mace4"]+0
    printf "  %-30s %9d %9d\n", "fatal",                  fa["prover9"]+0, fa["mace4"]+0
    printf "\n  at least one prover answered: %d of %d = %.1f%%\n",
      length(anyw), length(anyp),
      length(anyp) ? 100*length(anyw)/length(anyp) : 0
  }
' $(printf '%s' "$retries" | tr ',' ' ') "$base"
