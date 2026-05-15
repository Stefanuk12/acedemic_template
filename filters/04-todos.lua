-- filters/04-todos.lua
--
-- Render `[text]{.todo}` and `[text]{.fixme}` spans as visible
-- highlighted markers in the output, or strip them silently for
-- a "clean" build.
--
-- Authoring:
--   This passage [needs rewriting]{.todo} in the next pass.
--   The figure [is missing]{.fixme}.
--   [Cite Bass 2021]{.cite-needed}
--
-- YAML metadata:
--   todos:
--     mode: highlight | hide   (default: highlight)
--     types: [todo, fixme, cite-needed]   (classes that match)
--
-- The total number of matched spans is exposed as the `todo-count`
-- metadata field for templates / `make stats` to read back.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local meta = require("_meta")

local default_types = { "todo", "fixme", "cite-needed" }
local default_colors = {
	todo            = "yellow",
	fixme           = "red!30",
	["cite-needed"] = "orange!40",
}

---@param doc Pandoc
---@return Pandoc
function Pandoc(doc)
	local cfg = doc.meta.todos
	local mode = meta.as_string(meta.meta_get(cfg, "mode", "highlight")):lower()
	if mode == "" then mode = "highlight" end

	local types = meta.as_list(meta.meta_get(cfg, "types", nil))
	if #types == 0 then types = default_types end
	---@type table<string, boolean>
	local types_set = {}
	for _, t in ipairs(types) do types_set[t] = true end

	local count = 0

	-- Walk the body, transforming or removing matching spans.
	local processed = pandoc.walk_block(pandoc.Div(doc.blocks), {
		Span = function(s)
			local matched_class = nil
			for _, cls in ipairs(s.classes) do
				if types_set[cls] then
					matched_class = cls
					break
				end
			end
			if not matched_class then return nil end

			count = count + 1

			if mode == "hide" then
				return {} -- delete entirely
			end

			-- highlight mode: wrap in a coloured \colorbox
			local color = default_colors[matched_class] or "yellow"
			local result = { pandoc.RawInline("latex", "\\colorbox{" .. color .. "}{") }
			for _, inl in ipairs(s.content) do
				table.insert(result, inl)
			end
			table.insert(result, pandoc.RawInline("latex", "}"))
			return pandoc.Span(result)
		end,
	})

	-- highlight mode pulls in xcolor (already on Eisvogel's preamble
	-- but harmless if loaded twice). Add nothing here.

	doc.blocks = processed.content
	doc.meta["todo-count"] = pandoc.MetaInlines({ pandoc.Str(tostring(count)) })

	return doc
end
