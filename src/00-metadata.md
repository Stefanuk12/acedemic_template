---
# ---- Document identity ----
title: "Report Title"
subtitle: "Optional subtitle"
# `author:` is the simple form; `authors:` (below) is the structured
# form. filters/07-authors.lua reads `authors:` and rewrites `author:`
# accordingly, so leave the bare scalar in place for fallback / single-
# author drafts that don't want affiliations.
author: "Your Name"
# Demonstrates the structured authors form. Drop or comment this block
# to fall back to the bare `author:` scalar above.
authors:
  - name: "Your Name"
    affiliation: "Your Department, Your Institution"
    email: "you@example.edu"
    orcid: "0000-0000-0000-0000"
    corresponding: true
date: \today

abstract: |
  This template demonstrates how a Markdown→PDF pipeline can produce a polished academic report with cover page, table of contents, list of figures, citations, and cross-references — all from plain Markdown sources. The body of this
  document is a placeholder; structure, prose, and analysis must be
  your own.

# ---- Eisvogel template options ----
titlepage: true

# Cover-page colour preset (filters/01-cover-style.lua).
# Available: navy, burgundy, forest, slate, crimson, plain.
# Set to "custom" (or comment out) and uncomment the four explicit
# titlepage-* fields below to manage colours by hand.
cover-style: navy

# Manual colour overrides — only used if cover-style is unset / "custom".
# titlepage-color: "1F4E79"
# titlepage-text-color: "FFFFFF"
# titlepage-rule-color: "FFFFFF"
# titlepage-rule-height: 2

# Article-style (sections 1, 2, 3 …). Set `book: true` for chapter-style,
# but note that scrbook drops the `abstract` environment, so you'd need
# to remove the abstract field above too.
book: false

# ---- Layout ----
classoption:
  - 11pt
  - a4paper
  - oneside
geometry: margin=2.5cm
linestretch: 1.15

# ---- Eisvogel niceties ----
table-use-row-colors: true
code-block-font-size: \footnotesize

# ---- Draft mode (filters/02-draft.lua) ----
# When true, every page gets a faint diagonal "DRAFT" watermark.
# The template ships with draft:true so the watermark code path is
# exercised on every CI build; flip to false for the final submission.
draft: true
draft-text: "DRAFT"

# ---- Anonymous mode (filters/03-anonymous.lua) ----
# When true, replaces the author with "Anonymous" on the cover and
# in any header/footer that reads from the author field. Useful for
# blind-review submissions. Filters run 02 → 03 → 07; with the
# structured `authors:` list above, 07-authors.lua will overwrite the
# anonymisation, so the visible cover still shows the real author.
# Setting `anonymous: true` here keeps 03-anonymous.lua's main branch
# under test on every CI build.
anonymous: true

# ---- Word count (filters/00-wordcount.lua) ----
# Display the count on the cover and configure what's included.
# Defaults follow common UK academic conventions: only body prose
# is counted. Flip any include-* flag to widen the scope. Use
# exclude-sections to skip specific sections by their heading id.
# Set `limit` to enforce a word ceiling — the build will warn (or
# fail with `strict: true`) if the count exceeds it.
# The formatted count is also exposed as `word-count` for use in
# custom template snippets.
wordcount:
  show: true
  include-cover:       false   # title, subtitle, author, abstract
  include-references:  false   # everything after # References / # Bibliography
  include-appendix:    false   # everything after \appendix
  include-citations:   false   # in-text [@key] citations
  include-quotations:  false   # block quotes (BlockQuote)
  exclude-sections: []         # e.g. [sec:methods, sec:limitations]
  # A generous default so CI exercises the enforce_limit code path
  # without actually tripping it for the sample document. Set to your
  # real ceiling (e.g. 5000) for the final submission.
  limit: 50000
  strict: false

# ---- TODO highlights (filters/04-todos.lua) ----
# Author with bracketed-span syntax:
#   [needs rewriting]{.todo}
#   [missing figure]{.fixme}
#   [add citation]{.cite-needed}
todos:
  mode: highlight   # highlight | hide
  types: [todo, fixme, cite-needed]

# ---- Frontmatter pages (filters/06-frontmatter.lua) ----
# Each of these is optional; any combination that is present is emitted
# between the cover and the TOC, in the order shown. The sample values
# below keep all three branches under test on every CI build — replace
# with your own text or comment out the keys you don't need.
dedication: |
  For everyone who reads the source before reading the PDF.
acknowledgements: |
  Thanks to the maintainers of Pandoc, Eisvogel, and pandoc-crossref —
  the heavy lifting on this template happens upstream.
declaration: |
  I declare that this work is my own and that any sources have been
  appropriately cited.

# ---- Acronyms / glossary (filters/05-glossary.lua) ----
# First use of each key gets expanded to "Expansion (KEY)"; later uses
# remain "KEY". Acronyms inside Code/CodeBlock are not expanded.
acronyms:
  API: Application Programming Interface
  DDD: Domain-Driven Design
  MVC: Model-View-Controller
glossary:
  append: false       # append a glossary section at the end of the doc
  title: "Glossary"
  only-used: true     # only list acronyms that actually appeared

# ---- Auto-generated lists ----
toc: true
toc-depth: 3
lof: true

# ---- pandoc-crossref ----
linkReferences: true
nameInLink: true

# ---- Hyperlink colours ----
colorlinks: true
linkcolor: NavyBlue
urlcolor: NavyBlue
citecolor: NavyBlue
---
