# Introduction — broken mermaid

This fixture intentionally contains a malformed Mermaid block. Under
the default policy (DIAGRAM_FAIL_HARD unset) filters/_diagram.lua
should emit a visible red-box placeholder. With DIAGRAM_FAIL_HARD=1
the same path should kill the build with a clean stderr message (no
Lua position prefix). The assertion harness counts the literal
placeholder phrase in the LaTeX output, so this prose deliberately
does not repeat it.

```{.mermaid #fig:broken-mermaid caption="A deliberately malformed mermaid graph"}
graph TD
  A -->
```
