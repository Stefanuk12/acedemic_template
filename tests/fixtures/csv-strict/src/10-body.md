# Introduction

This fixture deliberately references a non-existent CSV file so the
io.open path in filters/csv.lua trips its failure_placeholder. Under
the default policy (CSV_FAIL_HARD unset) the build still succeeds
and renders a red-box placeholder; with CSV_FAIL_HARD=1 the same
path escalates to a hard error and kills the build with a clean
"[csv] render failed for …" stderr message (no Lua position prefix,
thanks to error(..., 0)).

```{.csv #tbl:missing file=data/this-file-does-not-exist.csv caption="A non-existent file"}
```
