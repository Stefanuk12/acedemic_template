# Pandoc Report Template

A reproducible Markdown → PDF pipeline for academic / technical reports,
packaged as a Nix flake dev shell. Produces typeset PDFs with a polished
cover page, a table of contents, a list of figures, Harvard-style
citations, and full UML diagram support — entirely from plain Markdown
sources.

> \[!WARNING\] This template was built with significant AI assistance. It has been reviewed and tested, but you should still inspect anything that matters for correctness in your own context.
>
> Targeted at NixOS / Linux. macOS is exercised in CI; Windows is untested and likely needs adaptation.

## What's in the box

- **Markdown sources** in `src/*.md`, concatenated alphabetically — name files like `15-architecture.md` to slot them into the order.
- **Diagram backends** with caching: Mermaid, PlantUML (all 14 UML 2.x types), D2, Graphviz/dot, and TikZ. Drop-in fenced blocks; rendered to PDF.
- **Cover page** courtesy of [Eisvogel](https://github.com/Wandmalfarbe/pandoc-latex-template) (pinned via `flake.nix` to v3.4.0), with a `cover-style:` preset selector (navy / burgundy / forest / slate / crimson / plain) or full manual control via `titlepage-*` fields.
- **Harvard "Cite Them Right" citations** via citeproc, with the CSL fetched at build time and patched to approximate the 13th edition.
- **Figure cross-references** via `pandoc-crossref`, with a hyperlinked List of Figures.
- **Lettered appendix** (`A`, `A.1`, `A.2`, …) via raw LaTeX.
- **Word count** with configurable inclusion rules and an optional word-limit cap that can warn or fail the build.
- **Author tooling**: draft watermark, `[text]{.todo}` markers, acronym auto-expansion with auto-glossary, and a blind-review anonymous mode.
- **Multi-output builds**: `make html`, `make docx`, `make epub` alongside the default PDF.
- **Workflow tooling**: `make stats`, `make submit` (zips PDF + cleaned source), `make arxiv` (tarball with PDF + intermediate .tex + bib + diagram PDFs for arXiv submission), `make diff REF=…` (latexdiff-driven tracked changes against any git ref), `make review` (line-numbered PDF for supervisor / referee feedback), `make watch` (entr rebuild), `make typecheck` (LuaLS), `make gc-diagrams` (prune orphan diagram cache entries).
- **Pre-submission proofreading**: `make proofread` runs every static gate (typecheck, citation hygiene, spell-check, all `check-*` fixtures) in one shot; `make check-links` HEADs every URL in body + bib; and a [Claude Code skill](.claude/skills/paper-proofreading/SKILL.md) (`/paper-proofreading`) drives a full 7-phase prose pass — citations, cross-refs, TODO/FIXME residue, prose, structure, optional diff vs a base ref.
- **CI**: GitHub Actions workflow builds the PDF on Linux on PRs and on Linux + macOS on push to `main` and on releases. Cachix substitutes pre-built nix derivations so a warm run lands in ~2 min instead of ~5. A scheduled job opens a PR when the upstream Harvard CSL changes (gated on commits since the last successful run, so dormant repos don't burn cron slots).
- **Pre-commit hooks**: typecheck filters, validate citations on push, fix trailing whitespace and line endings.
- **Lua filter type-checking** via `lua-language-server` against upstream EmmyLua stubs.

## Quick start

Three paths, increasing in commitment. Pick the lowest row that still
covers your needs:

| Option | Consumer tree                  | Customisation                                     | When                                                       |
|--------|--------------------------------|---------------------------------------------------|------------------------------------------------------------|
| **C**  | `src/` + optional `refs/`      | None — bundled filters and template only          | One-off paper, you just want a PDF                         |
| **B**  | `src/` + `refs/` + `flake.nix` | `extraFilters`, template swap, engine, Make goals | You need a custom filter or a non-eisvogel template        |
| **A**  | Full fork                      | Anything — you own the Makefile and filter tree   | You want to evolve the template itself, not just consume it |

Migration is monotone: C → B is one new file, B → A is `git clone`. You
can't accidentally lock yourself in.

### Option A — fork-and-edit (you want to customise filters / Makefile)

```sh
git clone <your-fork-url>
cd <your-fork>
nix develop          # enters dev shell with all tools on PATH
make                 # builds build/report.pdf
make watch           # rebuilds on every save (entr; Ctrl-C to stop)
make typecheck       # static-check Lua filters
make open            # opens the PDF
make clean           # wipes build/
```

The dev shell creates two gitignored symlinks on entry:
`templates/eisvogel` and `types`, both pointing into the nix store at
the versions pinned in `flake.lock`. Bump them with `nix flake update`.

If you use direnv: `direnv allow` once and the shell auto-loads.

`nix build` produces `result/report.pdf` reproducibly without entering
the dev shell.

Set `ACEDEMIC_INSTALL_EXTENSIONS=1` before `nix develop` if you want
the shell hook to install the recommended VS Code / VSCodium
extensions automatically. Without it, the editor's own
"recommended extensions" prompt covers the same list.

### Option B — flake input (your repo only contains `src/` + `refs/`)

If you don't need to fork, consume the template as a flake input. Your
repo just contains your Markdown sources:

```
my-paper/
├── flake.nix
├── src/*.md
└── refs/refs.bib
```

```nix
# my-paper/flake.nix
{
  inputs = {
    nixpkgs.url      = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url  = "github:numtide/flake-utils";
    acedemic.url     = "github:<owner>/acedemic_template";
  };

  outputs = { self, nixpkgs, flake-utils, acedemic }:
    flake-utils.lib.eachDefaultSystem (system: {
      packages.default   = acedemic.lib.${system}.mkReport { src = ./.; };
      devShells.default  = acedemic.devShells.${system}.default;
    });
}
```

```sh
nix build              # produces result/report.pdf
nix develop            # tools on PATH; `make` works against ./src
```

`mkReport` accepts:

| Arg            | Default | Effect                                                                |
|----------------|---------|-----------------------------------------------------------------------|
| `src`          | (req.)  | Consumer repo root (must contain `src/*.md`)                          |
| `name`         | report  | Derivation pname                                                      |
| `srcDir`       | src     | Subdir of `src` holding the markdown                                  |
| `refsDir`      | refs    | Subdir holding `refs.bib` (and optional CSL)                          |
| `engine`       | xelatex | Pandoc PDF engine                                                     |
| `extraGoals`   | []      | Extra Make goals (e.g. `[ "html" ]`)                                  |
| `extraFilters` | []      | Consumer Lua filters layered on top of the bundled set (see below)    |
| `template`     | null    | Override the LaTeX template entirely; path to a `.latex` file         |

If the consumer doesn't ship `refs/harvard.csl`, `mkReport` drops in
the patched copy from `flake.nix:harvardCsl` automatically.

Bumping the template (eisvogel, filters, Makefile) is then a flake-lock
update on the consumer side: `nix flake update acedemic`.

#### Adding consumer Lua filters

Either point at individual files or at a directory:

```nix
acedemic.lib.${system}.mkReport {
  src = ./.;

  # Both forms accepted; mix freely.
  extraFilters = [
    ./filters                  # all *.lua in the dir (skips _-prefixed)
    ./extra/uppercase.lua      # individual file
  ];
}
```

Bundled filters run first (in their numeric order), then `extraFilters`
in the order given. Within a directory, files are alphabetised — same
convention as the bundled `NN-name.lua` scheme.

#### Swapping the LaTeX template

```nix
acedemic.lib.${system}.mkReport {
  src = ./.;
  template = ./templates/my-template.latex;
}
```

Pandoc resolves partials relative to the template file, so put any
`*.latex` partials next to it. To keep eisvogel but layer on extra
LaTeX header includes, prefer `header-includes:` / `include-before:`
in your `src/00-metadata.md` YAML frontmatter — that's what eisvogel is
designed for and avoids forking the template.

#### Adding refs / CSL

Just commit them to your repo at the standard paths — no flake plumbing
needed:

- `refs/refs.bib` — picked up automatically.
- `refs/harvard.csl` — overrides the bundled patched CTR13 copy if
  present. Drop in any other CSL from
  [citation-style-language/styles](https://github.com/citation-style-language/styles)
  to switch citation style.

### Option C — zero-flake `nix run` (no `flake.nix` in your repo)

If you don't want to write a `flake.nix` at all, run the template
directly against any directory that contains `src/*.md` (and optionally
`refs/refs.bib`):

```
my-paper/
├── src/*.md
└── refs/refs.bib       # optional
```

```sh
cd my-paper
nix run github:<owner>/acedemic_template
```

That builds `./build/report.pdf` in-place, using the bundled filters,
Makefile, eisvogel template, and lua type stubs from the pinned
flake — no checkout, no submodules, no dev shell. Pass extra Make
goals after `--`:

```sh
nix run github:<owner>/acedemic_template -- html docx stats
nix run github:<owner>/acedemic_template -- check-refs
```

To pin a known-good revision, append `/<ref>`:

```sh
nix run github:<owner>/acedemic_template/v0.3
```

Trade-off vs Option B: no `mkReport` customisation surface — you can't
layer in `extraFilters`, swap the template, or change the engine
without dropping a `flake.nix` next to your sources.

#### Outgrowing Option C → Option B

The moment you need any of: a custom Lua filter, a non-eisvogel
template, a non-xelatex engine, an `html`/`docx` build by default,
or a pinned input set (`nix flake update acedemic` instead of
re-fetching `master` on every run) — drop the Option B `flake.nix`
snippet above into your repo. Your `src/` and `refs/` keep working
unchanged; no source rewrite is needed.

## Layout

| Path                    | Purpose                                                |
|-------------------------|--------------------------------------------------------|
| `src/*.md`              | Source content, concatenated by filename order         |
| `src/00-metadata.md`    | YAML frontmatter (title, author, Eisvogel knobs, …)    |
| `filters/*.lua`         | Pandoc Lua filters (mermaid, plantuml, …)              |
| `filters/_*.lua`        | Shared filter helpers — excluded from the auto-load glob |
| `refs/refs.bib`         | BibTeX bibliography                                    |
| `refs/harvard.csl`      | Citation style (fetched + patched on first build)      |
| `data/`                 | Sample data exercising the csv filter's `file=` attribute |
| `templates/eisvogel/`   | Eisvogel template (dev-shell symlink → flake input)    |
| `types/`                | Pandoc Lua API stubs (dev-shell symlink → flake input) |
| `flake.nix`             | Reproducible dev shell + buildable package             |
| `Makefile`              | Build / watch / typecheck commands                     |
| `tests/fixtures/`       | Minimal mkReport fixtures exercised by `nix flake check` |
| `docs/`                 | Authoring guide, customisation, maintenance            |
| `.claude/skills/`       | Claude Code skills shipped with the template (see below) |
| `build/`                | Generated artefacts (gitignored)                       |

## Proofreading the paper

Two complementary entry points run before you submit / hand to a
supervisor.

### `make proofread` — static gates only

```sh
nix develop --command make proofread
```

Runs `typecheck`, `check-refs`, `spellcheck`, `check-inverse`,
`check-diagram-failure`, `check-wordcount-strict`, `check-csv-strict`,
and `check-anonymous` in cheap-to-expensive order, failing fast. Pass
means "the build is safe to ship"; it does not prove the prose is
good. Intentionally does not rebuild the PDF — run `make` separately
for the render. Network-dependent checks (`make check-links`) are
kept out of the gate; run that one separately before submission.

- `make check-refs` — cited-vs-defined diff PLUS per-entry-type
  required-field gate (article needs author/title/journal/year;
  book needs publisher; etc.) so the rendered references list never
  shows ?, n.d., or "Untitled" placeholders.
- `make spellcheck` — pandoc → plain-text → `aspell list` against a
  repo-local dictionary at `.aspell.en.pws`. Extend with
  `make spellcheck-add WORDS="foo bar baz"`; the target validates
  aspell's constraints (no hyphens, no boundary digits, no Unicode
  quotes), bumps the dictionary counter, and re-runs the check. The
  failing spellcheck output prints a copy-pastable `spellcheck-add`
  invocation for the rejected words. See
  [docs/authoring.md](docs/authoring.md#extending-the-spell-check-dictionary)
  for the full workflow.
- `make check-links` — HEAD every http(s) URL in body + bib
  (including DOIs via doi.org) with a 15s timeout. Fails on
  4xx / 5xx / connect errors. Skip with `make check-links SKIP=1`
  when offline.

### `/paper-proofreading` — full prose pass (Claude Code skill)

The repo ships a Claude Code skill at
[.claude/skills/paper-proofreading/SKILL.md](.claude/skills/paper-proofreading/SKILL.md).
Invoke it in Claude Code with `/paper-proofreading`, or just ask
Claude to "proofread the paper" / "do a final pass before submission".

It runs 7 phases against the Markdown sources:

1. **Build gate** — calls `make proofread`.
2. **Citation hygiene** — `make check-refs` + `{.cite-needed}` audit +
   bare-claim heuristic + format / multi-citation grouping consistency.
3. **Cross-reference validity** — `@fig:foo` / `[@tbl:bar]` ↔
   `{#fig:foo}` declarations.
4. **TODO / FIXME residue** — `{.todo}`, `{.fixme}`, `{.cite-needed}`
   spans.
5. **Prose review** — grammar, voice, tense, hedge density, sentence
   length, filler, duplicate acronym expansions.
6. **Structure & front matter** — YAML completeness, heading depth vs
   `toc-depth`, wordcount vs configured `limit:`.
7. **Diff vs a named base ref** — uses `make diff REF=<ref>`.

Findings land in `build/proofread.md` (gitignored) with a Blockers /
Recommended / Stylistic summary. The skill is read-only on
`src/00-metadata.md`, `tests/fixtures/`, and `filters/*.lua` — those
are out of scope for a prose pass.

> Consumers using **Option B** (`mkReport` as a flake input) don't
> inherit `.claude/skills/` automatically — copy
> `.claude/skills/paper-proofreading/SKILL.md` into their tree, or
> switch to **Option A** (fork-and-edit). Consumers using **Option C**
> (`nix run`) don't get the skill — the workflow is meant for repos
> you're actively editing.

## Further reading

- [docs/authoring.md](docs/authoring.md) — adding sections, diagrams,
  citations, cross-references.
- [docs/customising.md](docs/customising.md) — cover page tweaks, word
  count config, filter naming convention.
- [docs/maintenance.md](docs/maintenance.md) — bumping pinned versions,
  CI layout, pre-commit hooks, diagram cache GC.
