---
name: paper-proofreading
description: Multi-pass proofread of the Markdown + Pandoc paper sources in this repo. Checks prose quality, citation hygiene, cross-reference validity, TODO/FIXME residue, acronym usage, wordcount-limit headroom, and a clean rebuild. Use when the user asks to "proofread the paper", "do a final pass", "check before submission", or names any of: prose, grammar, clarity, citations, cross-refs, todos, figures, structure.
---

# Paper proofreading (Markdown + Pandoc)

This repo is a Pandoc/Markdown report pipeline, NOT a LaTeX repo. The
canonical source is `src/*.md` (concatenated alphabetically), with
`refs/refs.bib` for citations and `filters/*.lua` for in-build
transforms. Treat the build (`make`) as the source of truth — if a
check is encoded in a `make check-*` target, run that instead of
hand-rolling a grep.

## Hard constraints

1. **Never rewrite prose in `src/00-metadata.md`.** It's YAML front-
   matter consumed by Pandoc + the Lua filters; reformatting it
   silently breaks the build. Body prose lives in `src/10-*.md`,
   `src/15-*.md`, etc.
2. **Do not modify `tests/fixtures/`.** Those are regression fixtures
   exercised by `make check-inverse`, `check-anonymous`, etc. Touching
   their content invalidates the assertions.
3. **Do not modify `filters/*.lua` during a proofreading pass.** Those
   are build logic, not prose. Surface filter bugs as findings; don't
   fix them inline.
4. **Quote, don't rewrite, in your report.** Show the original snippet,
   then propose the change. Let the author accept or reject. The
   exception is `[text]{.todo}` / `{.fixme}` / `{.cite-needed}` spans —
   those are the author's open notes; flag them but never delete them.

## What "the paper" means here

Body sources only. The file ordering is alphabetic by filename, so
`src/01-introduction.md`, `src/10-mermaid.md`, …, `src/90-references.md`,
`src/99-appendix.md` is the actual reading order. Confirm with:

```sh
ls src/*.md | sort
```

## Workflow

Run the 7 phases below in order. Each phase produces a section in your
final report. Don't skip phases just because the count is zero — say
"0 findings" explicitly so the author knows the check ran.

### Phase 1 — clean build gate

Before any prose review, prove the build is currently healthy.
A broken build can mask later findings (e.g. a Pandoc filter erroring
out leaves citations un-resolved, so "missing citation" findings become
unreliable).

One target wraps every gate check:

```sh
nix develop --command make proofread
```

That runs (in order, failing fast): `typecheck` → `check-refs` →
`spellcheck` → `check-inverse` → `check-diagram-failure` →
`check-wordcount-strict` → `check-csv-strict` → `check-anonymous`.
If it prints "✓ proofreading gate clean", proceed. If it prints "✗"
anywhere, STOP and report the failure as the first finding — do not
move to prose review until the build is healthy.

`check-refs` covers both directions: cited-but-undefined keys AND
per-entry-type required-field gaps (an `@article` without `journal`,
an `@inproceedings` without `booktitle`, etc.).

`spellcheck` uses a project dictionary at `.aspell.en.pws`. If it
fails on a legitimate project-specific term (a person's surname,
a domain acronym not yet registered in `acronyms:`), append the term
to the dictionary; if it fails on a real typo, fix the source.

The gate intentionally does NOT include `check-links` — link health
depends on the network and would make the gate flaky. Run it
separately before submission:

```sh
nix develop --command make check-links
```

Then build the actual PDF (the gate intentionally doesn't, so you only
pay the cost once you know the gate is green):

```sh
nix develop --command make                # build/report.pdf
```

### Phase 2 — citation hygiene

`make check-refs` already catches cited-but-undefined and unused-but-
defined entries. After that passes, look deeper:

1. **Cite-needed markers.** Every `{.cite-needed}` span is an author
   IOU. List them with location:
   ```sh
   grep -nE '\{\.cite-needed\}' src/*.md
   ```
2. **Bare claims in the body.** Heuristic scan for statements that look
   like they should be cited but aren't. Phrases that often signal an
   uncited claim:
   - "studies have shown"
   - "it is widely accepted"
   - "research indicates"
   - "previous work"
   - "the literature"
   - "according to"
   - Year tokens not adjacent to a `@key` (e.g. "in 2024" with no
     citation nearby)

   Flag with file + line + the surrounding sentence. Do NOT auto-add
   citations — propose the bib entry the author should look up.

3. **Citation-format consistency.** `[@key]` is parenthetical,
   `@key` is narrative ("As @smith2024 showed…"). Both are valid;
   inconsistency within a single section often reads as sloppy.

4. **Multi-citation grouping.** `[@a; @b; @c]` is correct;
   `[@a], [@b], [@c]` is not. Grep for `\], \[@`.

### Phase 3 — cross-reference validity

This template uses `pandoc-crossref` with sec/fig/tbl/eq/lst prefixes.
Cross-references live as `@fig:foo` / `[@fig:foo]` in body prose and
must point to a target declared with `{#fig:foo}` somewhere.

1. **Find all targets** (`{#prefix:id}` declarations):
   ```sh
   grep -hoE '\{#[a-z]+:[A-Za-z0-9_-]+[^}]*\}' src/*.md | grep -oE '#[a-z]+:[A-Za-z0-9_-]+' | sort -u
   ```
2. **Find all references** (`@prefix:id` mentions):
   ```sh
   grep -hoE '@[a-z]+:[A-Za-z0-9_-]+' src/*.md | sort -u
   ```
3. Diff the two. Any reference without a target is a broken xref;
   any target without a reference is a dangling label (less serious
   but worth flagging).
4. Sanity-check the rendered PDF: in `build/report.pdf` you should see
   "Figure 3", "Table 1", "§2.1", etc. — never literal `[@fig:foo]`.
   If a literal escapes into the PDF, the xref didn't resolve.

### Phase 4 — TODO / FIXME residue

`filters/04-todos.lua` supports three marker classes, each meant for a
different review stage:

| Class            | Meaning                                  | Allowed in submission? |
|------------------|------------------------------------------|------------------------|
| `{.todo}`        | Author note, low urgency                 | No                     |
| `{.fixme}`       | Known defect to fix before submission    | No                     |
| `{.cite-needed}` | Claim needs a citation                   | No                     |

Surface every occurrence with file + line + the surrounding sentence:

```sh
grep -nE '\{\.(todo|fixme|cite-needed)\}' src/*.md
```

The `wordcount:show` filter optionally renders these visibly in the
cover-page word count, so they're not strictly silent — but in a
proofreading pass they should be ZERO. List them; let the author
either resolve or accept residual debt.

### Phase 5 — prose review (the actual proofreading)

For each body file in `src/*.md` (excluding `00-metadata.md`), look for:

1. **Grammar / spelling.** Quote the exact sentence; propose the fix.
2. **Voice consistency.** Active vs passive, first-person plural ("we
   show") vs impersonal ("it is shown"). Pick what dominates and flag
   outliers — don't enforce either globally without checking the
   author's preference.
3. **Tense consistency.** Background usually past tense ("Smith
   showed"), present claims about the work usually present ("This
   paper presents"). Flag mid-paragraph tense swaps.
4. **Hedge density.** "Might", "perhaps", "arguably", "to some extent"
   stacked together weaken the claim. Two hedges per sentence is the
   informal ceiling for academic prose.
5. **Sentence length.** Sentences over ~40 words usually benefit from
   a split. Flag the longest 5 per file with their word counts.
6. **Paragraph length.** Single-sentence paragraphs in the body
   (excluding figures/code blocks) read as fragments. Flag.
7. **Filler / throat-clearing.** "It should be noted that",
   "In order to", "Due to the fact that", "At this point in time".
   Suggest the tightened version.
8. **First-occurrence acronyms.** The acronyms filter expands the
   first appearance of a key from `acronyms:` to "Long form (KEY)".
   If the body manually expands a key the YAML already lists,
   that's a duplicated expansion — flag.

For each issue: filename, line, original sentence, proposed change,
one-line rationale. Don't write a stylebook; ship findings.

### Phase 6 — structure & front matter

1. **YAML frontmatter completeness.** Open `src/00-metadata.md` and
   confirm at minimum: `title`, `author` (or `authors:`), `cover-style`,
   `wordcount:` block. For a thesis-style report also: `acronyms:`,
   `glossary:`, `dedication` / `acknowledgements` / `declaration`.
   If `anonymous: true`, confirm no author name leaks into body prose.

2. **Section depth.** `pandoc-crossref` is configured with `toc-depth:
   3`. Headings at `####` (level 4) and below won't appear in the TOC.
   Flag deeply-nested headings as likely-overstructured.

3. **Heading capitalization.** "Title Case" or "Sentence case" —
   pick what dominates and flag outliers.

4. **Word count vs configured limit.** The `wordcount:` block in the
   metadata declares `limit:` (and optionally `strict:`). After
   building, get the current count:

   ```sh
   nix develop --command make stats
   ```

   Compare to the limit. If `strict: true` and you're over, the build
   would have failed in Phase 1 — but in `strict: false` mode the
   author may be unknowingly over. Flag headroom: "currently N words,
   limit M, X% utilized." Aim for under 95% as a safety margin.

5. **Reference section ordering.** `90-references.md` must precede
   `99-appendix.md` so references list before the appendix. Confirm
   the alphabetic ordering hasn't been broken by an inserted file.

### Phase 7 — diff against last reviewed revision

If the user names a base ref (e.g. "since the supervisor read it last
month"), use the built-in latexdiff target to produce a tracked-changes
PDF, then list the substantive deltas:

```sh
nix develop --command make diff REF=<ref>
```

Output: `build/report-diff.pdf`. Walk the diff text version:

```sh
git diff <ref>...HEAD -- src/*.md refs/refs.bib
```

For each substantive change (skip whitespace-only, list re-ordering
that doesn't change content), summarise in 1 line. The author can
then judge whether the supervisor's previous feedback was addressed.

If no base ref is given, skip Phase 7.

## Output format

Write findings to a single markdown report at `build/proofread.md`
(create `build/` if missing — it's gitignored). Don't write into
`docs/` or the repo root.

Structure:

```markdown
# Proofreading report

**Built at:** <ISO timestamp>
**Against:** <git rev-parse HEAD>
**Base ref (if Phase 7 ran):** <ref or "—">

## 1. Build gate
✓ make typecheck / check-refs / check-inverse / check-diagram-failure /
  check-wordcount-strict / check-csv-strict / check-anonymous / build
  — all clean.

(or: ✗ <failed target> — <error excerpt>)

## 2. Citation hygiene
- N cite-needed markers (list)
- N likely-uncited claims (list with snippet + proposed bib lookup)
- 0 format inconsistencies / multi-citation grouping issues

## 3. Cross-reference validity
- N broken @prefix:id references (list with target name)
- N dangling labels (list)

## 4. TODO / FIXME residue
- {.todo}: N (list file:line + sentence)
- {.fixme}: N
- {.cite-needed}: N

## 5. Prose review
### src/<file>.md
- L<line>: <original> → <proposed>. <one-line rationale>
- …

## 6. Structure & front matter
- Word count: <count>/<limit> (<percent>%) — <ok | watch | over>
- N heading-style outliers
- N over-deep headings

## 7. Diff vs <ref> (omit if skipped)
- One bullet per substantive change.

## Summary
- Blockers (must-fix before submission): N
- Recommended (should-fix): N
- Stylistic (consider): N
```

## Final reminders

- **Brevity beats completeness.** A 20-finding report the author will
  actually read beats a 200-finding report they won't. If a category
  has more than 15 entries, list the top 10 by severity and note
  "+N more — run the grep above to see all".
- **Never auto-stage or auto-commit your findings.** The report is
  reference material; the author drives the actual edits.
- **Don't enter the LaTeX worldview.** This is Pandoc; cross-refs are
  `@fig:foo`, not `\ref{fig:foo}`. Headings are `# Foo {#sec:bar}`,
  not `\section{Foo}\label{sec:bar}`. Citation keys live in
  `refs/refs.bib`, queried via `make check-refs`. If you find yourself
  reaching for a `.tex` file, you're in the wrong repo.
- **Use the dev shell.** Every `make` target above assumes
  `nix develop --command` (or an active dev shell). Outside that
  context, `pandoc`, `lua-language-server`, and the diagram backends
  won't be on PATH and the checks will produce false negatives.
