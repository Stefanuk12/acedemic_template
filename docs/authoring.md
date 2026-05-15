# Authoring guide

> **Ready to submit?** Skip to [Pre-submission proofreading](#pre-submission-proofreading)
> for the `make proofread` gate and the `/paper-proofreading` Claude
> Code skill that drives a full 7-phase prose pass against your sources.

## Add a new section

Drop a Markdown file into `src/`. Files are concatenated alphabetically:

```
src/00-metadata.md
src/01-introduction.md
src/10-mermaid.md       <-- existing example
src/15-architecture.md  <-- your new section, slotted between 10 and 20
src/20-plantuml.md
…
```

## Mermaid diagrams

````
```{.mermaid #fig:auth-flow caption="Login sequence"}
sequenceDiagram
    User->>App: credentials
    App->>DB: lookup
```
````

Reference it later with `[@fig:auth-flow]` → renders as `Fig. 2.1` and
appears in the List of Figures.

## PlantUML diagrams

Same pattern, just `.plantuml`:

````
```{.plantuml #fig:component-view caption="Component breakdown"}
@startuml
[Frontend] --> [Backend]
[Backend] --> [Database]
@enduml
```
````

`@startuml` / `@enduml` are added automatically if missing.

## TikZ diagrams

For mathematically precise figures, use `.tikz`. The block body goes
straight inside `\begin{document}` of a `standalone` LaTeX document
and is compiled with the same engine as the rest of the build
(`ENGINE`, default `xelatex`):

````
```{.tikz #fig:layers caption="Stack layers" libraries=arrows.meta,positioning}
\begin{tikzpicture}[
  node distance=8mm,
  every node/.style={draw, rectangle, minimum width=3cm, minimum height=8mm}
]
  \node (app)  {Application};
  \node (lib)  [below=of app]  {Library};
  \node (os)   [below=of lib]  {Operating system};
  \draw[->, thick] (app) -- (lib);
  \draw[->, thick] (lib) -- (os);
\end{tikzpicture}
```
````

Optional attributes:

| Attribute   | Effect                                                              |
|-------------|---------------------------------------------------------------------|
| `libraries` | Comma-separated `\usetikzlibrary{…}` entries (e.g. `arrows.meta`)   |
| `preamble`  | Extra preamble lines (rare; for one-off custom commands)            |
| `width`     | Sets pandoc image width on the rendered figure                      |
| `#fig:…`    | Cross-reference identifier, consumed by `pandoc-crossref`           |

Both `libraries` and `preamble` are mixed into the cache key via the
`source_transform` hook in `filters/_diagram.lua` — changing them
invalidates the cache so the figure re-renders.

## Citations

Add entries to `refs/refs.bib`. Cite them with:

- Parenthetical: `software architecture is widely studied [@bass2021].`
- In-prose: `@kruchten1995 proposed the 4+1 view model.`
- Multiple: `[@bass2021; @fowler2014]`
- Page numbers: `[@bass2021, p. 42]`

The reference list is appended automatically at the `# References` section in `src/90-references.md`.

## Cross-references

`pandoc-crossref` understands `#fig:label`, `#tbl:label`, `#eq:label`, and `#sec:label`. Reference them as `[@fig:label]`, etc.

## Diagram failures

If a diagram backend (`mmdc`, `plantuml`, `d2`, `dot`) fails to render
a block, the build inserts a red **DIAGRAM FAILED — &lt;backend&gt; (&lt;hash&gt;)**
placeholder where the figure would have been. Search the build log for
the matching `[backend] ... failed for diagram &lt;hash&gt;` line for
diagnostic detail.

Set `DIAGRAM_FAIL_HARD=1` in the environment to turn placeholders into
hard build failures (useful in CI).

## Pre-submission proofreading

Two complementary entry points: a Make target that runs all the static
gates, and a Claude skill that drives a full multi-phase prose review.

### `make proofread` — static gates only

```sh
nix develop --command make proofread
```

Runs `typecheck`, `check-refs`, `spellcheck`, `check-inverse`,
`check-diagram-failure`, `check-wordcount-strict`, `check-csv-strict`,
and `check-anonymous` in order, failing fast on the first non-zero
exit. Cheap-to-expensive order means a broken Lua filter or a missing
bib entry surfaces before the heavier fixture builds. Pass means "the
build is safe to ship"; it does NOT prove the prose is good.

Intentionally does not rebuild the PDF. Run `make` separately when you
also want the render. Network-dependent checks (`make check-links`)
are also kept out of the gate — run that one separately before
submission.

### Individual targets that the gate composes

| Target                    | Catches                                                                            |
|---------------------------|------------------------------------------------------------------------------------|
| `make typecheck`          | Lua filter syntax + EmmyLua type errors                                            |
| `make check-refs`         | citations without bib entries, orphan bib entries, AND per-entry-type field gaps   |
| `make spellcheck`         | unknown words against `.aspell.en.pws` (project dictionary; see below to extend)   |
| `make check-links`        | dead URLs in body + bib (HEAD with 15s timeout per URL; not in the gate — network) |
| `make check-inverse`      | every filter's inverse-mode branch renders the expected output                     |
| `make check-diagram-failure` | every diagram backend's default + strict-mode failure path                      |
| `make check-wordcount-strict` | strict-mode overflow kills the build with a clean stderr message               |
| `make check-csv-strict`   | `CSV_FAIL_HARD=1` escalates csv failure to a hard error                            |
| `make check-anonymous`    | filters/03-anonymous.lua rewrites the author in isolation from 07-authors          |

### Extending the spell-check dictionary

`make spellcheck` fails fast on any word not in `.aspell.en.pws`.
When it surfaces a legitimate project-specific term (a person's
surname, a domain acronym, a CLI name), accept it with:

```sh
nix develop --command make spellcheck-add WORDS="foo bar baz"
```

That appends each word (one per line), bumps the trailing counter on
the dictionary's first line, and re-runs `make spellcheck` to confirm
the new entries load cleanly. The failing `make spellcheck` output
also prints a copy-pastable `spellcheck-add` invocation for whichever
words it just rejected, so the round-trip is:

```sh
make spellcheck                                  # ✗ unknown: HMAC, OAuth
make spellcheck-add WORDS="HMAC OAuth"           # paste from the failure
make spellcheck                                  # ✓ clean
```

aspell's personal dictionary format has three constraints — the
`spellcheck-add` target surfaces them as rejections rather than
appending an invalid line:

| Constraint                            | Workaround                                          |
|---------------------------------------|-----------------------------------------------------|
| No hyphens (`pre-commit`, `arXiv-id`) | Register the parts (`pre`, `commit`) separately     |
| No digits at boundaries (`v3`, `Q1`)  | Rephrase, or accept the warning if it's rare        |
| No Unicode quotes (curly `'` / `"`)   | Use ASCII apostrophes in source AND in dictionary   |

Pandoc smart-quote handling (curly `'` / `"`) is stripped from the
spellcheck pipeline via `--from=markdown-smart`, so `crossref's` in
the source is checked as the ASCII form `crossref's`. Register the
possessive directly (`crossref's`) when the root word is too rare to
shorten.

To remove a word: open `.aspell.en.pws` directly, delete the line,
and decrement the trailing counter on line 1 (or just bump it down
by the number of deletions).

### Setting up the Cachix binary cache (one-time)

[`.github/workflows/build.yml`](../.github/workflows/build.yml) is
wired to push pre-built Nix derivations to a Cachix cache so that
subsequent runs pull the texlive/pandoc/diagram-backend store paths
instead of rebuilding them. A warm run lands in ~2 min vs ~5 min cold.

If you fork or rename the repo, do this once:

1. Sign in at <https://app.cachix.org>.
2. Create a cache. Name it `acedemic-template` to match the workflow,
   or pick your own and edit the `name:` field on the `Set up Cachix`
   step in `build.yml`.
3. From the cache's Settings page, generate a **Write** token.
4. Add it as repo secret `CACHIX_AUTH_TOKEN`
   (Settings → Secrets and variables → Actions → New repository secret).

Without the token, the workflow falls back to read-only mode: it
still subscribes the cache as a substituter (so derivations someone
else pushed can be pulled) but won't push new ones — which means the
cache stops accumulating useful entries. Don't ship the template
without setting this up unless you genuinely want every CI run to
rebuild texlive from source.

### Running CI locally

Before pushing a branch that might break CI, run the GitHub Actions
workflow in Docker via [act](https://github.com/nektos/act):

```sh
nix develop --command make ci-local
```

That invokes `act` with the settings in `.actrc` (committed alongside
this Makefile): platform pinned to `catthehacker/ubuntu:act-latest`,
macOS matrix leg skipped, action cache + upload artifacts redirected
under `build/`. The first run pulls the runner image (~17 GB) and
installs Nix into the container — expect 25-40 minutes end-to-end.
Subsequent runs reuse the cache.

Pass extra flags via `ACT_ARGS`:

```sh
make ci-local ACT_ARGS="-j pdf --verbose"             # one job, verbose
make ci-local ACT_ARGS="-W .github/workflows/bump-csl.yml"  # different workflow
make ci-local ACT_ARGS="--list"                       # enumerate jobs and exit
```

Limitations:

| Limitation                         | Reason                                                             |
|------------------------------------|--------------------------------------------------------------------|
| macOS matrix leg is skipped        | `act` is Linux-only; macOS only runs on hosted GitHub Actions      |
| `magic-nix-cache-action` no-ops    | Local runs have no GitHub cache backend; the action degrades gracefully |
| Artifact uploads land in `build/`  | `act` writes to a local server instead of GitHub's artifact storage|

A green `ci-local` run on the `pdf` job is a strong predictor of a
green run on hosted CI — but it isn't proof; release-attached
artefacts, scheduled jobs, and macOS-specific failures only surface
upstream.

### Building variants

| Target                 | What it produces                                                                              |
|------------------------|-----------------------------------------------------------------------------------------------|
| `make`                 | `build/report.pdf` — the canonical deliverable                                                 |
| `make review`          | `build/report-review.pdf` — every body line numbered for supervisor / referee feedback         |
| `make diff REF=<ref>`  | `build/report-diff.pdf` — latexdiff-rendered tracked changes against another git revision      |
| `make arxiv`           | `build/arxiv.tar.gz` — PDF + pandoc-intermediate `.tex` + bib + diagram PDFs + REBUILD note    |
| `make submit`          | `build/submit.zip` — PDF + clean source tree, suitable for handing in                          |
| `make html / docx / epub` | secondary single-file outputs of the same content                                            |

### `/paper-proofreading` — full prose pass

The repo ships a Claude Code skill at
[.claude/skills/paper-proofreading/SKILL.md](../.claude/skills/paper-proofreading/SKILL.md)
that does the 7-phase pre-submission review:

1. Build gate (calls `make proofread`)
2. Citation hygiene (`make check-refs` + `{.cite-needed}` audit + bare-
   claim heuristic + format/grouping consistency)
3. Cross-reference validity (`@fig:foo` / `[@tbl:bar]` ↔ `{#fig:foo}`
   declarations)
4. TODO / FIXME residue (`{.todo}`, `{.fixme}`, `{.cite-needed}` spans)
5. Prose review (grammar, voice, tense, hedge density, sentence length,
   filler, duplicate acronym expansions)
6. Structure & front matter (YAML completeness, heading depth vs
   `toc-depth`, wordcount vs configured `limit:`)
7. Diff vs a named base ref (uses `make diff REF=<ref>`)

Invoke it in Claude Code with `/paper-proofreading`, or just ask
Claude to "proofread the paper" / "do a final pass before submission".

The skill writes its findings to `build/proofread.md` (gitignored) with
fixed-shape sections and a summary that counts Blockers / Recommended /
Stylistic findings separately. It will NOT modify `src/00-metadata.md`,
`tests/fixtures/`, or `filters/*.lua` — those are out of scope for a
prose pass.

`.claude/skills/` is gitignored by default — the skill ships with this
template's tree, but consumer repos using Option B (`mkReport` as a
flake input) won't inherit it automatically. To use it in a consumer
repo, copy the `SKILL.md` into their `.claude/skills/paper-proofreading/`
or fork Option A.
