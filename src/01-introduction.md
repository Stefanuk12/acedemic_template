# Introduction

Edit the files in `src/` to write the report. Build with `make`. New
sections are just new files — they are concatenated alphabetically, so
prefix names like `15-architecture.md` to slot in between existing
files.

This template demonstrates: Mermaid, PlantUML, D2, and Graphviz
diagrams; Harvard in-text citations with an auto-generated reference
list; figure, table, equation, and listing cross-references with
matching auto-generated lists; CSV-driven tables; multi-author
metadata with affiliations; optional front matter (dedication,
acknowledgements, declaration); and a lettered appendix.

The build is fully reproducible thanks to a Nix flake dev shell that
pins every tool — pandoc, xelatex, mermaid-cli, plantuml, d2,
graphviz — to specific versions.

## How to cite

Two styles of in-text citation:

- Parenthetical: design under constraint shapes every engineered
  system [@bass2021].
- In-prose: @kruchten1995 introduced the 4+1 view model.

Multiple sources in one bracket: [@bass2021; @fowler2014]. Page
numbers: [@bass2021, p. 42]. The full reference list appears
automatically at the end of the document.

## How to cross-reference figures

Each diagram fence can carry an identifier. Reference it later with
`[@fig:label]` and pandoc-crossref will substitute the figure number
(and link back to it in the PDF).
