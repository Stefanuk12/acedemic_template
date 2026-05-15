-- filters/plantuml.lua
--
-- Pandoc Lua filter: render fenced ```plantuml blocks to PDF for LaTeX output.
-- Covers the full UML 2.x set: class, sequence (ISD), activity, state,
-- use case, component, deployment, object, composite structure,
-- communication, package, interaction, timing, profile.
--
-- Pipeline per block (mirrors filters/mermaid.lua):
--   1. Hash block contents (so unchanged diagrams are cached).
--   2. plantuml -tsvg : PlantUML source  ->  SVG
--   3. rsvg-convert   : SVG              ->  PDF (vector, tight bbox)
--   4. Replace the code block with an \includegraphics image.
--
-- Optional attributes on the fence:
--   ```{.plantuml caption="Class diagram of the auth module" #fig:auth}
--   width=80%   -> sets pandoc image width
--
-- The @startuml / @enduml markers are added automatically if missing,
-- so blocks can be written either way.
--
-- Outputs go into  build/diagrams/<hash>.{puml,svg,pdf}.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local D = require("_diagram")

---PlantUML requires `@startuml` / `@enduml`. Wrap silently if absent so
---authors can omit them in markdown if they prefer.
---@param src string
---@return string
local function ensure_uml_markers(src)
	if src:match("^%s*@start") then
		return src
	end
	return "@startuml\n" .. src .. "\n@enduml\n"
end

CodeBlock = D.make_filter({
	tag = "plantuml",
	classes = { "plantuml" },
	src_ext = "puml",
	-- source_transform wraps the block in @startuml/@enduml if absent
	-- so plantuml sees valid markers. _diagram.make_filter writes the
	-- transformed string to ctx.src_path AND hashes it, so by the
	-- time render() runs the file on disk already has the wrapped
	-- form — no second write is needed in this callback.
	source_transform = function(block) return ensure_uml_markers(block.text) end,
	render = function(ctx)
		local svg = ctx.cache_dir .. "/" .. ctx.hash .. ".svg"

		--   cd into the cache dir so plantuml writes the .svg next to the .puml
		--   -tsvg     : SVG output (vector; rsvg-convert handles it well)
		--   -nbthread : let plantuml pick a sensible thread count
		local cmd_puml = string.format(
			"(cd %s && plantuml -tsvg -nbthread auto %s)",
			D.shell_quote(ctx.cache_dir),
			D.shell_quote(ctx.hash .. ".puml"))
		if not D.run(cmd_puml) or not D.file_exists(svg) then
			io.stderr:write("[plantuml] plantuml failed for diagram " .. ctx.hash .. "\n")
			return nil
		end

		local cmd_rsvg = string.format("rsvg-convert -f pdf -o %s %s", D.shell_quote(ctx.pdf_path), D.shell_quote(svg))
		if not D.run(cmd_rsvg) or not D.file_exists(ctx.pdf_path) then
			io.stderr:write("[plantuml] rsvg-convert failed for diagram " .. ctx.hash .. "\n")
			return nil
		end

		return ctx.pdf_path
	end,
})
