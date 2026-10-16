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
