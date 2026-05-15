# Broken plantuml

PlantUML is forgiving about syntax errors at the diagram level (it
renders an error image and exits 0), so we trip filters/plantuml.lua's
failure branch via filename mismatch instead: a leading `@startuml
custom_name` directive makes plantuml write `custom_name.svg` rather
than `<hash>.svg`, so the `D.file_exists(svg)` check fails and both
the `[plantuml] plantuml failed for diagram <hash>` stderr line and
the standard red-box placeholder fire. The assertion harness counts
the placeholder phrase in the LaTeX output, so this prose deliberately
does not repeat it.

```{.plantuml #fig:broken-plantuml caption="A deliberately misnamed plantuml graph"}
@startuml deliberately_misnamed_output
class A
@enduml
```
