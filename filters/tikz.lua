-- filters/tikz.lua
--
-- Pandoc Lua filter: render fenced ```tikz blocks to PDF via the
-- LaTeX `standalone` document class.
--
-- Pipeline per block:
--   1. Hash block contents (so unchanged diagrams are cached).
--   2. Wrap the source in \documentclass{standalone} + \usepackage{tikz},
--      via the shared source_transform hook in _diagram.lua.
--   3. xelatex (or whatever ENGINE the build uses) → PDF with a tight
--      bounding box from the `standalone` class.
--   4. Replace the code block with a Figure containing the image.
--
-- Optional attributes on the fence:
--   ```{.tikz #fig:layers caption="Block layers"}
--   width=80%        -> sets pandoc image width
--   libraries=...    -> comma-separated \usetikzlibrary{...} entries,
--                       e.g. libraries=arrows.meta,positioning,calc
--   preamble=...     -> extra preamble lines (rare; for one-off
--                       commands you don't want to factor out)
--
-- Outputs go into  build/diagrams/<hash>.{tex,pdf,aux,log}.
--
-- Trust model: TikZ source runs `xelatex` with arbitrary input. As
-- with the other diagram backends, the author of the source markdown
-- is the trust principal. Don't run this filter against untrusted
-- third-party markdown.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local D = require("_diagram")

---Wrap a tikz fence body in a \documentclass{standalone} document.
---libraries= and preamble= attributes get folded in here so the wrap
---is one place; cache key includes the libraries pick automatically
---via source_transform.
---@param block CodeBlock
---@return string
local function wrap_standalone(block)
	local libraries = block.attributes["libraries"] or ""
	local preamble = block.attributes["preamble"] or ""

	local lib_lines = {}
	if libraries ~= "" then
		for lib in libraries:gmatch("[^,%s]+") do
			table.insert(lib_lines, "\\usetikzlibrary{" .. lib .. "}")
		end
	end

	return table.concat({
		"\\documentclass[border=2pt]{standalone}",
		"\\usepackage{tikz}",
		table.concat(lib_lines, "\n"),
		preamble,
		"\\begin{document}",
		block.text,
		"\\end{document}",
		"",
	}, "\n")
end

CodeBlock = D.make_filter({
	tag = "tikz",
	classes = { "tikz" },
	src_ext = "tex",
	-- source_transform writes the wrapped standalone document to
	-- ctx.src_path AND hashes it, so any change to libraries / preamble
	-- invalidates the cache.
	source_transform = wrap_standalone,
	render = function(ctx)
		-- Resolve the engine the build uses. Make exports ENGINE in its
		-- env; fall back to xelatex (matches the Makefile default).
		local engine = os.getenv("ENGINE") or "xelatex"
		-- `cd` into the cache dir so xelatex's intermediate files (.aux,
		-- .log) land next to the source — interaction=nonstopmode keeps
		-- it non-interactive even if there's a syntax error.
		local cmd = string.format(
			"(cd %s && %s -interaction=nonstopmode -halt-on-error %s.tex >/dev/null 2>&1)",
			D.shell_quote(ctx.cache_dir),
			engine,
			D.shell_quote(ctx.hash))
		if not D.run(cmd) or not D.file_exists(ctx.pdf_path) then
			io.stderr:write("[tikz] " .. engine .. " failed for diagram " .. ctx.hash .. "\n")
			return nil
		end
		return ctx.pdf_path
	end,
})
