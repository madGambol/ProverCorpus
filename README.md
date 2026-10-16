# Prover9 / Mace4 regression corpus

The input corpus the `Prover9Mace4` gates run against. It lived in a session
scratchpad until 2026-10-14, which meant the two most valuable gates could not
be re-run once the session ended; it is here so that they can.

## Start here

- **`LICENSING.md`** — terms, and what is bundled versus what you must fetch.
- **`results/`** — every scored sweep, gzipped, each with its conditions
  recorded in the commit that added it.
- The headline numbers these results produce are written up in the parent
  tree's `RESULTS.md`; this repo is the evidence behind them.

**Two things are not here and are needed to reproduce anything:** the TPTP
problem library (v9.3.1, from <https://www.tptp.org> — `results/` holds problem
*paths*, not problems) and a built `Prover9Mace4` tree. The scripts look for
`../Prover9Mace4/bin` and take `BIN_DIR`/`TPTP_DIR` to override.

```sh
git clone https://mirror.invalid/Prover9Mace4.git
git clone https://mirror.invalid/Prover9Corpus.git prover9-corpus
(cd Prover9Mace4 && make all)
```

The examples below spell the corpus directory `~/Projects/prover9-corpus`,
which is why the clone above is named that; the published repository is
`Prover9Corpus`. Nothing but those examples depends on the name — the scripts
resolve the tree under test as `../Prover9Mace4/bin`, whatever this directory
is called.

## What is here

| path | what | where it came from |
| --- | --- | --- |
| `prover9-manual-2009-11A/` | the worked examples from McCune's Prover9 manual | `prover9-manual-2009-11A.tar.gz`, kept alongside |
| `web/2009-11A/` | the example sets published with the 2009-11A release | the LADR/Prover9 web distribution |
| `files.txt` | 168 problem paths, one per line | the tier3 memory sweeps |
| `comparable.txt` | 174 `prog\|path` lines | the behaviour A/B |

Both lists hold absolute paths into this directory. If it moves, rewrite them:

```sh
sed -i "s|/old/path|$PWD|" files.txt comparable.txt
```

## The tools

| script | what it does |
| --- | --- |
| `run_one.sh` | runs ONE problem under one prover and emits one TSV row: `prog dom form status rating nforms verdict ms rc problem`. Everything else drives this. Limits are CPU time, not wall clock. |
| `oracle_run.sh`, `oracle_sweep_resume.sh`, `oracle_retry_capped.sh` | the absolute capability sweeps, resumable |
| `oracle_scoreboard.sh` | scores a sweep: soundness first, then capability |
| `baseline_ab.sh` | the capability A/B against a second build, both builds **interleaved** in one shuffled queue |
| `cap_compare.sh`, `score_r1.sh` | score an A/B, and set two A/B runs against each other |
| `cross_feed.sh` | attribute a capability change to the INPUT or to the PROVER, by running all four combinations of {old,new} translation x {old,new} prover |
| `freevars.py` | the soundness oracle that needs no reasoning: every TPTP `fof` formula is closed, so a free variable in the translated output is wrong on its face |
| `recheck_changed.sh` | re-run only the pairs that changed hands, several times each, and report STABLE or NOISE |
| `cap_gate.sh` | the fast capability gate: the 294 problems that have ever changed hands |
| `verify_models.sh` | re-derive every Mace4 model and check every input clause against it |
| `dump_translations.sh` | per-problem translations for `cross_feed.sh` and `freevars.py` |

## How the two lists differ, and why it matters

`files.txt` is every problem. `comparable.txt` is the subset of
*prover/problem pairs* that both **terminate on their own** and **do not stop
on a clock** — a proof, a model, an exhausted search, or a memory ceiling.

That distinction is the whole basis of the A/B gate. A run killed at a resource
limit is cut mid-output and a run that exits `max_seconds`/`max_sec_no` stops
wherever the clock landed, so comparing either kind produces differences that
are the measurement rather than the code. Including them once cost this project
a long investigation into prover nondeterminism that did not exist.

`comparable.txt` was derived by running each pair and keeping those whose output
ends in an exit banner that is not a timer. To rebuild it after a change to the
provers' own time limits, see the `self_terminating`/`clock_limited` helpers in
`Prover9Mace4/test.src/determinism.sh`, which encode the same rule.

## Running the gates

```sh
cd ~/Projects/Prover9Mace4/test.src

make tier1                                   # ~2 s
make tier2 BASELINE=/path/to/pristine/bin    # ~3 min
make tier3 CORPUS=~/Projects/prover9-corpus/files.txt   # ~15 min, 80 jobs
```

The A/B is not a make target because it needs a second build to compare
against. The shape of it:

```sh
# A/A first -- the noise floor.  An A/B number means nothing without it.
xargs -a comparable.txt -P 60 -I{} ./ab.sh aa "{}"
xargs -a comparable.txt -P 60 -I{} ./ab.sh ab "{}"
```

where `ab.sh` runs the pair under both builds, pipes each through
`Prover9Mace4/test.src/normalize_output.sh`, and prints a line only when they
differ. Expect **A/A = 0**; any A/B difference needs explaining, not averaging.

## The soundness oracle

`oracle_run.sh` runs one TPTP problem through both provers against a given
build and emits the TSV that `run_one.sh` defines. The verdict column
carries **`UNSOUND`** when a prover contradicts the problem's own SZS status:
Prover9 proving a `Satisfiable` or `CounterSatisfiable` problem, or Mace4
finding a model of a `Theorem`, `Unsatisfiable` or `ContradictoryAxioms` one.
For a theorem prover this is the check that matters most, because everything
else only measures how much it can do, not whether what it says is true.

```sh
cd ~/Projects/TPTP/TPTP-v9.3.1          # includes resolve relative to here
BIN_DIR=~/Projects/Prover9Mace4/bin TPTP_SECS=10 \
  xargs -a ~/Projects/prover9-corpus/oracle_sample.txt -P 80 -I{} \
    ~/Projects/prover9-corpus/oracle_run.sh '{}' > oracle.tsv
grep UNSOUND oracle.tsv
```

`oracle_sample.txt` is every third problem (8,996 of 26,990), which is 17,992
runs and about half an hour at 80 jobs. A short CPU budget is the right trade
here: an unsound proof is almost always found quickly, so 10 seconds over three
times as many problems finds more than 30 seconds over a third as many.

### Calibrate the detector before trusting a clean sweep

A detector that cannot fire reports zero violations on a broken prover just as
happily as on a correct one. Before believing a clean result, confirm `UNSOUND`
actually triggers, by giving the oracle a problem whose stated status is a lie:

```sh
mkdir -p /tmp/ctl/Problems/ZZZ
ln -sfn ~/Projects/TPTP/TPTP-v9.3.1/Axioms /tmp/ctl/Axioms   # or include() fails
sed 's/^% Status   : Unsatisfiable/% Status   : Satisfiable/' \
  ~/Projects/TPTP/TPTP-v9.3.1/Problems/GRP/GRP001-1.p \
  > /tmp/ctl/Problems/ZZZ/CTRL001-1.p
cd /tmp/ctl && BIN_DIR=~/Projects/Prover9Mace4/bin ~/Projects/prover9-corpus/oracle_run.sh \
  Problems/ZZZ/CTRL001-1.p
```

GRP001-1 is unsatisfiable and Prover9 proves it in about 110 ms, so relabelling
the header as `Satisfiable` makes that proof a contradiction of the stated
status. Expect `UNSOUND` in the verdict column. The `Axioms` symlink matters:
without it the problem reports `translate-fail` and the control silently proves
nothing, which is how a first attempt at this went.

### Long sweeps: bound the memory, and make the run resumable

A 300-second Mace4 sweep is not the 10-second one with a bigger number. At
10 s no run reaches a domain size where Mace4's allocation behaviour matters;
at 300 s many do, and the first attempt at this **cost a reboot** — 80 jobs
reached 74 GB resident with one process at 18.4 GB, exhausted all 7 GB of
swap, and left the machine unable to fork a login shell.

The cause was two defects in Mace4, now fixed as M9 and M10: the cell table
and the negative-propagation index were each allocated outside `palloc`,
unchecked and unaccounted, and the negprop index grows as
`(domain+1)^arity`. One problem, `NLP229-10`, was asking for **1.4 TB**. Run
these sweeps against a build that has both fixes, or the sweep is measuring
the bug.

Four independent layers, because the first attempt relied on one:

```sh
systemd-run --user --scope -p MemoryMax=160G -p MemorySwapMax=0 ...
```

`MemorySwapMax=0` is not optional. `MemoryMax` alone **silently spills to
swap**, which is the exact mechanism of the lockout. Per-run, `ulimit -t 300`
for CPU and `ulimit -v 12000000` for address space — calibrated, not guessed:
measured on 8 known-FATAL problems, a 4 GB cap turned 8 of 8 into FATAL while
12 GB produced none. And `oracle_guard.sh` outside the cgroup, which kills the
sweep if MemAvailable drops below 40 GB or swap free below 50%.

**But jobs × per-run cap must be consistent with the cgroup budget.** 12 GB
times 64 jobs permits 768 GB against a 160 GB ceiling. When a cgroup reaches
`MemoryMax` the kernel kills a process *inside* it, and the one it picks is
often the scope's own `xargs` — so a 5171-run sweep ended at 1236 rows with
`Failed with result 'oom-kill'` in `journalctl --user`. The machine was fine;
only the run was lost, and only because nothing resumed it.

So drive long sweeps through `oracle_sweep_resume.sh`, which recomputes the
remaining work from the output file on every pass and halves concurrency when
the driver does not survive:

```sh
BIN_DIR=~/Projects/Prover9Mace4/bin TPTP_SECS=300 MEM_KB=12000000 \
  CGROUP_MAX=160G ./oracle_sweep_resume.sh \
    retry300_mace4_ordered.tsv results/oracle-300s-mace4.tsv 48
```

It is safe to interrupt and re-run: the TSV is append-only with one row per
completed run, and a row's first field and last field are exactly the key the
input list is made of.

**Order the list by where the answers are.** Mace4 can only find a model of a
satisfiable problem, so of the 5,171 timed-out runs, 503 (`Satisfiable` 325,
`CounterSatisfiable` 178) can possibly yield one. The other 4,668 are
`Theorem`, `Unsatisfiable` or `ContradictoryAxioms`, where no model exists —
but they are *exactly* where an `UNSOUND` would appear, so they are run, just
second. An earlier uncapped attempt processed in arbitrary order and found 0
models in 221 runs, which looked like a capability result and was really a
sampling artefact.

## Results kept here

`results/oracle-10s.tsv.gz` is the full 17,992-run sweep at 10 s CPU, and
`results/oracle-300s-prover9.tsv.gz` the 3,361 Prover9 re-runs at 300 s.
`oracle_scoreboard.sh BASE [RETRY ...]` merges them — the re-run's verdict
where one exists, the base's otherwise — and prints the scoreboard. It
reproduces the 10 s result exactly when given only the base, which is how it
was checked before being trusted on merged data.

Headline: **0 soundness violations** in either sweep. Prover9 answers 47.5% of
the 5,681 first-order problems with a usable SZS status at 300 s (38.5% at
10 s); Mace4 5.9% at 10 s, never re-run at 300 s.

### Provenance of `results/oracle-300s-mace4.tsv`: two builds, one boundary

This file was not produced by a single binary, and the reason is a mistake
worth not repeating: `bin/` was rebuilt while the sweep was running against
it. The boundary is at **row 3782**.

- **rows 1–3782** come from the build with M9 and M10 (cell table and negprop
  index bounded).
- **rows 3783 on** come from the build that adds M11 and M12 (honest
  accounting, and `max_megs` enforced before the first search node).

What that does and does not affect:

- **The capability figure is unaffected.** All 503 problems whose stated
  status allows a model, and all 31 models found, are above the boundary —
  one build, start to finish.
- **The soundness result is unaffected.** Everything below the boundary is
  `Unsatisfiable` (693), `Theorem` (664) or `ContradictoryAxioms` (32), where
  no model can exist. Those runs can only time out, reach `max_megs`, or
  expose a violation, and both builds are strictly *more* conservative about
  memory than the one before them, so neither can fabricate a model.
- **The verdict mix among non-answers is mixed.** Below the boundary, runs
  that would have died `FATAL` at the operating system's limit now exit
  cleanly as `MAX_MEGS` instead. That is M12 working, but it means the
  `FATAL`/`MAX_MEGS` split in this file is not uniform across its rows and
  should not be quoted as a single figure.

The rule it argues for: **do not rebuild the binary a sweep is running
against.** Build in a `git worktree` instead — `git worktree add --detach
/tmp/b <commit> && (cd /tmp/b && make all)` — which is how every gate in this
project was run while this sweep was in flight, and is the only reason the
boundary is at one known row rather than scattered.

### Check the scoreboard against known figures before trusting a new one

`oracle_scoreboard.sh` reproduces both recorded results exactly, and that is
how it is checked:

```sh
./oracle_scoreboard.sh results/oracle-10s.tsv.gz
#   17,992 runs, 0 UNSOUND, prover9 38.5%, mace4 5.9%, either 41.4%

./oracle_scoreboard.sh results/oracle-10s.tsv.gz results/oracle-300s-prover9.tsv.gz
#   prover9 47.5%, either 50.1%
```

It takes any number of re-run files now, one per prover, because their keys
are disjoint — the prover is part of the key. It also reads `.gz` directly,
which it did not: given a gzipped file it scored the gzip bytes as text,
reported "runs scored: 594" from binary noise, and died dividing by a zero
total. A count of zero now says what is wrong and exits 2 instead. The lesson
is the small one: a tool that crashes on bad input looks like a broken
analysis, while a tool that says "no scorable rows" points at the input.

## Provenance

This is third-party data, downloaded, and it is treated as untrusted input:
nothing here is executed, the paths are passed to the provers as arguments, and
the directory holds no scripts.

## The capability A/B, and why it needs a cross-feed

`baseline_ab.sh` runs the same sample against two builds, interleaved. The
first run of it on this tree (`results/cap-10s-*.tsv.gz`, 8,996 problems, both
provers, 10 s CPU, 4 GB per run, pristine `7f94204` against `ce7d848`) reported
prover9's sound answers down 2,353 -> 2,219, which read as a 134-answer
regression.

It was not one, and the reason matters for anyone comparing two builds that
differ in more than the prover. **A corrected translation is a different
problem.** This tree fixes a translator defect (T4: the negation of a
quantified formula was dropped), so for 1,000-odd problems the two builds are
not being asked the same question — the baseline was answering a formula the
input never contained. Losing such a problem is the fix working.

`cross_feed.sh` separates the two causes by running all four combinations of
{baseline, current} translation x {baseline, current} prover:

| | baseline prover | current prover |
| --- | ---: | ---: |
| **baseline translation** | 205 answers | 190 |
| **current translation** | 18 | 6 |

Per problem that is **186 input, 13 prover, 6 noise**. The 13 bisected to a
single commit and are written up as R1 in `../Prover9Mace4/FIXES.md`. Quoting
the 134 without the split would have been wrong in both directions at once:
it overstates the regression tenfold and hides a real one.

`freevars.py` is the other half of the argument, and it needs no logic. Every
TPTP `fof` formula is closed, so a free variable in the translated output is a
defect on its face. Over the 288 FOF problems involved, pristine emits **1,168
formulas with a free variable** and this tree emits **0**. The LADR-2026
translator (`62ae6ff`) emits the same 1,168 — the defect is live upstream.
