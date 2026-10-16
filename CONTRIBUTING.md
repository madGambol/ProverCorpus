# Working in this repository

This holds input data and the scripts that drive sweeps over it. It is
deliberately separate from `Prover9Mace4`, because the gates there need it to
outlive any one session: it lived in a session scratchpad once, which meant
the two most valuable gates could not be re-run after that session ended.

Two rules, both learned the hard way.

**Results are committed compressed, and the run that produced them is
recorded.** A results file whose provenance is not written down is worth
much less than one whose is. `results/oracle-300s-mace4.tsv` has a build
boundary at row 3782 because `bin/` was rebuilt mid-sweep; that is in
`README.md`, with what it does and does not affect.

**Never rebuild the binary a sweep is running against.** Build in a
`git worktree` instead:

```sh
cd ~/Projects/Prover9Mace4
git worktree add --detach /tmp/b <commit> && (cd /tmp/b && make all)
```

Every gate accepts a bin directory, so there is never a reason to touch the
live `bin/` while a sweep is in flight.

---

Copyright (C) 2026 Chris Arena, 2026-10-16.  Written in collaboration
with Claude Opus 5 (Anthropic).  GPL-2.0-only; see `COPYING`.  Not part
of the LADR-2009-11A release.
