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
# Circuit breaker.  Kills the sweep if free memory or swap heads toward the
# state that cost a reboot, so a sweep can never again take the machine away
# from its owner.  Belt and braces: the per-run ulimit -v should make this
# unreachable, but "should" is what the last attempt relied on.
MIN_AVAIL_GB="${MIN_AVAIL_GB:-40}"
MIN_SWAP_FREE_PCT="${MIN_SWAP_FREE_PCT:-50}"
while pgrep -f oracle_retry_capped.sh >/dev/null; do
  avail=$(awk '/^MemAvailable:/ {print int($2/1048576)}' /proc/meminfo)
  st=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
  sf=$(awk '/^SwapFree:/  {print $2}' /proc/meminfo)
  pct=100; [ "$st" -gt 0 ] && pct=$(( 100 * sf / st ))
  if [ "$avail" -lt "$MIN_AVAIL_GB" ] || [ "$pct" -lt "$MIN_SWAP_FREE_PCT" ]; then
    echo "GUARD TRIPPED: MemAvailable ${avail}GB, swap ${pct}% free -- killing the sweep"
    pkill -f 'xargs -a.*retry300_mace4' 2>/dev/null
    pkill -f oracle_retry_capped.sh 2>/dev/null
    pkill -x mace4 2>/dev/null; pkill -x prover9 2>/dev/null
    exit 1
  fi
  sleep 15
done
echo "guard: sweep finished with memory healthy throughout"
