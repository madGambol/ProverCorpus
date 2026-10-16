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

import re, sys
# LADR prints every quantifier explicitly and the file declares
# set(prolog_style_variables), so a capitalised token is a variable and a
# variable never bound by all/exists in its own formula is FREE.  Every TPTP
# fof/cnf formula is closed, so a free variable in the output is a translation
# defect -- no logic required to see it.
QUANT = re.compile(r'\b(?:all|exists)\s+([A-Z][A-Za-z0-9_]*)')
VAR   = re.compile(r'(?<![A-Za-z0-9_$])([A-Z][A-Za-z0-9_]*)(?![A-Za-z0-9_])')
bad = 0; tot = 0
for path in sys.argv[1:]:
    try: text = open(path, errors='replace').read()
    except OSError: continue
    for line in text.splitlines():
        if '#' not in line and not line.rstrip().endswith('.'): continue
        if not re.search(r'\b(all|exists)\b|\(', line): continue
        if line.lstrip().startswith(('set(', 'assign(', 'formulas(', 'clauses(', 'end_of_list', '%')): continue
        tot += 1
        bound = set(QUANT.findall(line))
        used  = set(VAR.findall(line))
        if used - bound: bad += 1
print(f"{bad}\t{tot}")
