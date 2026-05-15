# Discussion

Cross-references work transparently across all four diagram backends.
A reference to the class model in [@fig:mermaid-class], the component
view in [@fig:puml-comp], the system architecture in [@fig:d2-system],
and the dependency graph in [@fig:gv-deps] each renders as a
hyperlinked figure number; pandoc-crossref renumbers them
automatically and the PDF links each one back to the figure.

## Authoring helpers

Inline review markers exercise `filters/04-todos.lua`. Spans tagged
`{.todo}` ([revisit this paragraph]{.todo}), `{.fixme}` ([replace
placeholder]{.fixme}), and `{.cite-needed}` ([find canonical
reference]{.cite-needed}) appear as coloured highlights in `highlight`
mode and disappear entirely in `hide` mode. The `todo-count` metadata
field exposes the running count to templates.

First use of an acronym defined under `acronyms:` is expanded by
`filters/05-glossary.lua`: an API call (so API alone afterwards) and
DDD principles (then DDD) read naturally without manual
parenthesisation. Setting `glossary.append: true` adds an unnumbered
glossary section automatically.
