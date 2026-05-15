# Broken d2

The body of this fence is intentionally invalid d2 syntax. The `d2`
CLI exits non-zero on parse errors, so filters/d2.lua's failure branch
fires: stderr gains a `[d2] d2 failed for diagram <hash>` line and the
default policy renders the standard red-box placeholder for this
backend. The assertion harness counts the placeholder phrase in the
LaTeX output, so this prose deliberately does not repeat it.

```{.d2 #fig:broken-d2 caption="A deliberately malformed d2 graph"}
shape: { rectangle: { rectangle: { shape: invalid }}}}}}}}
```
