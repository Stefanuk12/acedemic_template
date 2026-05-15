-- filters/05-glossary.lua
--
-- Lightweight acronym expansion. On first use of an acronym defined
-- in YAML, expands "API" to "Application Programming Interface (API)";
-- subsequent uses remain "API". Optionally appends a glossary section
-- listing every acronym used.
--
-- YAML metadata:
--   acronyms:
--     API: Application Programming Interface
--     DDD: Domain-Driven Design
--     MVC: Model-View-Controller
--   glossary:
--     append: true            # append a glossary section at the end
--     title: "Glossary"       # section heading
--     only-used: true         # only list acronyms that appeared in the text
--
-- Matching is exact-string against Str inlines. Plurals ("APIs"),
-- possessives ("API's"), and acronyms inside Code/CodeBlock are
-- not expanded.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local meta = require("_meta")

---@param doc Pandoc
---@return Pandoc
function Pandoc(doc)
	if not doc.meta.acronyms then return doc end

	---@type table<string, string>
	local acronyms = {}
	---@type table<string, boolean>
	local seen = {}

	-- Load definitions
	if type(doc.meta.acronyms) == "table" then
		for k, v in pairs(doc.meta.acronyms --[[@as table]]) do
			acronyms[tostring(k)] = meta.as_string(v)
		end
	end

	-- Walk and expand first-use
	local processed = pandoc.walk_block(pandoc.Div(doc.blocks), {
		Str = function(s)
			-- Strip trailing punctuation for matching, preserve it on the way out.
			local core, tail = s.text:match("^(%S-)(%p*)$")
			if not core or core == "" then return nil end

			local expansion = acronyms[core]
			if not expansion then return nil end

			if seen[core] then return nil end
			seen[core] = true

			return pandoc.Str(expansion .. " (" .. core .. ")" .. (tail or ""))
		end,
	})
	doc.blocks = processed.content

	-- Optionally append a glossary section
	local glossary_cfg = doc.meta.glossary
	if meta.is_truthy(meta.meta_get(glossary_cfg, "append", false)) then
		local title = meta.as_string(meta.meta_get(glossary_cfg, "title", "Glossary"))
		local only_used = meta.is_truthy(meta.meta_get(glossary_cfg, "only-used", true))

		---@type {[1]: string, [2]: string}[]
		local entries = {}
		for k, v in pairs(acronyms) do
			if (not only_used) or seen[k] then
				table.insert(entries, { k, v })
			end
		end
		table.sort(entries, function(a, b) return a[1] < b[1] end)

		if #entries > 0 then
			table.insert(doc.blocks,
				pandoc.Header(1, { pandoc.Str(title) },
					pandoc.Attr("sec:glossary", { "unnumbered" }, {})))
			local list_items = {}
			for _, e in ipairs(entries) do
				table.insert(list_items, {
					pandoc.Plain({
						pandoc.Strong({ pandoc.Str(e[1]) }),
						pandoc.Str(" — "),
						pandoc.Str(e[2]),
					}),
				})
			end
			table.insert(doc.blocks, pandoc.BulletList(list_items))
		end
	end

	return doc
end
