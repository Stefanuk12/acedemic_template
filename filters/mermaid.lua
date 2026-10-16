-- filters/mermaid.lua
--
-- Pandoc Lua filter: render fenced ```mermaid blocks to PDF for LaTeX output.
--
-- Pipeline per block:
--   1. Hash block contents (so unchanged diagrams are cached).
--   2. mmdc  : mermaid source  ->  SVG
--   3. rsvg-convert : SVG  ->  PDF (vector, tight bounding box)
--   4. Replace the code block with an \includegraphics image.
--
-- Optional attributes on the fence:
--   ```{.mermaid caption="UML class diagram of the auth module" #fig:auth}
--   width=80%   -> sets pandoc image width
--
-- Outputs go into  build/diagrams/<hash>.{mmd,svg,pdf}.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local D = require("_diagram")

CodeBlock = D.make_filter({
	tag = "mermaid",
	classes = { "mermaid" },
	src_ext = "mmd",
	render = function(ctx)
		local svg = ctx.cache_dir .. "/" .. ctx.hash .. ".svg"

		local cmd_mmdc = string.format(
			"mmdc -i %s -o %s -b transparent --quiet",
			D.shell_quote(ctx.src_path), D.shell_quote(svg))
		if not D.run(cmd_mmdc) or not D.file_exists(svg) then
			io.stderr:write("[mermaid] mmdc failed for diagram " .. ctx.hash .. "\n")
			return nil
		end

		return D.svg_to_pdf(ctx, svg)
	end,
})
