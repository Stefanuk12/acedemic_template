```{=latex}
\appendix
```

# Supporting material

Sections below this point are lettered (Appendix A, B, ...) instead of
numbered, courtesy of LaTeX's `\appendix` command above.

## Build environment

The build is reproducible via the project flake. See `flake.nix` and
`Makefile` for exact tool versions.

## Diagram source

All diagrams are authored in fenced code blocks within `src/*.md` and
rendered by Lua filters at build time (`filters/mermaid.lua`,
`filters/plantuml.lua`).
