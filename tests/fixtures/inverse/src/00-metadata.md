---
title: "mkReport inverse-mode fixture"
subtitle: "exercises the inverse branches of toggleable filters"
author: "test"

# Exercise filters/01-cover-style.lua unknown-preset branch (stderr
# warn + fallback to explicit titlepage-* fields, all of which are
# unset — Eisvogel ships sensible defaults).
cover-style: nonexistent

# Exercise filters/06-frontmatter.lua Inlines branch (bare-scalar YAML).
# A literal block (`dedication: |`) would parse as MetaBlocks; this
# bare scalar parses as MetaInlines and must be wrapped in a Para by
# as_blocks. The token "barededitoken" is grep-asserted in check-inverse.
dedication: "barededitoken"

# Exercise filters/04-todos.lua delete branch.
todos:
  mode: hide
  types: [todo]

# Exercise filters/05-glossary.lua append branch + acronym record/render
# code paths. The second acronym UNUSEDACRO is intentionally NEVER used
# in body prose, so only-used:false is needed for it to appear in the
# appended glossary — that's the branch the test gates.
acronyms:
  HIDE: Hide-Mode Demo
  UNUSEDACRO: An Acronym That Body Prose Never Mentions
glossary:
  append: true
  title: "Glossary"
  only-used: false

# Exercise filters/00-wordcount.lua include-references, include-appendix,
# and exclude-sections branches. include-* widen the word count beyond
# the default body-prose-only behaviour; exclude-sections suppresses the
# heading whose identifier matches.
wordcount:
  show: false
  limit: 10
  strict: false
  include-references: true
  include-appendix: true
  exclude-sections: [sec:excluded]
---
