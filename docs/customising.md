# Customising

## Cover page

Edit `src/00-metadata.md`. Useful Eisvogel knobs:

| Field                  | Effect                                              |
|------------------------|-----------------------------------------------------|
| `title` / `subtitle`   | Cover page text                                     |
| `author`               | Cover + page footer                                 |
| `titlepage-color`      | Hex color of the top block (no `#`)                 |
| `titlepage-rule-color` | Hex color of the dividing rule                      |
| `logo`                 | Path to a PDF/PNG logo (e.g. `assets/logo.pdf`)     |
| `logo-width`           | e.g. `100mm`                                        |
| `book: true`           | Switch to scrbook (chapters; drops abstract)        |

For more, see [Eisvogel's README](https://github.com/Wandmalfarbe/pandoc-latex-template).

## Word count

A Lua filter (`filters/00-wordcount.lua`) counts the document's words
and can display the count on the cover page. All configuration lives
under the `wordcount:` map in `src/00-metadata.md`:

```yaml
wordcount:
  show: true                # display "N words" on the cover

  # Defaults follow common UK academic conventions: only body prose
  # is counted. Flip any flag below to widen the scope.
  include-cover:       false   # title, subtitle, author, abstract
  include-references:  false   # everything after # References
  include-appendix:    false   # everything after \appendix
  include-citations:   false   # in-text [@key] citations
  include-quotations:  false   # block quotes (BlockQuote)

  # Skip specific sections by their heading identifier:
  exclude-sections: []         # e.g. [sec:methods, sec:limitations]

  # Optional hard limit. `limit` warns; `strict: true` fails the build.
  limit: 10000
  strict: false
```

`# References`, `# Bibliography` and `\appendix` are detected
automatically. CodeBlocks, raw LaTeX/HTML blocks, and inline raw code
are always excluded.

The formatted count is also exposed as `word-count` for use in custom
template snippets — e.g. `$word-count$ words` in a header-includes
LaTeX command.

## Filter naming convention

Files in `filters/` follow three patterns, each with a distinct role:

- `NN-<name>.lua` — **document-scope filters** (operate on `Pandoc`).
  Numeric prefix encodes load order via the `Makefile` glob; lower
  numbers run first. Used for metadata transforms (cover style, draft
  watermark, anonymity, todos, glossary, frontmatter, authors,
  wordcount).
- `<name>.lua` (no prefix) — **block-scope filters** (operate on
  `CodeBlock`/other AST nodes). Order between siblings does not matter
  because each only matches its own fence class. Used for the
  diagram backends (`mermaid`, `plantuml`, `d2`, `graphviz`) and CSV
  tables.
- `_<name>.lua` — **shared modules** loaded via `require()` from
  sibling filters; excluded from the default `$(FILTERS)` glob in
  `Makefile` so Pandoc never invokes them as filters directly. Used
  for `_meta.lua`, `_diagram.lua`, and the on-demand
  `_collect-citations.lua`.

## YAML metadata convention

Filters read configuration from `src/00-metadata.md` in one of two
shapes. Pick the shape that matches the filter's complexity:

- **Top-level keys** for single-toggle behaviour. The filter has one
  boolean (or one short string) gate, and grouping it under a sub-map
  would just add a layer of indirection. Used by:

  | Key                                                | Filter                       |
  |----------------------------------------------------|------------------------------|
  | `draft:`, `draft-text:`                            | `filters/02-draft.lua`       |
  | `anonymous:`                                       | `filters/03-anonymous.lua`   |
  | `dedication:`, `acknowledgements:`, `declaration:` | `filters/06-frontmatter.lua` |
  | `authors:`                                         | `filters/07-authors.lua`     |
  | `cover-style:`                                     | `filters/01-cover-style.lua` |

- **Namespaced sub-map** for multi-option filters. The filter has
  several related knobs that benefit from grouping. Used by:

  | Sub-map        | Filter                       |
  |----------------|------------------------------|
  | `wordcount.*`  | `filters/00-wordcount.lua`   |
  | `todos.*`      | `filters/04-todos.lua`       |
  | `glossary.*`   | `filters/05-glossary.lua`    |
  | `acronyms:`    | `filters/05-glossary.lua`    |

  The `acronyms:` key is itself a map of `KEY: Expansion` pairs, so the
  sub-map distinction is only meaningful for the `glossary.*` group.

When adding a new filter: if it has one knob, give it a top-level key
named after the feature (`draft:`). If it has two or more related
knobs, namespace them under a sub-map (`featurename.*`).
