# Build pipeline: Markdown (+ Mermaid + PlantUML) -> PDF via pandoc + LaTeX.
# Includes: Harvard citations (citeproc + CSL), figure/table cross-references
# (pandoc-crossref), automatic List of Figures, and an appendix.
#
# Sources are split across multiple files in `src/`. They are concatenated
# alphabetically; prefix with numbers (e.g. 15-foo.md) to control ordering.
#
# Designed to run inside the flake dev shell (`nix develop`).
#
# All paths below are overridable from the environment so the same
# Makefile can be invoked against this template's bundled assets from
# a downstream consumer flake (see flake.nix:lib.mkReport). The dev
# shell exports EISVOGEL_DIR / PANDOC_LUA_TYPES_DIR pointing into the
# nix store; the symlinks created by the shellHook keep the in-tree
# defaults working without any env wiring.

SRC_DIR       ?= src
OUT_DIR       ?= build
FILTERS_DIR   ?= filters
REFS_DIR      ?= refs
TEMPLATES_DIR ?= $(if $(EISVOGEL_DIR),$(EISVOGEL_DIR),templates/eisvogel)
TYPES_DIR     ?= $(if $(PANDOC_LUA_TYPES_DIR),$(PANDOC_LUA_TYPES_DIR),types)

SRCS     := $(sort $(wildcard $(SRC_DIR)/*.md))
OUT      ?= $(OUT_DIR)/report.pdf
FILTERS  := $(sort $(filter-out $(FILTERS_DIR)/_%.lua,$(wildcard $(FILTERS_DIR)/*.lua)))
# Consumer-supplied filters layered on top of the bundled set. Pass as
# a space-separated list of .lua paths, or as a directory (every
# *.lua file in it is picked up, _-prefixed files excluded as usual).
# Order: bundled filters run first, then EXTRA_FILTERS in given order.
EXTRA_FILTERS ?=
_extra_files := $(foreach f,$(EXTRA_FILTERS),$(if $(wildcard $(f)/.),$(filter-out $(f)/_%.lua,$(wildcard $(f)/*.lua)),$(f)))
FILTERS += $(_extra_files)
ENGINE   ?= xelatex

BIB      ?= $(REFS_DIR)/refs.bib
CSL      ?= $(REFS_DIR)/harvard.csl
# Upstream CTR12 file; we patch it on download to approximate CTR13.
# Swap this URL for the official CTR13 once Bloomsbury / O'Brien publish it.
CSL_URL  := https://raw.githubusercontent.com/citation-style-language/styles/master/harvard-cite-them-right.csl

# Eisvogel pandoc LaTeX template. Resolved from $(TEMPLATES_DIR), which
# defaults to the dev-shell symlink at templates/eisvogel (pointing into
# the nix store). To upgrade, bump the eisvogel input in flake.nix.
#
# We use the multi-file (partials) variant because the upstream repo
# does NOT track the standalone eisvogel.latex in its working tree
# (that's only generated at release time and bundled into the .tar.gz).
# Pandoc resolves the partials relative to the template path, so this
# works identically to the single-file version.
TEMPLATE ?= $(TEMPLATES_DIR)/template-multi-file/eisvogel.latex

# Diagram filters read this from the env (filters/_diagram.lua) so the
# cache lives next to the rest of the build artefacts.
export DIAGRAM_CACHE_DIR := $(OUT_DIR)/diagrams

PANDOC_OPTS := \
  --from=markdown+raw_tex+tex_math_dollars+pipe_tables+grid_tables+fenced_code_attributes \
  --pdf-engine=$(ENGINE) \
  --template=$(TEMPLATE) \
  --filter=pandoc-crossref \
  --citeproc \
  --bibliography=$(BIB) \
  --csl=$(CSL) \
  $(addprefix --lua-filter=,$(FILTERS)) \
  --number-sections \
  --toc \
  --toc-depth=3 \
  --lof \
  --lot \
  --highlight-style=tango \
  -M link-citations=true \
  -M reference-section-title="References" \
  -M figureTitle="Figure" \
  -M tableTitle="Table" \
  -M listingTitle="Listing" \
  -M figPrefix="Fig." \
  -M tblPrefix="Tbl." \
  -M eqnPrefix="Eq." \
  -M lstPrefix="Lst." \
  -M secPrefix="§"

.PHONY: all build-dir clean watch open typecheck html docx epub review stats submit arxiv diff check-refs check-links check-inverse check-diagram-failure check-wordcount-strict check-csv-strict check-anonymous spellcheck spellcheck-add proofread ci-local gc-diagrams

all: $(OUT)

$(OUT): $(SRCS) $(FILTERS) $(BIB) $(CSL) $(TEMPLATE) | build-dir
	pandoc $(PANDOC_OPTS) -o $@ $(SRCS)
	@echo "✓ wrote $@"

build-dir:
	@mkdir -p $(OUT_DIR)/diagrams $(REFS_DIR)

# Bail with a clear hint if the eisvogel template isn't reachable.
# Inside the dev shell this is provided via the templates/eisvogel
# symlink that shellHook creates. Outside the dev shell, the user has
# to point TEMPLATES_DIR (or EISVOGEL_DIR) at a checkout themselves.
$(TEMPLATE):
	@if [ ! -f "$@" ]; then \
	  echo "✗ eisvogel template not found at $(TEMPLATE)"; \
	  echo "  Enter the dev shell (\`nix develop\`) or set TEMPLATES_DIR=/path/to/eisvogel."; \
	  exit 1; \
	fi

# Fetch the upstream "Cite Them Right" CSL and patch it to approximate
# the 13th edition. The main documented CTR13 difference encodable in
# CSL is the removal of place-of-publication for books and similar
# source types. Other CTR13 changes (sentence case in references,
# AI-source guidance, paragraph numbers for online sources without
# pages) are not currently covered.
$(CSL):
	@mkdir -p $(REFS_DIR)
	@echo "↓ fetching upstream Cite Them Right CSL"
	@curl -sLf $(CSL_URL) -o $@.tmp
	@echo "✎ patching for CTR13 (removing publisher-place)"
	@sed -i '/<text variable="publisher-place"\/>/d' $@.tmp
	@sed -i 's|<title>Cite Them Right 12th edition (author-date/Harvard)</title>|<title>Cite Them Right 13th edition (author-date/Harvard) — local patch</title>|' $@.tmp
	@mv $@.tmp $@
	@echo "✓ wrote $@"

clean:
	rm -rf $(OUT_DIR)

# Static type-check every filter in `filters/` against the EmmyLua
# annotations in `types/*.lua`. Uses lua-language-server (LuaLS) in
# CLI check mode against the project root so it picks up .luarc.json
# (workspace.library = ["types"]) automatically. Files marked with
# `---@meta` (i.e. types/*.lua) are loaded as definitions and skipped
# during the actual check pass.
# In-tree only: relies on .luarc.json in CWD to set workspace.library.
# Consumers don't need to typecheck the bundled filters — that's done
# in this template's CI before release.
typecheck: $(FILTERS) $(TYPES_DIR)/pandoc.lua
	@command -v lua-language-server >/dev/null || { echo "lua-language-server not found (in dev shell?)"; exit 1; }
	@mkdir -p $(OUT_DIR)/luals-log
	@lua-language-server --check=. --logpath=$(OUT_DIR)/luals-log --checklevel=Warning
	@echo "✓ all filters type-check clean"

watch:
	@command -v entr >/dev/null || { echo "entr not found (in dev shell?)"; exit 1; }
	@echo "watching $(SRCS) $(FILTERS) $(BIB) — Ctrl-C to stop"
	@echo $(SRCS) $(FILTERS) $(BIB) | tr ' ' '\n' | entr -c $(MAKE) all

open: $(OUT)
	@xdg-open $(OUT) >/dev/null 2>&1 &

# ---- Multi-format outputs ----
# Build options shared with the PDF target, minus the LaTeX-specific
# things (template, pdf-engine). Each format keeps citation processing,
# crossrefs, and all Lua filters.
PANDOC_COMMON := \
  --from=markdown+raw_tex+tex_math_dollars+pipe_tables+grid_tables+fenced_code_attributes \
  --filter=pandoc-crossref \
  --citeproc \
  --bibliography=$(BIB) \
  --csl=$(CSL) \
  $(addprefix --lua-filter=,$(FILTERS)) \
  --number-sections \
  --toc \
  --toc-depth=3 \
  --highlight-style=tango \
  -M link-citations=true \
  -M reference-section-title="References" \
  -M figureTitle="Figure" \
  -M tableTitle="Table" \
  -M figPrefix="Fig." \
  -M tblPrefix="Tbl." \
  -M eqnPrefix="Eq." \
  -M lstPrefix="Lst." \
  -M secPrefix="§"

$(OUT_DIR)/report.html: $(SRCS) $(FILTERS) $(BIB) $(CSL) | build-dir
	pandoc $(PANDOC_COMMON) --standalone --embed-resources --mathjax -o $@ $(SRCS)
	@echo "✓ wrote $@"

$(OUT_DIR)/report.docx: $(SRCS) $(FILTERS) $(BIB) $(CSL) | build-dir
	pandoc $(PANDOC_COMMON) -o $@ $(SRCS)
	@echo "✓ wrote $@"

$(OUT_DIR)/report.epub: $(SRCS) $(FILTERS) $(BIB) $(CSL) | build-dir
	pandoc $(PANDOC_COMMON) -o $@ $(SRCS)
	@echo "✓ wrote $@"

html: $(OUT_DIR)/report.html
docx: $(OUT_DIR)/report.docx
epub: $(OUT_DIR)/report.epub

# ---- Stats ----
# Snapshot of where the document is right now: word count (using the
# active wordcount config), figures by backend, citations, TODOs, files.
# Body content only — src/00-metadata.md is excluded from grep counts
# so its example syntax in comments doesn't pad the numbers.
BODY_SRCS := $(filter-out $(SRC_DIR)/00-metadata.md,$(SRCS))
stats:
	@echo "=== Source statistics ==="
	@printf "  %-25s %s\n" "Markdown source files:" "$$(echo $(SRCS) | wc -w)"
	@printf "  %-25s %s\n" "Mermaid figures:"   "$$(grep -hcF '```{.mermaid'  $(BODY_SRCS) | awk '{s+=$$1} END{print s+0}')"
	@printf "  %-25s %s\n" "PlantUML figures:"  "$$(grep -hcF '```{.plantuml' $(BODY_SRCS) | awk '{s+=$$1} END{print s+0}')"
	@printf "  %-25s %s\n" "D2 figures:"        "$$(grep -hcF '```{.d2'       $(BODY_SRCS) | awk '{s+=$$1} END{print s+0}')"
	@printf "  %-25s %s\n" "Graphviz figures:"  "$$(grep -hcE '^```\{\.(dot|graphviz)' $(BODY_SRCS) | awk '{s+=$$1} END{print s+0}')"
	@printf "  %-25s %s\n" "Distinct citations:" "$$(grep -hoE '@[a-zA-Z][a-zA-Z0-9_:.-]*' $(BODY_SRCS) | sort -u | wc -l)"
	@printf "  %-25s %s\n" "TODO markers:"      "$$(grep -hoE '\{\.(todo|fixme|cite-needed)\}' $(BODY_SRCS) | wc -l)"
	@printf "  %-25s %s\n" "Bibliography entries:" "$$(grep -hcE '^@[a-zA-Z]+\{' $(BIB) 2>/dev/null || echo 0)"
	@echo
	@echo "=== Word count (active wordcount.* config) ==="
	@pandoc --lua-filter=$(FILTERS_DIR)/00-wordcount.lua $(SRCS) -t markdown --standalone 2>/dev/null \
	  | awk '/^---$$/{p=!p; next} p && /^word-count:/{sub(/^word-count: */,""); print "  Filter-counted words:    " $$0; exit}'

# ---- Submission package ----
# Bundles the rendered PDF and clean source into a single zip the
# student / author can hand in. Excludes build artefacts, .direnv/,
# .git/, and the (symlinked) eisvogel template + lua type stubs.
# Anything not present in the consumer's tree is silently skipped.
submit: $(OUT)
	@rm -rf $(OUT_DIR)/submit $(OUT_DIR)/submit.zip
	@mkdir -p $(OUT_DIR)/submit
	@cp $(OUT) $(OUT_DIR)/submit/
	@for d in $(SRC_DIR) $(REFS_DIR) $(FILTERS_DIR); do \
	  [ -d "$$d" ] && cp -rL "$$d" $(OUT_DIR)/submit/ ; \
	done
	@for f in Makefile flake.nix flake.lock README.md; do \
	  [ -f "$$f" ] && cp "$$f" $(OUT_DIR)/submit/ ; \
	done
	@cd $(OUT_DIR) && zip -qr submit.zip submit
	@echo "✓ $(OUT_DIR)/submit.zip ($$(du -h $(OUT_DIR)/submit.zip | cut -f1))"

# ---- arXiv-ready bundle ----
# Produces $(OUT_DIR)/arxiv.tar.gz containing the rendered PDF, the
# pandoc-intermediate LaTeX (so arXiv can rebuild from source if PDF-
# only submission is not accepted), the bib, the rendered diagram
# cache, and a one-line REBUILD note. Layout:
#
#   arxiv/
#     report.pdf               -- the rendered deliverable
#     report.tex               -- pandoc-intermediate LaTeX
#     refs.bib                 -- bibliography
#     diagrams/<hash>.pdf      -- pre-rendered diagram PDFs (referenced
#                                 by report.tex via \includegraphics)
#     REBUILD.md               -- one-liner: `xelatex report.tex` etc.
#
# Intermediate .tex is produced WITHOUT --template (raw pandoc output),
# so arXiv's compiler isn't forced through Eisvogel's preamble. If you
# need Eisvogel-styled .tex, set TEMPLATE=… explicitly in the env.
arxiv: $(OUT)
	@rm -rf $(OUT_DIR)/arxiv $(OUT_DIR)/arxiv.tar.gz
	@mkdir -p $(OUT_DIR)/arxiv/diagrams
	@cp $(OUT) $(OUT_DIR)/arxiv/report.pdf
	@cp $(BIB) $(OUT_DIR)/arxiv/refs.bib
	@if [ -d "$(OUT_DIR)/diagrams" ]; then \
	  find "$(OUT_DIR)/diagrams" -maxdepth 1 -name '*.pdf' -exec cp {} $(OUT_DIR)/arxiv/diagrams/ \; ; \
	fi
	@pandoc \
	  --from=markdown+raw_tex+tex_math_dollars+pipe_tables+grid_tables+fenced_code_attributes \
	  --to=latex \
	  --standalone \
	  --pdf-engine=$(ENGINE) \
	  --filter=pandoc-crossref \
	  --citeproc --bibliography=$(BIB) --csl=$(CSL) \
	  $(addprefix --lua-filter=,$(FILTERS)) \
	  --number-sections \
	  -M link-citations=true \
	  -M reference-section-title="References" \
	  -o $(OUT_DIR)/arxiv/report.tex $(SRCS)
	@printf 'Rebuild:\n\n    %s -interaction=nonstopmode report.tex\n    %s -interaction=nonstopmode report.tex    # second pass for refs\n\nDiagrams are pre-rendered; do not edit `diagrams/*.pdf`.\nThe canonical source is the project repo from which this bundle was generated.\n' \
	  $(ENGINE) $(ENGINE) > $(OUT_DIR)/arxiv/REBUILD.md
	@cd $(OUT_DIR) && tar czf arxiv.tar.gz arxiv/
	@echo "✓ $(OUT_DIR)/arxiv.tar.gz ($$(du -h $(OUT_DIR)/arxiv.tar.gz | cut -f1))"

# ---- Line-numbered review build ----
# Builds the PDF with every body line numbered for supervisor / referee
# comments. Reuses the default PANDOC_OPTS so all filters and crossref
# behaviour stay identical; injects the `lineno` package via the
# `header-includes` metadata channel (NOT --include-in-header, which
# silently suppresses pandoc-crossref's own header injection — that
# breaks the `codelisting` \newfloat used by lstPrefix-prefixed code
# blocks).
#
# `header-includes` accepts a single string; the embedded `\linenumbers`
# turns numbering on document-wide. Code blocks and floats remain
# unnumbered thanks to lineno's default behaviour of skipping non-text
# environments.
#
# Output: $(OUT_DIR)/report-review.pdf — separate file so the regular
# `make` build isn't disturbed.
$(OUT_DIR)/report-review.pdf: $(SRCS) $(FILTERS) $(BIB) $(CSL) $(TEMPLATE) | build-dir
	@meta=$$(mktemp --suffix=.yaml); \
	  printf 'header-includes: |\n  ```{=latex}\n  \\usepackage{lineno}\n  \\linenumbers\n  ```\n' > $$meta; \
	  pandoc $(PANDOC_OPTS) --metadata-file=$$meta -o $@ $(SRCS); rc=$$?; \
	  rm -f $$meta; \
	  if [ $$rc -ne 0 ]; then exit $$rc; fi
	@echo "✓ wrote $@"

review: $(OUT_DIR)/report-review.pdf

# ---- Bibliography hygiene ----
# Two gates against refs.bib:
#
# 1. Cited-vs-defined diff. Walks the AST with a one-shot Lua filter
#    to collect every cited key, extracts every defined key from
#    refs.bib, and reports:
#      - cited but not defined  → SEVERE (will render as ?)
#      - defined but not cited  → warning (orphan; harmless)
#
# 2. Per-entry-type required-field gate. Each bib entry must carry the
#    minimal metadata its type implies, otherwise the rendered
#    references list shows ?, n.d., or "Untitled" placeholders. The
#    rules below are conservative — they match what citeproc + Cite
#    Them Right need to produce a valid reference.
#
# The required-fields awk script reads refs.bib once and accumulates
# the field set per entry. At @<closing-brace> it checks the active
# rule set for the entry's type. Missing fields are reported as
# "<key> (<type>): missing <field>" — one line per omission.
check-refs:
	@cited=$$(mktemp); defined=$$(mktemp); fieldgaps=$$(mktemp); \
	  pandoc --lua-filter=$(FILTERS_DIR)/_collect-citations.lua $(SRCS) -t plain 2>$$cited 1>/dev/null; \
	  grep -hoE '^@[a-zA-Z]+\{[^,]+' $(BIB) | sed 's/^@[a-zA-Z]*{//' | sort -u > $$defined; \
	  awk ' \
	    BEGIN { IGNORECASE=1; \
	      req["article"]      = "author title journal year"; \
	      req["book"]         = "author title publisher year"; \
	      req["inbook"]       = "author title chapter publisher year"; \
	      req["incollection"] = "author title booktitle publisher year"; \
	      req["inproceedings"]= "author title booktitle year"; \
	      req["conference"]   = "author title booktitle year"; \
	      req["mastersthesis"]= "author title school year"; \
	      req["phdthesis"]    = "author title school year"; \
	      req["techreport"]   = "author title institution year"; \
	      req["manual"]       = "title year"; \
	      req["unpublished"]  = "author title note"; \
	      req["misc"]         = "author-or-editor title year"; \
	    } \
	    /^@[a-zA-Z]+\{/ { \
	      if (key != "") flush(); \
	      type = tolower($$0); sub(/^@/, "", type); sub(/\{.*/, "", type); \
	      key  = $$0; sub(/^@[a-zA-Z]+\{/, "", key); sub(/,.*$$/, "", key); \
	      fields = ""; next; \
	    } \
	    /^[[:space:]]*[a-zA-Z]+[[:space:]]*=/ { \
	      f = $$0; sub(/^[[:space:]]*/, "", f); sub(/[[:space:]]*=.*$$/, "", f); \
	      fields = fields " " tolower(f); \
	    } \
	    END { if (key != "") flush(); } \
	    function flush(   need, n, i, f) { \
	      if (!(type in req)) return; \
	      n = split(req[type], need, " "); \
	      for (i = 1; i <= n; i++) { \
	        f = need[i]; \
	        if (f == "author-or-editor") { \
	          if (index(fields, " author") == 0 && index(fields, " editor") == 0) \
	            print key " (" type "): missing author or editor"; \
	        } else if (index(fields, " " f) == 0) { \
	          print key " (" type "): missing " f; \
	        } \
	      } \
	    } \
	  ' $(BIB) > $$fieldgaps; \
	  missing=$$(comm -23 $$cited $$defined); \
	  orphan=$$(comm -13 $$cited $$defined); \
	  rc=0; \
	  if [ -n "$$missing" ]; then \
	    echo "✗ Citations without a matching bib entry:"; \
	    echo "$$missing" | sed 's/^/    /'; \
	    rc=1; \
	  fi; \
	  if [ -s $$fieldgaps ]; then \
	    echo "✗ Bib entries missing type-required fields:"; \
	    sed 's/^/    /' $$fieldgaps; \
	    rc=1; \
	  fi; \
	  if [ -n "$$orphan" ]; then \
	    echo "⚠ Bib entries that are never cited:"; \
	    echo "$$orphan" | sed 's/^/    /'; \
	  fi; \
	  if [ -z "$$missing" ] && [ ! -s $$fieldgaps ] && [ -z "$$orphan" ]; then \
	    echo "✓ all $$(wc -l < $$cited) citations resolve; all bib entries have type-required fields; no orphans"; \
	  elif [ -z "$$missing" ] && [ ! -s $$fieldgaps ]; then \
	    echo "✓ citations + bib fields clean (orphans listed above are advisory)"; \
	  fi; \
	  rm -f $$cited $$defined $$fieldgaps; \
	  exit $$rc

# ---- Shared check-* harness helpers ----
# Two shell functions every check-* target relies on:
#   count_eq <file> <pattern> <n> <description>   asserts grep -cF == n
#   count_ge <file> <pattern> <n> <description>   asserts grep -cF >= n
# Defined once here; each target prepends $(CHECK_HELPERS) instead of
# redefining the same two functions inline. `fail` is the shared rc
# accumulator each target initialises to 0 before sourcing the helpers.
#
# Note: $$ is Make's literal-$. Shell sees $1..$4 as positional args of
# the functions; grep -c always emits a count on stdout but exits 1 on
# zero matches, so we suppress that via `|| :` and fall back to 0 when
# the file/pattern reading fails entirely.
define CHECK_HELPERS
count_eq() { actual=$$(grep -cF "$$2" "$$1" 2>/dev/null || :); [ -z "$$actual" ] && actual=0; \
             if [ "$$actual" = "$$3" ]; then echo "  ✓ $$4 (count=$$3)"; \
             else echo "  ✗ $$4 (expected $$3 occurrences of '$$2', got $$actual)"; fail=1; fi; }; \
count_ge() { actual=$$(grep -cF "$$2" "$$1" 2>/dev/null || :); [ -z "$$actual" ] && actual=0; \
             if [ "$$actual" -ge "$$3" ]; then echo "  ✓ $$4 (count=$$actual ≥ $$3)"; \
             else echo "  ✗ $$4 (expected ≥ $$3 occurrences of '$$2', got $$actual)"; fail=1; fi; };
endef

# ---- Inverse-mode fixture build check ----
# Builds tests/fixtures/inverse to LaTeX and asserts the expected
# filter-output shape — verifies that hide-mode todos, glossary append,
# unknown cover-style fallback, the wordcount warn branch, csv io.open
# failure, csv empty-rows failure, and csv header=false all run.
#
# Several assertions are count-based (count_eq <file> <pattern> <n>),
# not just substring-presence — so a regression that still happens to
# emit the marker but the wrong number of times (e.g. csv failure path
# running twice when only one block should fail, or the wordcount
# warning firing on every pass) is caught.
#
# `nix flake check` ALSO builds this fixture (via mkReport-inverse) and
# proves it doesn't crash; this target additionally proves the inverse
# branches actually produced the right output.
check-inverse:
	@inv=tests/fixtures/inverse; \
	  out=$$(mktemp --suffix=.tex); \
	  err=$$(mktemp); \
	  pandoc \
	    --from=markdown+raw_tex+tex_math_dollars+pipe_tables+grid_tables+fenced_code_attributes \
	    --to=latex \
	    --template=$(TEMPLATE) \
	    --citeproc --bibliography=$$inv/refs/refs.bib --csl=$(CSL) \
	    $(addprefix --lua-filter=,$(FILTERS)) \
	    -M reference-section-title="References" \
	    -o $$out $$inv/src/*.md 2>$$err; rc=$$?; \
	  fail=0; assert() { if grep -qF "$$2" $$1; then echo "  ✓ $$3"; else echo "  ✗ $$3 (missing '$$2')"; fail=1; fi; }; \
	  refute() { if grep -qF "$$2" $$1; then echo "  ✗ $$3 (unexpected '$$2')"; fail=1; else echo "  ✓ $$3"; fi; }; \
	  $(CHECK_HELPERS) \
	  if [ $$rc -ne 0 ]; then \
	    echo "✗ pandoc failed to build the inverse fixture (rc=$$rc)"; \
	    cat $$err; rm -f $$out $$err; exit 1; \
	  fi; \
	  echo "Inverse-mode fixture assertions:"; \
	  assert    $$out "Glossary"            "glossary.append rendered a glossary heading"; \
	  refute    $$out "hidden marker"       "todos.hide deleted the [text]{.todo} span"; \
	  count_eq  $$out "CSV FAILED"        2 "two csv failure_placeholder blocks rendered (io.open + empty)"; \
	  count_eq  $$out "bodycellhf"        1 "csv header=false branch emitted first-row data into the table body"; \
	  count_eq  $$err "[cover-style]"     1 "unknown cover-style preset warned exactly once on stderr"; \
	  count_eq  $$err "[wordcount] WARNING" 1 "wordcount over-limit warned exactly once on stderr"; \
	  count_eq  $$err "[csv] cannot open" 1 "csv io.open failure logged exactly once on stderr"; \
	  count_eq  $$err "[csv] no rows parsed" 1 "csv empty-rows failure logged exactly once on stderr"; \
	  count_eq  $$out "barededitoken"        1 "06-frontmatter.lua Inlines branch (bare-scalar dedication) reached the rendered output"; \
	  count_eq  $$out "UNUSEDACRO"           1 "05-glossary.lua only-used:false branch listed an acronym never used in body prose"; \
	  count_eq  $$out "EXCLUDEDSECTIONTOKEN" 1 "wordcount.exclude-sections kept the heading body in the rendered output"; \
	  count_eq  $$out "APPENDIXSECTIONTOKEN" 1 "wordcount.include-appendix branch ran (appendix words counted; heading body still rendered)"; \
	  count_eq  $$out "RESUMEDBODYTOKEN"     1 "post-excluded section heading resumed body word-counting (still rendered)"; \
	  rm -f $$out $$err; \
	  if [ $$fail -ne 0 ]; then exit 1; fi; \
	  echo "✓ all inverse-mode assertions passed"

# ---- Broken-diagram failure-path checks ----
# Asserts diagram failure modes against tests/fixtures/broken-diagram,
# which ships one deliberately-malformed block per backend
# (mermaid, d2, plantuml, graphviz) in its own src/ file:
#
#   1. default policy (DIAGRAM_FAIL_HARD unset)    → build succeeds,
#      output contains exactly four "DIAGRAM FAILED" placeholders,
#      and stderr has each backend's `[<tag>]` failure log line.
#      This exercises every backend's `return nil` failure branch and
#      _diagram.lua's failure_placeholder path simultaneously.
#
#   2. strict policy (DIAGRAM_FAIL_HARD=1)         → pandoc exits
#      non-zero with a clean "[<tag>] render failed …" message
#      (no Lua position prefix, thanks to error(..., 0)). Run once
#      per backend, with that backend's broken source as the only
#      diagram input, so each backend's strict-mode branch is
#      independently verified.
check-diagram-failure:
	@bd=tests/fixtures/broken-diagram; \
	  isolated_cache=$$(mktemp -d); \
	  out=$$(mktemp --suffix=.tex); err=$$(mktemp); \
	  fail=0; \
	  $(CHECK_HELPERS) \
	  echo "Broken-diagram fixture assertions (default policy):"; \
	  DIAGRAM_CACHE_DIR=$$isolated_cache pandoc \
	    --from=markdown+raw_tex+tex_math_dollars+pipe_tables+grid_tables+fenced_code_attributes \
	    --to=latex --template=$(TEMPLATE) \
	    --citeproc --bibliography=$$bd/refs/refs.bib --csl=$(CSL) \
	    $(addprefix --lua-filter=,$(FILTERS)) \
	    -o $$out $$bd/src/*.md 2>$$err; rc=$$?; \
	  if [ $$rc -ne 0 ]; then \
	    echo "  ✗ default-policy build crashed (rc=$$rc); placeholder path is unreachable"; \
	    cat $$err; rm -rf $$isolated_cache $$out $$err; exit 1; \
	  fi; \
	  count_eq $$out "DIAGRAM FAILED"          4 "default policy: 4 placeholders rendered (one per backend)"; \
	  count_eq $$err "[mermaid] mmdc failed"   1 "[mermaid] failure branch logged exactly once"; \
	  count_eq $$err "[d2] d2 failed"          1 "[d2] failure branch logged exactly once"; \
	  count_eq $$err "[plantuml] plantuml failed" 1 "[plantuml] failure branch logged exactly once"; \
	  count_eq $$err "[graphviz] dot failed"   1 "[graphviz] failure branch logged exactly once"; \
	  echo "Broken-diagram fixture assertions (DIAGRAM_FAIL_HARD per backend):"; \
	  for spec in "mermaid:10-broken.md" "d2:20-broken-d2.md" "plantuml:30-broken-plantuml.md" "graphviz:40-broken-graphviz.md"; do \
	    tag=$${spec%%:*}; file=$${spec##*:}; \
	    : > $$err; \
	    DIAGRAM_CACHE_DIR=$$isolated_cache DIAGRAM_FAIL_HARD=1 pandoc \
	      --from=markdown+raw_tex+tex_math_dollars+pipe_tables+grid_tables+fenced_code_attributes \
	      --to=latex --template=$(TEMPLATE) \
	      --citeproc --bibliography=$$bd/refs/refs.bib --csl=$(CSL) \
	      $(addprefix --lua-filter=,$(FILTERS)) \
	      -o /dev/null $$bd/src/00-metadata.md $$bd/src/$$file 2>$$err; rc=$$?; \
	    if [ $$rc -eq 0 ]; then \
	      echo "  ✗ [$$tag] DIAGRAM_FAIL_HARD: pandoc exited 0; expected non-zero"; fail=1; \
	    else \
	      count_eq $$err "[$$tag] render failed" 1 "[$$tag] strict-mode error() fired once with clean message"; \
	    fi; \
	  done; \
	  rm -rf $$isolated_cache $$out $$err; \
	  if [ $$fail -ne 0 ]; then exit 1; fi; \
	  echo "✓ all diagram failure paths exercised (4 backends × default + strict)"

# ---- Wordcount strict-mode failure-path check ----
# Asserts that filters/00-wordcount.lua's strict-overflow path actually
# kills the build with a clean "[wordcount] N words exceeds limit of M"
# message. Mirrors the check-diagram-failure pattern: a tiny fixture
# whose body exceeds wordcount.limit:5 with strict:true; this target
# expects pandoc to exit non-zero on it.
#
# Count-based assertion: the strict-mode error must fire exactly once,
# not loop or get re-emitted by re-runs of the filter under crossref.
check-wordcount-strict:
	@wc=tests/fixtures/wordcount-strict; \
	  err=$$(mktemp); fail=0; \
	  $(CHECK_HELPERS) \
	  echo "Wordcount strict-mode fixture assertions:"; \
	  pandoc \
	    --from=markdown+raw_tex+tex_math_dollars+pipe_tables+grid_tables+fenced_code_attributes \
	    --to=latex --template=$(TEMPLATE) \
	    --citeproc --bibliography=$$wc/refs/refs.bib --csl=$(CSL) \
	    $(addprefix --lua-filter=,$(FILTERS)) \
	    -o /dev/null $$wc/src/*.md 2>$$err; rc=$$?; \
	  if [ $$rc -eq 0 ]; then \
	    echo "  ✗ pandoc exited 0; expected non-zero (strict-limit not enforced)"; \
	    rm -f $$err; exit 1; \
	  fi; \
	  count_eq $$err "[wordcount]"          1 "wordcount tag logged exactly once on stderr"; \
	  count_eq $$err "strict mode enabled"  1 "strict-mode error suffix appeared exactly once"; \
	  rm -f $$err; \
	  if [ $$fail -ne 0 ]; then exit 1; fi; \
	  echo "✓ strict wordcount path exercised"

# ---- CSV strict-mode failure-path check ----
# Asserts that filters/csv.lua's CSV_FAIL_HARD path actually kills the
# build with a clean "[csv] render failed for …" message. Mirrors the
# check-wordcount-strict pattern: a tiny fixture with a missing-file
# csv block; this target expects pandoc to exit non-zero with the
# level-0 stderr message and zero residual "[csv] cannot open" lines
# (those only fire under the default permissive policy).
check-csv-strict:
	@csv=tests/fixtures/csv-strict; \
	  err=$$(mktemp); fail=0; \
	  $(CHECK_HELPERS) \
	  echo "CSV strict-mode fixture assertions:"; \
	  CSV_FAIL_HARD=1 pandoc \
	    --from=markdown+raw_tex+tex_math_dollars+pipe_tables+grid_tables+fenced_code_attributes \
	    --to=latex --template=$(TEMPLATE) \
	    --citeproc --bibliography=$$csv/refs/refs.bib --csl=$(CSL) \
	    $(addprefix --lua-filter=,$(FILTERS)) \
	    -o /dev/null $$csv/src/*.md 2>$$err; rc=$$?; \
	  if [ $$rc -eq 0 ]; then \
	    echo "  ✗ pandoc exited 0; expected non-zero (CSV_FAIL_HARD not enforced)"; \
	    rm -f $$err; exit 1; \
	  fi; \
	  count_eq $$err "[csv] render failed" 1 "csv strict-mode error() fired once with clean message"; \
	  rm -f $$err; \
	  if [ $$fail -ne 0 ]; then exit 1; fi; \
	  echo "✓ strict csv path exercised"

# ---- Anonymous-mode fixture build check ----
# Builds tests/fixtures/anonymous to LaTeX and asserts filters/03-anonymous.lua
# replaces the real `author:` value with "Anonymous". This fixture
# deliberately omits the structured `authors:` list so filters/07-authors.lua
# does not run — without that isolation the 07 filter would overwrite
# 03's effect (in the inverse fixture both fire, and a regression in 03
# would still let "Anonymous" appear in the cover indirectly).
#
# Both directions are checked: presence of "Anonymous" (≥ 1 occurrence)
# AND absence of the real name "Jane Realname" (count == 0). The combined
# pair is a value comparison: 03 ran AND its rewrite stuck through the
# remainder of the filter chain.
check-anonymous:
	@an=tests/fixtures/anonymous; \
	  out=$$(mktemp --suffix=.tex); err=$$(mktemp); fail=0; \
	  $(CHECK_HELPERS) \
	  echo "Anonymous-mode fixture assertions:"; \
	  pandoc \
	    --from=markdown+raw_tex+tex_math_dollars+pipe_tables+grid_tables+fenced_code_attributes \
	    --to=latex --template=$(TEMPLATE) \
	    --citeproc --bibliography=$$an/refs/refs.bib --csl=$(CSL) \
	    $(addprefix --lua-filter=,$(FILTERS)) \
	    -o $$out $$an/src/*.md 2>$$err; rc=$$?; \
	  if [ $$rc -ne 0 ]; then \
	    echo "  ✗ pandoc failed to build the anonymous fixture (rc=$$rc)"; \
	    cat $$err; rm -f $$out $$err; exit 1; \
	  fi; \
	  count_ge $$out "Anonymous"      1 "03-anonymous.lua wrote 'Anonymous' into the rendered output"; \
	  count_eq $$out "Jane Realname"  0 "real author name was rewritten and never reaches LaTeX"; \
	  rm -f $$out $$err; \
	  if [ $$fail -ne 0 ]; then exit 1; fi; \
	  echo "✓ anonymous-mode path exercised"

# ---- URL link checker ----
# HEADs every http(s) URL appearing in the body markdown OR in refs.bib
# `url = {…}` / `doi = {…}` fields. Reports any URL that responds with
# 4xx / 5xx / connection failure. DOIs are resolved via https://doi.org.
#
# Uses `curl --head --silent --location --max-time 15 --fail`. Output
# is a list of "<status> <url>" lines for failures only; a clean run
# prints only the count. Skip with `make check-links SKIP=1`.
#
# Intentionally NOT in `proofread` — link health depends on network
# and would make the gate flaky. Run before submission, separately.
check-links:
	@if [ "$$SKIP" = "1" ]; then echo "✓ check-links skipped"; exit 0; fi
	@urls=$$(mktemp); failures=$$(mktemp); \
	  { grep -hoE 'https?://[^[:space:]<>"`'"'"'(){}]+' $(SRCS) 2>/dev/null; \
	    grep -hoE 'https?://[^[:space:]<>"`'"'"'(){},}]+' $(BIB) 2>/dev/null; \
	    grep -hoE 'doi[[:space:]]*=[[:space:]]*\{[^}]+\}' $(BIB) 2>/dev/null \
	      | sed -E 's|^.*\{||; s|\}.*$$||; s|^|https://doi.org/|'; \
	  } | sed -E 's/[].,;:)]+$$//' | sort -u > $$urls; \
	  total=$$(wc -l < $$urls); \
	  echo "checking $$total unique URL(s)…"; \
	  while IFS= read -r url; do \
	    [ -z "$$url" ] && continue; \
	    if ! status=$$(curl --head --silent --location --max-time 15 \
	                        --user-agent "acedemic-template/check-links" \
	                        --write-out '%{http_code}' --output /dev/null "$$url" 2>/dev/null); then \
	      echo "    CONNECT $$url" >> $$failures; \
	    elif [ "$$status" -ge 400 ]; then \
	      echo "    $$status $$url" >> $$failures; \
	    fi; \
	  done < $$urls; \
	  if [ -s $$failures ]; then \
	    echo "✗ link check failed:"; \
	    cat $$failures; \
	    rm -f $$urls $$failures; \
	    exit 1; \
	  fi; \
	  rm -f $$urls $$failures; \
	  echo "✓ all $$total URL(s) reachable"

# ---- Spell-check ----
# Strips Markdown structure via pandoc -t plain, then runs aspell list
# against an in-repo project dictionary at .aspell.en.pws (extend that
# file with project-specific terms — wordcount, eisvogel, plantuml, …).
# Exits non-zero on any unknown word.
#
# Code spans and fences are filtered out by `pandoc -t plain`. YAML
# front-matter values are NOT checked (filter as_string output drops
# raw text); add metadata-string tokens to the dictionary instead.
#
# To extend the dictionary, use:
#   make spellcheck-add WORDS="foo bar baz"   # recommended; rebuilds counter
# or hand-edit .aspell.en.pws (one word per line, bump the trailing
# integer on the first line by the number of words you added).
#
# Constraints aspell imposes on dictionary entries (we surface them in
# spellcheck-add so authors don't trip over them silently):
#   - no hyphens (`pre-commit` → register `pre` + `commit` separately,
#     or live with the warning if the term is rare)
#   - no digits at word boundaries (`v3`, `Q1` → not accepted)
#   - no Unicode quotes — use straight ASCII apostrophes in source
#     and the dictionary (pandoc's smart quotes are stripped in the
#     spellcheck pipeline via --from=markdown-smart)
spellcheck:
	@command -v aspell >/dev/null || { echo "aspell not found (in dev shell?)"; exit 1; }
	@miss=$$(mktemp); \
	  pandoc --from=markdown-smart -t plain \
	    $(filter-out $(SRC_DIR)/00-metadata.md,$(SRCS)) 2>/dev/null \
	    | aspell --lang=en --personal=$$PWD/.aspell.en.pws list \
	    | sort -u > $$miss; \
	  if [ -s $$miss ]; then \
	    n=$$(wc -l < $$miss); \
	    echo "✗ $$n unrecognised word(s) — add to .aspell.en.pws or fix:"; \
	    sed 's/^/    /' $$miss; \
	    echo ""; \
	    echo "  To accept all of these as valid project terms, run:"; \
	    echo "    make spellcheck-add WORDS=\"$$(tr '\n' ' ' < $$miss | sed 's/ *$$//')\""; \
	    echo "  To fix them in the source instead, edit the offending word in src/*.md."; \
	    rm -f $$miss; exit 1; \
	  fi; \
	  rm -f $$miss; \
	  echo "✓ no unrecognised words (project dictionary: .aspell.en.pws)"

# ---- Add words to the spell-check dictionary ----
# Usage:  make spellcheck-add WORDS="foo bar baz"
#
# Appends each space-separated word to .aspell.en.pws after validating
# it against aspell's personal-dictionary character rules (no hyphens,
# no digits at boundaries, no Unicode quotes). Bumps the trailing
# counter on the first line so aspell's bookkeeping stays consistent.
# Reruns `make spellcheck` to confirm the new dictionary loads cleanly.
.PHONY: spellcheck-add
spellcheck-add:
	@if [ -z "$(WORDS)" ]; then \
	  echo "usage: make spellcheck-add WORDS=\"foo bar baz\""; \
	  exit 1; \
	fi
	@dict=.aspell.en.pws; \
	  if [ ! -f $$dict ]; then \
	    echo "personal_ws-1.1 en 0" > $$dict; \
	  fi; \
	  added=0; rejected=0; \
	  for w in $(WORDS); do \
	    if printf '%s\n' "$$w" | grep -qE '[^A-Za-z'"'"']'; then \
	      echo "  ✗ rejected '$$w' (aspell only accepts letters and ASCII apostrophes)"; \
	      rejected=$$((rejected + 1)); continue; \
	    fi; \
	    if awk 'NR > 1 && $$0 == w' w="$$w" $$dict | grep -q .; then \
	      echo "  · '$$w' already in $$dict — skipped"; continue; \
	    fi; \
	    echo "$$w" >> $$dict; \
	    added=$$((added + 1)); \
	  done; \
	  if [ $$added -gt 0 ]; then \
	    total=$$(( $$(wc -l < $$dict) - 1 )); \
	    awk -v t=$$total 'NR == 1 { sub(/[0-9]+$$/, t); print; next } { print }' $$dict > $$dict.tmp && mv $$dict.tmp $$dict; \
	    echo "  ✓ appended $$added word(s); dictionary now has $$total entries"; \
	  fi; \
	  if [ $$rejected -gt 0 ]; then \
	    echo "  $$rejected word(s) rejected — fix in source or rename the term."; \
	    exit 1; \
	  fi
	@$(MAKE) --no-print-directory spellcheck

# ---- Run CI locally with act ----
# Spins up the GitHub Actions runtime in Docker via `act` and runs the
# `pdf` job from .github/workflows/build.yml against the current tree.
#
# Reads platform pins and cache directories from .actrc (committed
# alongside this Makefile). The first invocation pulls the
# catthehacker/ubuntu:act-latest image (~17 GB) and installs Nix into
# the container — expect ~25-40 minutes end-to-end. Subsequent runs
# reuse the container image and the action cache.
#
# Limitations baked into .actrc:
#   - macOS jobs skipped (act is Linux-only — they run on hosted CI)
#   - magic-nix-cache-action degrades to no-op (no real GH cache backend)
#   - upload-artifact steps land in build/.act-artifacts (gitignored)
#
# Pass extra act flags via ACT_ARGS, e.g.:
#   make ci-local ACT_ARGS="-j pdf --verbose"
#   make ci-local ACT_ARGS="-W .github/workflows/bump-csl.yml"
ACT_ARGS ?=
ci-local:
	@command -v docker >/dev/null || { echo "docker not found"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "docker daemon not reachable"; exit 1; }
	@command -v act >/dev/null || { echo "act not found (in dev shell?)"; exit 1; }
	@mkdir -p $(OUT_DIR)/.act-action-cache $(OUT_DIR)/.act-artifacts
	@echo "==> running act against .github/workflows/ (first run pulls ~17 GB)"
	@act $(ACT_ARGS)

# ---- Proofreading gate ----
# Runs every static check the proofreading skill needs as Phase 1, in
# one shot. Each sub-target prints its own pass/fail; this wrapper
# fails fast on the first non-zero rc so the skill sees a single
# go/no-go signal instead of having to parse seven separate runs.
#
# Order is deliberate: cheap → expensive. typecheck and check-refs run
# first because they catch the failures most likely to mask later
# findings (filter syntax error, missing bib entry rendering as "?").
#
# Intentionally does NOT rebuild the PDF — that's the proofreader's
# call once the gate is green. Run `make` separately if you want the
# render too.
proofread:
	@echo "==> Phase 1: proofreading gate"
	@$(MAKE) --no-print-directory typecheck
	@$(MAKE) --no-print-directory check-refs
	@$(MAKE) --no-print-directory spellcheck
	@$(MAKE) --no-print-directory check-inverse
	@$(MAKE) --no-print-directory check-diagram-failure
	@$(MAKE) --no-print-directory check-wordcount-strict
	@$(MAKE) --no-print-directory check-csv-strict
	@$(MAKE) --no-print-directory check-anonymous
	@echo "✓ proofreading gate clean — safe to proceed with prose review"
	@echo "  (network-dependent: run \`make check-links\` separately before submission)"

# ---- Diagram cache GC ----
# Removes stale entries from $(OUT_DIR)/diagrams: anything whose hash
# isn't referenced by the current document. Works by re-running pandoc
# once with DIAGRAM_MANIFEST set (so each diagram filter records the
# hashes it touches), then pruning everything else.
gc-diagrams: | build-dir
	@manifest=$(OUT_DIR)/diagrams/.manifest; \
	  : > "$$manifest"; \
	  DIAGRAM_MANIFEST="$$manifest" pandoc $(PANDOC_OPTS) -o /dev/null $(SRCS) >/dev/null 2>&1 || { \
	    echo "✗ gc-diagrams: pandoc build failed; refusing to prune"; rm -f "$$manifest"; exit 1; }; \
	  used=$$(sort -u "$$manifest"); \
	  pruned=0; \
	  for f in $(OUT_DIR)/diagrams/*.pdf; do \
	    [ -e "$$f" ] || continue; \
	    h=$$(basename "$$f" .pdf); \
	    if ! printf '%s\n' "$$used" | grep -qx "$$h"; then \
	      rm -f $(OUT_DIR)/diagrams/$$h.*; \
	      pruned=$$((pruned + 1)); \
	    fi; \
	  done; \
	  rm -f "$$manifest"; \
	  echo "✓ pruned $$pruned orphan diagram(s) from $(OUT_DIR)/diagrams"

# ---- Tracked changes ----
# Render the PDF as a diff against another git ref using latexdiff.
# Usage:  make diff REF=v1.0
#         make diff REF=HEAD~5
# Produces build/report-diff.pdf with insertions underlined and
# deletions struck through.
DIFF_REF ?= $(REF)
diff:
	@if [ -z "$(DIFF_REF)" ]; then \
	  echo "Usage: make diff REF=<git-ref>"; exit 1; \
	fi
	@DIFF_SHA=$$(git rev-parse --verify --quiet "$(DIFF_REF)^{commit}") || { \
	  echo "✗ '$(DIFF_REF)' is not a valid git ref"; exit 1; }; \
	  command -v latexdiff >/dev/null || { echo "latexdiff not found (in dev shell?)"; exit 1; }; \
	  mkdir -p $(OUT_DIR)/diff; \
	  echo "→ rendering current revision to .tex"; \
	  pandoc $(PANDOC_OPTS) -t latex -o $(OUT_DIR)/diff/new.tex $(SRCS); \
	  echo "→ checking out $(DIFF_REF) ($$DIFF_SHA) into a temporary worktree"; \
	  rm -rf $(OUT_DIR)/diff/old-tree; \
	  git worktree add --quiet --detach $(OUT_DIR)/diff/old-tree "$$DIFF_SHA"; \
	  trap "git worktree remove --force $(OUT_DIR)/diff/old-tree 2>/dev/null || true" EXIT; \
	  ( cd $(OUT_DIR)/diff/old-tree && \
	    pandoc $(PANDOC_OPTS) -t latex -o ../old.tex $(SRCS) ); \
	  echo "→ running latexdiff"; \
	  latexdiff --type=UNDERLINE --flatten $(OUT_DIR)/diff/old.tex $(OUT_DIR)/diff/new.tex \
	    > $(OUT_DIR)/diff/diff.tex 2> $(OUT_DIR)/diff/latexdiff.log || { \
	    echo "✗ latexdiff failed — last 30 lines of $(OUT_DIR)/diff/latexdiff.log:"; \
	    tail -n 30 $(OUT_DIR)/diff/latexdiff.log | sed 's/^/    /'; \
	    exit 1; }; \
	  echo "→ compiling diff PDF (two passes for refs)"; \
	  ln -sfn .. $(OUT_DIR)/diff/build; \
	  log=$(OUT_DIR)/diff/xelatex.log; \
	  ( cd $(OUT_DIR)/diff && \
	    xelatex -interaction=nonstopmode -halt-on-error diff.tex >$$(basename $$log) 2>&1 && \
	    xelatex -interaction=nonstopmode -halt-on-error diff.tex >>$$(basename $$log) 2>&1 ) || { \
	    echo "✗ xelatex failed — last 30 lines of $$log:"; \
	    tail -n 30 "$$log" | sed 's/^/    /'; \
	    echo "  full log: $$log and $(OUT_DIR)/diff/diff.log"; \
	    exit 1; }; \
	  cp $(OUT_DIR)/diff/diff.pdf $(OUT_DIR)/report-diff.pdf; \
	  echo "✓ $(OUT_DIR)/report-diff.pdf"
