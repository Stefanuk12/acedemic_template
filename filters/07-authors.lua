-- filters/07-authors.lua
--
-- Flatten a structured `authors:` list into the simple `author:`
-- list-of-strings that Eisvogel's title page expects, while emitting
-- an affiliation block for the same data via `include-before` (so it
-- renders after the title page and before the TOC).
--
-- YAML metadata:
--   authors:
--     - name: "Alice Smith"
--       affiliation: "Department of Computer Science"
--       email: "alice@example.edu"
--       orcid: "0000-0000-0000-0001"
--       corresponding: true
--     - name: "Bob Jones"
--       affiliation: "Department of Mathematics"
--
-- The simple `author:` field continues to work for single-author
-- documents — this filter only fires when `authors:` is present.
--
-- NOTE: `include-before` is a shared accumulator. filters/06-frontmatter.lua
-- also appends to it. Order is locked by the numeric filename prefixes
-- (06 runs before 07); add new producers with that constraint in mind.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local meta = require("_meta")

---@param doc Pandoc
---@return Pandoc
function Pandoc(doc)
	local authors = doc.meta.authors
	if not authors or type(authors) ~= "table" or not authors[1] then
		return doc
	end

	---Each entry is the Inline[] for one author's cover-page label
	---(name + LaTeX superscript for the affiliation index + optional `*`).
	---@type Inline[][]
	local name_runs = {}
	---@type string[]
	local detail_lines = {}

	local has_corresponding = false

	---@cast authors table
	for i, a in ipairs(authors) do
		local name = meta.as_string(a.name or "")
		local aff  = meta.as_string(a.affiliation or "")
		local mark = ""
		if meta.is_truthy(a.corresponding) then
			mark = "*"
			has_corresponding = true
		end

		-- Composite name shown on cover: "Name<sup>i</sup>" plus a star
		-- for the corresponding author. The numeric index + star ride in
		-- a LaTeX \textsuperscript so the cover renders the typographic
		-- form rather than a literal digit alongside the name.
		table.insert(name_runs, {
			pandoc.Str(name),
			pandoc.RawInline("latex", "\\textsuperscript{" .. tostring(i) .. mark .. "}"),
		})

		-- Affiliation footnote line.
		local detail = string.format("%d. %s", i, aff ~= "" and aff or "—")
		if a.email then detail = detail .. " — " .. meta.as_string(a.email) end
		if a.orcid then detail = detail .. " (ORCID: " .. meta.as_string(a.orcid) .. ")" end
		table.insert(detail_lines, detail)
	end

	-- Replace the simple `author` field for Eisvogel's title page.
	---@type Inline[]
	local author_inlines = {}
	for i, run in ipairs(name_runs) do
		if i > 1 then
			table.insert(author_inlines, pandoc.Str(", "))
		end
		for _, inline in ipairs(run) do
			table.insert(author_inlines, inline)
		end
	end
	doc.meta.author = pandoc.MetaInlines(author_inlines)

	-- Render affiliations as a small italicised block on the title page
	-- via include-before (after cover, before TOC). Shared with filters/06-frontmatter.lua.
	local aff_blocks = {
		pandoc.Para({ pandoc.Emph({ pandoc.Str("Affiliations:") }) }),
	}
	for _, line in ipairs(detail_lines) do
		table.insert(aff_blocks, pandoc.Para({ pandoc.Str(line) }))
	end
	-- Footer note for the star marker, only if at least one author had it.
	if has_corresponding then
		table.insert(aff_blocks, pandoc.Para({
			pandoc.Emph({ pandoc.Str("* corresponding author") }),
		}))
	end
	table.insert(aff_blocks, pandoc.RawBlock("latex", "\\clearpage"))

	meta.append_meta_blocks(doc.meta, "include-before", aff_blocks)

	return doc
end
