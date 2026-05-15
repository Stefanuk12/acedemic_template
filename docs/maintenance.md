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
the SRI hash in `flake.nix:harvardCsl` drifts. `nix build` then fails
with `hash mismatch in fixed-output derivation`. To bump manually:

```sh
nix hash convert --hash-algo sha256 --to sri \
  "$(nix-prefetch-url https://raw.githubusercontent.com/citation-style-language/styles/master/harvard-cite-them-right.csl)"
# paste the sha256-... value into flake.nix:harvardCsl
```

(An automated weekly bump workflow used to live at
`.github/workflows/bump-csl.yml`; it was removed because manual bumps
happen rarely enough that the cron cost wasn't justified. Re-add it
if upstream CSL churn becomes an issue.)

## Diagram cache

Render results live in `build/diagrams/<hash>.{src,svg,pdf}`. Hashes
are content-derived so unchanged diagrams are reused across builds.

When you delete or substantially edit a diagram, the old hash entries
linger until you clean. Two options:

- `make clean` — nuke `build/` entirely.
- `make gc-diagrams` — re-build once with manifest tracking and prune
  only the orphan hashes. Faster on large documents.

## CI

The `Build` workflow runs on push, PR, release, and manual dispatch.
Two stage-0 jobs race in parallel (a failure in either fails the
workflow), then a stage-1 job builds release-only secondary artefacts:

1. `proofread` — `make proofread` wraps `typecheck`, `check-refs`,
   `spellcheck`, and every `check-*` fixture target in cheap-to-
   expensive order, failing fast.
2. `build` — one `nix build` invocation realises
   `packages.<system>.default` plus the three `mkReport-*` flake
   checks in parallel, then a near-instant `nix flake check` for
   lib / devShell / app metadata. Uploads the PDF as the `report-pdf`
   artefact.
3. `release-artefacts` (release events only, gated on the two above
   succeeding) — downloads the PDF from the `build` job, runs
   `make html docx`, and attaches all three to the GitHub Release.

Linux-only — the flake builds the same expressions on darwin and the
codebase has no platform-specific paths, so the macOS leg was
removed. Consumers on macOS exercise the darwin code path on their
first `nix build`.

A separate `Check links` workflow runs weekly (Monday 12:00 UTC) to
HEAD every URL in body + bib. It's a sanity check on link rot, not
gated by commits.

## Pre-commit hooks

Local pre-commit runs only fast checks:

- `pre-commit` (every commit): trailing whitespace, line endings, YAML
  well-formedness, LuaLS on changed `filters/*.lua`.
- `pre-commit` (pre-push): `make check-refs`. The full PDF build is
  too slow for a push gate; CI is the source of truth there.
