-- filters/graphviz.lua
--
-- Pandoc Lua filter: render fenced ```dot / ```graphviz blocks to PDF.
-- Uses Graphviz's `dot` directly to produce PDF (no SVG round-trip
-- needed; Graphviz speaks PDF natively via Cairo).
--
-- Pipeline per block:
--   1. Hash block contents (so unchanged diagrams are cached).
--   2. dot -Tpdf : graphviz source -> PDF
--   3. Replace the code block with a Figure containing the image.
--
-- Optional attributes on the fence:
--   ```{.dot #fig:graph caption="Dependency graph" engine=neato}
--
-- The `engine=` attribute selects the layout algorithm
-- (dot|neato|fdp|sfdp|twopi|circo); defaults to dot.
--
-- Outputs go into  build/diagrams/<hash>.{dot,pdf}.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local D = require("_diagram")

local valid_engines = {
	dot = true, neato = true, fdp = true,
	sfdp = true, twopi = true, circo = true,
}

---@param block CodeBlock
---@return string
local function pick_engine(block)
	local engine = block.attributes["engine"] or "dot"
	if not valid_engines[engine] then
		io.stderr:write("[graphviz] invalid engine '" .. engine .. "', using dot\n")
		engine = "dot"
	end
	return engine
end

CodeBlock = D.make_filter({
	tag = "graphviz",
	classes = { "dot", "graphviz" },
	src_ext = "dot",
	-- Mix engine into the cache key so two blocks with identical source
	-- but different engines produce different PDFs.
	hash_extra = function(block) return pick_engine(block) end,
	render = function(ctx)
		-- ctx.hash_extra is the same engine pick_engine returned above —
		-- reuse it to avoid the second log line on an invalid engine.
		local engine = ctx.hash_extra or "dot"
		local cmd = string.format("%s -Tpdf -o %s %s", engine, D.shell_quote(ctx.pdf_path), D.shell_quote(ctx.src_path))
		if not D.run(cmd) or not D.file_exists(ctx.pdf_path) then
			io.stderr:write("[graphviz] " .. engine .. " failed for diagram " .. ctx.hash .. "\n")
			return nil
		end
		return ctx.pdf_path
	end,
})
