# Licensing

This repository holds three kinds of thing, under two sets of terms.

## The scripts, the problem lists and the results: GPL-2.0-only

Everything written for this repository — the sweep drivers, the scoring and
analysis tools, `run_one.sh`, the problem lists and everything under
`results/` — is **GPL-2.0-only**, the same licence as the tree it tests.
[`COPYING`](COPYING) holds the licence text, and each script carries the notice
in its own header, dated, with the copyright held by Chris Arena and a second
line recording that the file was written in collaboration with Claude Opus 5 —
the same thing the `Co-Authored-By` trailer on every commit says. The credit is
deliberately not in the copyright line: the US Copyright Office's position is
that purely machine-generated material is not copyrightable, so a joint holder
line would assert something the law does not grant, while the authorship is
simply a fact about how the file was written. The three Markdown files carry a
one-line footer instead of a header, so that a licence block is not the first
thing a reader meets.

`COPYING` was added when these notices were: a repository that tells you
"you should have received a copy of the GNU General Public License" should be
the one that gave it to you, and this one is distributed on its own, not only
beside the tree it tests.

GPL-2.0-only rather than "or later" because the LADR-2009-11A sources say
"version 2" without the "or (at your option) any later version" clause, and a
test corpus for a GPL-2.0-only program is not usefully more permissive than
the program.

## The bundled Prover9 material: McCune's, under his terms

| path | what |
| --- | --- |
| `prover9-manual-2009-11A/`, `prover9-manual-2009-11A.tar.gz` | the worked examples from William McCune's Prover9 manual |
| `web/2009-11A/` | the example sets published with the LADR-2009-11A release |

These are McCune's own files, redistributed unmodified from the LADR/Prover9
web distribution, and they keep whatever terms they came with. They are here
because the gates need them and because the distribution they came from is no
longer maintained.

## What is NOT here, and must be obtained separately

**The TPTP problem library.** `results/` records verdicts against problem
*paths* — `Problems/MGT/MGT072+1.p` and the like — and contains none of the
problems themselves. Reproducing any TPTP figure needs **TPTP v9.3.1** from
<https://www.tptp.org>, which has its own terms. Point the scripts at it with
`TPTP_DIR`.

**The provers.** The scripts expect a built `Prover9Mace4` tree; they look for
`../Prover9Mace4/bin` by default and take `BIN_DIR` otherwise.

---

Copyright (C) 2026 Chris Arena, 2026-10-16.  Written in collaboration
with Claude Opus 5 (Anthropic).  GPL-2.0-only; see `COPYING`.  Not part
of the LADR-2009-11A release.
