-- filters/06-frontmatter.lua
--
-- Insert front-matter pages (dedication, acknowledgements, declaration)
-- between the cover and the table of contents. Each page gets its own
-- unnumbered chapter-style heading and starts on a fresh page.
--
-- YAML metadata:
--   dedication: |
--     For my parents.
--   acknowledgements: |
--     Thanks to my supervisor ...
--   declaration: |
--     I declare that this work is my own ...
--
-- Pages are emitted in the conventional thesis order:
-- dedication → acknowledgements → declaration. They live in the
-- `include-before` metadata field, which Eisvogel/pandoc renders
-- between the title page and the TOC.
--
-- NOTE: `include-before` is a shared accumulator. filters/07-authors.lua
-- also appends to it. Order is locked by the numeric filename prefixes
-- (06 runs before 07); add new producers with that constraint in mind.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local meta = require("_meta")

---Convert a YAML frontmatter field to a list of pandoc Block values.
---Handles three input shapes:
---  - MetaBlocks (`dedication: |` + literal block in YAML)
---  - MetaInlines (`dedication: "one line of text"` — bare scalar)
---  - anything else: stringify and wrap in a single Para.
---Without the MetaBlocks / MetaInlines discriminator, a bare-scalar
---value would slip into the document's block list as Inline nodes
---(invalid AST), because both shapes are array-like tables.
---@param value any
---@return Block[]
local function as_blocks(value)
	if value == nil then return {} end
	local pandoc_type = pandoc.utils.type(value)
	if pandoc_type == "Blocks" then
		---@cast value Block[]
		return value
	end
	if pandoc_type == "Inlines" then
		---@cast value Inline[]
		return { pandoc.Para(value) }
	end
	-- Fall back: treat as a single Para of the stringified content.
	return { pandoc.Para({ pandoc.Str(meta.as_string(value)) }) }
end

---@param title string
---@param body Block[]
---@return Block[]
local function frontmatter_section(title, body)
	local blocks = {}
	-- An unnumbered chapter-style heading. The {-} class tells pandoc to
	-- skip section numbering. The .unnumbered class also keeps it out of
	-- the auto-generated TOC if toc-depth excludes unnumbered headings.
	table.insert(blocks, pandoc.Header(1, { pandoc.Str(title) },
		pandoc.Attr("", { "unnumbered" }, {})))
	for _, b in ipairs(body) do
		table.insert(blocks, b)
	end
	-- Force a page break after each front-matter section.
	table.insert(blocks, pandoc.RawBlock("latex", "\\clearpage"))
	return blocks
end

---@param doc Pandoc
---@return Pandoc
function Pandoc(doc)
	local sections = {
		{ key = "dedication",       title = "Dedication" },
		{ key = "acknowledgements", title = "Acknowledgements" },
		{ key = "declaration",      title = "Declaration" },
	}

	---@type Block[]
	local front = {}
	local any = false
	for _, s in ipairs(sections) do
		local raw = doc.meta[s.key]
		if raw then
			any = true
			for _, b in ipairs(frontmatter_section(s.title, as_blocks(raw))) do
				table.insert(front, b)
			end
		end
	end

	if not any then return doc end

	-- Inject as `include-before` so it renders after the title page
	-- but before the TOC / LoF / LoT. Shared with filters/07-authors.lua.
	meta.append_meta_blocks(doc.meta, "include-before", front)

	return doc
end
