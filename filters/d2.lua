-- filters/d2.lua
--
-- Pandoc Lua filter: render fenced ```d2 blocks to PDF for LaTeX output.
-- D2 (https://d2lang.com) is a modern declarative diagram language.
--
-- Pipeline per block:
--   1. Hash block contents (so unchanged diagrams are cached).
--   2. d2  : d2 source  ->  SVG
--   3. rsvg-convert : SVG  ->  PDF (vector, tight bounding box)
--   4. Replace the code block with a Figure containing the image.
--
-- Optional attributes on the fence:
--   ```{.d2 #fig:foo caption="Architecture overview"}
--   width=80%   -> sets pandoc image width
--
-- Outputs go into  build/diagrams/<hash>.{d2,svg,pdf}.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local D = require("_diagram")

CodeBlock = D.make_filter({
	tag = "d2",
	classes = { "d2" },
	src_ext = "d2",
	render = function(ctx)
		local svg = ctx.cache_dir .. "/" .. ctx.hash .. ".svg"
		local cmd_d2 = string.format("d2 %s %s", D.shell_quote(ctx.src_path), D.shell_quote(svg))
		if not D.run(cmd_d2) or not D.file_exists(svg) then
			io.stderr:write("[d2] d2 failed for diagram " .. ctx.hash .. "\n")
			return nil
		end

		local cmd_rsvg = string.format("rsvg-convert -f pdf -o %s %s", D.shell_quote(ctx.pdf_path), D.shell_quote(svg))
		if not D.run(cmd_rsvg) or not D.file_exists(ctx.pdf_path) then
			io.stderr:write("[d2] rsvg-convert failed for diagram " .. ctx.hash .. "\n")
			return nil
		end

		return ctx.pdf_path
	end,
})
