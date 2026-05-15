-- filters/csv.lua
--
-- Render fenced ```csv blocks (or external CSV files) as a captioned,
-- cross-referenceable pandoc Table.
--
-- Usage — inline CSV:
--   ```{.csv #tbl:sales caption="Quarterly sales" header=true}
--   Quarter,Revenue,Growth
--   Q1,100,10
--   Q2,120,20
--   ```
--
-- Usage — external file:
--   ```{.csv #tbl:big file=data/big.csv caption="Big table" header=true}
--   ```
--
-- Attributes:
--   header     true | false   (default: true) — first row becomes header
--   file       PATH           — read CSV from disk; ignores fence body
--   delimiter  STRING         — defaults to ","
--
-- Trust model: the author of the source markdown is the trust
-- principal. `file=` reads any path readable by the pandoc process
-- with no realpath confinement, mirroring how authors already control
-- the build via raw_tex / lua filters / --bibliography. Don't run
-- this filter against untrusted third-party markdown.
--
-- Failure escalation: by default a missing file or empty CSV renders
-- a visible "CSV FAILED" placeholder (so authors can't ship documents
-- with quietly-dropped tables). Setting CSV_FAIL_HARD=1 in the env
-- escalates these to a hard error(msg, 0) build failure — the right
-- default for CI. Mirrors filters/_diagram.lua's DIAGRAM_FAIL_HARD
-- and filters/00-wordcount.lua's wordcount.strict.
--
-- The body is parsed by a small in-house CSV reader that handles
-- comma separators, double-quoted fields, and "" escapes. Newlines
-- inside quoted fields are NOT supported — keep cells single-line.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local D = require("_diagram")

---Read one quoted field starting just past the opening `"`.
---Returns the field text and the position immediately past the
---closing quote. Doubled `""` inside the field is decoded to a
---single literal `"`.
---@param line string
---@param pos integer position of the byte AFTER the opening quote
---@return string, integer
local function read_quoted_field(line, pos)
	local n = #line
	local out = {}
	while pos <= n do
		local c = line:sub(pos, pos)
		if c == '"' then
			if line:sub(pos + 1, pos + 1) == '"' then
				table.insert(out, '"')
				pos = pos + 2
			else
				return table.concat(out), pos + 1
			end
		else
			table.insert(out, c)
			pos = pos + 1
		end
	end
	return table.concat(out), pos
end

---@param line string
---@param delim string
---@return string[]
local function split_csv_line(line, delim)
	local fields = {}
	local pos = 1
	local n = #line
	while pos <= n do
		local field
		if line:sub(pos, pos) == '"' then
			field, pos = read_quoted_field(line, pos + 1)
		else
			local start = pos
			while pos <= n and line:sub(pos, pos) ~= delim do
				pos = pos + 1
			end
			field = line:sub(start, pos - 1)
		end
		table.insert(fields, field)
		-- Skip the trailing delimiter (if any). One unified site for both
		-- the quoted and unquoted branches.
		if pos <= n and line:sub(pos, pos) == delim then
			pos = pos + 1
		end
	end
	return fields
end

---@param text string
---@param delim string
---@return string[][]
local function parse_csv(text, delim)
	local rows = {}
	for line in text:gmatch("([^\r\n]+)") do
		if line:match("%S") then
			table.insert(rows, split_csv_line(line, delim))
		end
	end
	return rows
end

---Parse one CSV cell as inline markdown. Each cell is wrapped in
---pandoc.Plain so it doesn't introduce extra paragraph spacing inside
---the table layout. An empty cell yields an empty Plain so column
---counts stay stable across rows.
---@param text string
---@return Block[]
local function cell_blocks(text)
	if text == "" then return { pandoc.Plain({}) } end
	local parsed = pandoc.read(text, "markdown").blocks
	-- Lift Para → Plain (avoids the extra vertical gap pandoc would add
	-- between paragraphs inside a table cell); leave other block types
	-- (BulletList, BlockQuote, CodeBlock, ...) intact.
	local out = {}
	for _, b in ipairs(parsed) do
		if b.t == "Para" then
			table.insert(out, pandoc.Plain(b.content))
		else
			table.insert(out, b)
		end
	end
	return out
end

---Build a pandoc Table directly from CSV rows. Going via SimpleTable +
---from_simple_table keeps the cell-construction code small while still
---producing a real Table block with a writable Attr — so we can set
---`identifier` at construction time instead of mutating after the fact.
---@param rows string[][]
---@param has_header boolean
---@param caption string
---@param identifier string
---@return Block?
local function rows_to_table(rows, has_header, caption, identifier)
	if #rows == 0 then return nil end

	local ncols = #rows[1]
	local aligns, widths = {}, {}
	for _ = 1, ncols do
		table.insert(aligns, pandoc.AlignDefault)
		table.insert(widths, 0)
	end

	local header_row = {}
	local body_start = 1
	if has_header then
		for _, c in ipairs(rows[1]) do
			table.insert(header_row, cell_blocks(c))
		end
		body_start = 2
	end

	local body_rows = {}
	for i = body_start, #rows do
		local row_cells = {}
		for _, c in ipairs(rows[i]) do
			table.insert(row_cells, cell_blocks(c))
		end
		table.insert(body_rows, row_cells)
	end

	-- Guard the markdown round-trip: a whitespace-only caption passes
	-- the ~= "" check but pandoc.read returns an empty block list, so
	-- .blocks[1] would be nil. Pull blocks[1] out and check it exists
	-- before indexing .content.
	local caption_inlines
	if caption ~= "" then
		local parsed = pandoc.read(caption, "markdown").blocks
		caption_inlines = parsed[1] and parsed[1].content or pandoc.Inlines({})
	else
		caption_inlines = pandoc.Inlines({})
	end
	local simple = pandoc.SimpleTable(caption_inlines, aligns, widths, header_row, body_rows)
	local tbl = pandoc.utils.from_simple_table(simple)
	-- Identifier travels through the Attr that pandoc-crossref later
	-- consumes to bind `@tbl:foo` cross-references.
	if identifier ~= "" then
		tbl.attr = pandoc.Attr(identifier, tbl.attr.classes, tbl.attr.attributes)
	end

	return tbl
end

---Build a visible "CSV FAILED" placeholder via the shared helper in
---_diagram.lua so the boxed-red-error visual stays in sync across
---the table/diagram pipelines. CSV_FAIL_HARD=1 escalates to error().
---@param hint string
---@return Block
local function failure_placeholder(hint)
	return D.make_failure_placeholder("CSV", hint, "CSV_FAIL_HARD", "csv")
end

---@param block CodeBlock
---@return Block?
function CodeBlock(block)
	if not block.classes:includes("csv") then return nil end

	local delim = block.attributes["delimiter"] or ","
	local has_header = (block.attributes["header"] or "true"):lower() ~= "false"
	local caption = block.attributes["caption"] or ""
	local identifier = block.identifier or ""

	local text
	local file = block.attributes["file"]
	if file then
		local f, err = io.open(file, "r")
		if not f then
			io.stderr:write("[csv] cannot open " .. file .. ": " .. tostring(err) .. "\n")
			return failure_placeholder(file)
		end
		text = f:read("*a")
		f:close()
	else
		text = block.text
	end

	local rows = parse_csv(text, delim)
	if #rows == 0 then
		io.stderr:write("[csv] no rows parsed from block #" .. identifier .. "\n")
		return failure_placeholder(identifier ~= "" and ("#" .. identifier) or (file or ""))
	end

	return rows_to_table(rows, has_header, caption, identifier)
end
