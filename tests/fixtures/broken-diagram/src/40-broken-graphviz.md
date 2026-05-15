# Broken graphviz

The body of this fence is intentionally invalid graphviz/dot syntax
(edge with no target). `dot` exits non-zero on parse errors, so
filters/graphviz.lua's failure branch fires: stderr gains a
`[graphviz] dot failed for diagram <hash>` line and the default
policy renders the standard red-box placeholder for this backend.
The assertion harness counts the placeholder phrase in the LaTeX
output, so this prose deliberately does not repeat it.

```{.dot #fig:broken-graphviz caption="A deliberately malformed graphviz graph"}
digraph G {
  A ->
}
```
