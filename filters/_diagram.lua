-- filters/_diagram.lua
--
-- Shared scaffolding for the diagram-rendering filters
-- (d2, mermaid, plantuml, graphviz). Provides:
--
--   * file_exists / shell_quote / run  — small shell-wrappers
--   * make_filter(spec)                — the full Pandoc filter:
--                                        cache-by-hash, write source,
--                                        invoke render(), wrap as Figure.
--
-- Each backend file becomes a thin spec table plus a `CodeBlock = ...`
-- assignment. Loaded via the package.path shim documented in the
-- backend filters; the leading underscore keeps this file out of the
-- default $(FILTERS) glob in Makefile.
--
-- The Makefile's `build-dir` target creates the cache directory
-- before any filter is invoked, so render() can assume it exists.
-- Path is taken from $DIAGRAM_CACHE_DIR (exported by the Makefile)
-- with a build/diagrams fallback for ad-hoc pandoc invocations.

local M = {}

-- Env-driven knobs are read lazily so a caller (test harness, REPL,
-- in-process pandoc invocation) can change the cache dir or manifest
-- path between filter runs without re-loading this module.
local function cache_dir()
	return os.getenv("DIAGRAM_CACHE_DIR") or "build/diagrams"
end

-- Optional GC manifest. When DIAGRAM_MANIFEST is set, each hash this
-- filter touches (cache hit or fresh render) is appended to that file.
-- `make gc-diagrams` uses the manifest to prune orphan hash entries
-- from the cache directory after a clean build.
local function manifest_path()
	return os.getenv("DIAGRAM_MANIFEST")
end

local function record_used(hash)
	local mp = manifest_path()
	if not mp then return end
	local mf = io.open(mp, "a")
	if mf then
		mf:write(hash .. "\n")
		mf:close()
	end
end

---@param path string
---@return boolean
function M.file_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

---Single-quote a shell argument, escaping any embedded single quotes.
---@param s string
---@return string
function M.shell_quote(s)
	return "'" .. s:gsub("'", "'\\''") .. "'"
end

---Run a shell command, returning whether it succeeded.
---@param cmd string
---@return boolean
function M.run(cmd)
	-- Pandoc embeds Lua 5.4: os.execute returns (true|nil, "exit"|"signal", code).
	-- Truthy first return is sufficient; the `or code == 0` of older snippets is
	-- defensive noise under 5.4.
	return os.execute(cmd) == true
end

---@class DiagramSpec
---@field tag string                                          short name used in stderr (e.g. "d2")
---@field classes string[]                                    fence classes that trigger this filter
---@field src_ext string                                      extension for the source file written to cache
---@field render fun(ctx: DiagramCtx): string?                returns pdf path on success, nil on failure
---@field hash_extra? fun(block: CodeBlock): string?          optional extra string mixed into the cache key
---@field source_transform? fun(block: CodeBlock): string     optional rewrite of block.text before hashing/writing
                                                              -- (e.g. plantuml wraps with @startuml/@enduml). When
                                                              -- present its return replaces block.text for both
                                                              -- the cache-key input and the on-disk write — so the
                                                              -- backend never needs to re-open ctx.src_path.

---@class DiagramCtx
---@field tag string             diagram tag (== spec.tag)
---@field hash string            12-char content hash
---@field src_path string        path to the written source file
---@field pdf_path string        path the renderer must write to
---@field cache_dir string       cache directory ("build/diagrams")
---@field block CodeBlock        the Pandoc CodeBlock being rendered
---@field hash_extra? string     value returned by spec.hash_extra (if any) — let render() reuse it without recomputing

---Build a visible failure-placeholder block as a red, boxed LaTeX
---notice. Used by the diagram backends and by filters/csv.lua so a
---failed render is obvious in the rendered PDF — silently leaving
---the source CodeBlock in place meant authors shipped documents
---with literal markup where a figure or table should have been.
---
---`fail_hard_env` is the env var name (e.g. "DIAGRAM_FAIL_HARD",
---"CSV_FAIL_HARD") that escalates to a Lua error() instead of a
---visible placeholder. The error is raised with level 0 so the user
---sees only the "[tag] …" message, not the Lua source prefix.
---
---The LaTeX uses \fbox (built-in) + \textcolor (xcolor, already
---loaded by eisvogel) so no extra packages are needed.
---@param heading string            label shown before " FAILED" in the placeholder ("DIAGRAM", "CSV")
---@param hint string               render hint shown after the em-dash (hash, file path, block id)
---@param fail_hard_env string|nil  env var that escalates to a hard error when set to "1"
---@param error_tag string|nil      bracket-prefix in error message; defaults to heading:lower()
---@return Block
function M.make_failure_placeholder(heading, hint, fail_hard_env, error_tag)
	if fail_hard_env and os.getenv(fail_hard_env) == "1" then
		-- Level 0 strips the `_diagram.lua:line:` prefix Lua would
		-- otherwise prepend, mirroring filters/00-wordcount.lua's
		-- strict-mode error() so the user sees only the [tag] message.
		local prefix = error_tag or heading:lower()
		error("[" .. prefix .. "] render failed for " .. hint
			.. " (" .. fail_hard_env .. "=1)", 0)
	end
	local msg = string.format("%s FAILED — %s", heading,
		hint ~= "" and hint or "<unnamed block>")
	local latex = string.format(
		"\\begin{center}\\fbox{\\textcolor{red}{\\textbf{%s}}}\\end{center}",
		msg)
	return pandoc.RawBlock("latex", latex)
end

---Diagram-specific shim around make_failure_placeholder. Keeps the
---existing "DIAGRAM FAILED — <tag> (<hash>)" wording and DIAGRAM_FAIL_HARD
---escalation as a one-liner — render() callers and the broken-diagram
---fixture depend on this exact label / env var.
---@param tag string
---@param hash string
---@return Block
function M.failure_placeholder(tag, hash)
	return M.make_failure_placeholder(
		"DIAGRAM",
		string.format("%s (%s)", tag, hash),
		"DIAGRAM_FAIL_HARD",
		tag)
end

---True iff `block` carries one of the fence classes the spec handles.
---@param spec DiagramSpec
---@param block CodeBlock
---@return boolean
local function matches_classes(spec, block)
	for _, cls in ipairs(spec.classes) do
		if block.classes:includes(cls) then return true end
	end
	return false
end

---Resolve cache-key inputs and on-disk paths for one block.
---When spec.source_transform is set, its return replaces block.text as
---the source written to disk AND the primary hash input; the optional
---spec.hash_extra return is still mixed in (e.g. graphviz's engine pick).
---@param spec DiagramSpec
---@param block CodeBlock
---@return string hash         12-char content hash
---@return string src_path     where to write the source file
---@return string pdf_path     where the renderer must produce a PDF
---@return string source_text  text to write to src_path (== block.text unless source_transform fires)
---@return string|nil hash_extra  whatever spec.hash_extra returned (for render() to reuse)
local function compute_paths(spec, block)
	local source_text = spec.source_transform and spec.source_transform(block) or block.text
	local hash_extra = spec.hash_extra and spec.hash_extra(block) or nil
	local hash_input = hash_extra and (hash_extra .. ":" .. source_text) or source_text
	local hash = pandoc.utils.sha1(hash_input):sub(1, 12)
	local cdir = cache_dir()
	local src_path = cdir .. "/" .. hash .. "." .. spec.src_ext
	local pdf_path = cdir .. "/" .. hash .. ".pdf"
	return hash, src_path, pdf_path, source_text, hash_extra
end

---Write `text` to `src_path`. Logs `[tag] cannot write …` on failure
---so render-failure stderr stays single-format across the pipeline.
---@param tag string
---@param src_path string
---@param text string
---@return boolean ok
local function write_source(tag, src_path, text)
	local f, err = io.open(src_path, "w")
	if not f then
		io.stderr:write("[" .. tag .. "] cannot write " .. src_path .. ": " .. tostring(err) .. "\n")
		return false
	end
	f:write(text)
	f:close()
	return true
end

---Build the CodeBlock filter function for one diagram backend.
---@param spec DiagramSpec
---@return fun(block: CodeBlock): Block?
function M.make_filter(spec)
	---@param block CodeBlock
	---@return Block?  Figure on success, placeholder on failure, nil if no class matched
	return function(block)
		if not matches_classes(spec, block) then return nil end

		local hash, src_path, pdf_path, source_text, hash_extra = compute_paths(spec, block)

		if M.file_exists(pdf_path) then
			record_used(hash)
			return M.wrap_as_figure(block, pdf_path)
		end

		if not write_source(spec.tag, src_path, source_text) then
			return M.failure_placeholder(spec.tag, hash)
		end

		---@type DiagramCtx
		local ctx = {
			tag = spec.tag,
			hash = hash,
			src_path = src_path,
			pdf_path = pdf_path,
			cache_dir = cache_dir(),
			block = block,
			hash_extra = hash_extra,
		}

		local result = spec.render(ctx)
		if not result then
			-- render() already logged the failure.
			return M.failure_placeholder(spec.tag, hash)
		end

		record_used(hash)
		return M.wrap_as_figure(block, result)
	end
end

---Wrap a rendered PDF path in a Pandoc Figure honoring the original
---block's identifier, `caption`, and `width` attributes. Caption is
---parsed as markdown so inline formatting works.
---@param block CodeBlock
---@param pdf_path string
---@return Figure
function M.wrap_as_figure(block, pdf_path)
	local caption_text = block.attributes["caption"] or ""
	local caption_blocks = caption_text ~= ""
		and pandoc.read(caption_text, "markdown").blocks
		or {}

	local img_attr = pandoc.Attr("", {}, {})
	if block.attributes["width"] then
		img_attr.attributes["width"] = block.attributes["width"]
	end

	local img = pandoc.Image({}, pdf_path, caption_text, img_attr)
	local fig_attr = pandoc.Attr(block.identifier or "", {}, {})

	-- Wrap in a proper Figure so pandoc-crossref sees the ID and the
	-- LaTeX writer emits \begin{figure}…\end{figure} with \label{}.
	return pandoc.Figure({ pandoc.Plain({ img }) }, pandoc.Caption(caption_blocks), fig_attr)
end

return M
