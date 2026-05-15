# Introduction

This fixture exercises the inverse branches of four toggleable filters
in a single mkReport build: hide-mode todos, glossary append-on-render,
unknown cover-style fallback, and the wordcount warn branch.

This paragraph has a [hidden marker]{.todo} that filters/04-todos.lua
must delete in hide mode. The body also uses HIDE so filters/05-glossary.lua
records the acronym for the appended glossary.

It cites [@fixture2026] to exercise citeproc.

This block deliberately references a non-existent file to exercise
filters/csv.lua's failure-placeholder branch — the build keeps going
and the rendered output gets a visible red box in place of the table.
The assertion harness counts placeholder occurrences in the LaTeX,
not in this prose, so do not name the placeholder phrase here.

```{.csv file=data/this-file-does-not-exist.csv caption="A non-existent file"}
```

The next inline block exercises the header=false branch of csv.lua
(first row is data, not a header). The first cell's literal value is
asserted to appear in the LaTeX output exactly once, which only holds
if the header=false code path runs and the cell goes through to the
body of the rendered longtable.

```{.csv #tbl:hf header=false caption="Header-less inline CSV"}
bodycellhf,beta,gamma
delta,epsilon,zeta
```

The empty fenced block below has zero rows after parsing, so csv.lua
hits the placeholder branch via the `#rows == 0` check (a distinct
path from the io.open failure above) and emits a second placeholder
keyed by the block identifier.

```{.csv #tbl:empty caption="Empty inline CSV block"}
```

# Excluded section {#sec:excluded}

This section's heading carries the identifier sec:excluded, which is
listed in wordcount.exclude-sections in the metadata. The unique token
EXCLUDEDSECTIONTOKEN appears only here; check-inverse verifies that
the rendered LaTeX still contains it (the heading is kept, only the
word-count contribution is suppressed by filters/00-wordcount.lua).

# Body resumes

The wordcount filter must resume counting in this section — the
excluded-section rule only applies until the next heading at the same
or higher level. The marker RESUMEDBODYTOKEN is grep-asserted in
check-inverse to confirm the post-excluded prose still renders.

# References
