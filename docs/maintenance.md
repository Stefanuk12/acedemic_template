# Maintenance

## Bumping pinned versions

Everything is pinned via `flake.lock`. To bump:

```sh
nix flake update                # all inputs
nix flake update eisvogel       # just the LaTeX template
nix flake update pandoc-lua-types
git commit flake.lock
```

To target a specific eisvogel tag, edit `flake.nix`:

```nix
eisvogel.url = "github:Wandmalfarbe/pandoc-latex-template/v3.5.0";
```

The Cite Them Right CSL is fetched at flake-eval time as a fixed-output
derivation. Upstream doesn't tag releases, so when they change the file
the SRI hash in `flake.nix:harvardCsl` drifts. A scheduled GitHub
Actions workflow (`.github/workflows/bump-csl.yml`) checks weekly and
opens a PR with the new hash automatically. To bump manually:

```sh
nix hash convert --hash-algo sha256 --to sri \
  "$(nix-prefetch-url https://raw.githubusercontent.com/citation-style-language/styles/master/harvard-cite-them-right.csl)"
# paste the sha256-... value into flake.nix:harvardCsl
```

## Diagram cache

Render results live in `build/diagrams/<hash>.{src,svg,pdf}`. Hashes
are content-derived so unchanged diagrams are reused across builds.

When you delete or substantially edit a diagram, the old hash entries
linger until you clean. Two options:

- `make clean` — nuke `build/` entirely.
- `make gc-diagrams` — re-build once with manifest tracking and prune
  only the orphan hashes. Faster on large documents.

## CI

The `Build` workflow runs on push, PR, release, and manual dispatch:

1. `make typecheck` — LuaLS against the bundled EmmyLua stubs.
2. `make check-refs` — every cited key resolves, no orphan bib entries.
3. `nix build` — the same code path consumer flakes use via `mkReport`.
4. `nix flake check` — exercises the `tests/fixtures/minimal` fixture
   to catch breakage in the public `mkReport` API.
5. `make html docx` — non-fatal; produced when possible.

Builds run on both `ubuntu-latest` and `macos-latest`. PDF artefacts
are uploaded from the Linux runner only.

## Pre-commit hooks

Local pre-commit runs only fast checks:

- `pre-commit` (every commit): trailing whitespace, line endings, YAML
  well-formedness, LuaLS on changed `filters/*.lua`.
- `pre-commit` (pre-push): `make check-refs`. The full PDF build is
  too slow for a push gate; CI is the source of truth there.
