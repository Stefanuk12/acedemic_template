-- filters/08-section-limits.lua
--
-- Enforce per-section limits written into the headings, the way
-- university forms state them:
--
--   # Background to Project (max 300 words)
--   # Objectives (max 10 objectives, max 150 words)
--   # Sources of information / bibliography (list of references, max 10)
--
-- "max N words" limits the section's word count. Any other "max N"
-- limits its item count: top-level list items plus generated
-- bibliography entries. A section runs until the next heading at the
-- same or a higher level, so subsections count towards their parent.
--
-- Word counting follows filters/00-wordcount.lua's defaults: block
-- quotes (e.g. form guidance kept in the source), code, raw blocks and
-- citations are skipped. Citeproc runs before the Lua filters in the
-- Makefile, so a #refs div in the section is already populated.
--
-- Headings without a "max N" are ignored, so the filter is inert for
-- documents that don't use it.
--
-- YAML metadata (all optional):
--   section-limits:
--     report: true    # print every limited section's counts to stderr
--     strict: false   # fail the build if any section is over a limit

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local meta = require("_meta")

---@param block Block
---@return integer
local function words_in(block)
	if block.t == "BlockQuote" or block.t == "CodeBlock" or block.t == "RawBlock" then
		return 0
	end
	local stripped = pandoc.walk_block(block, { Cite = function(_) return {} end })
	return meta.count_words(stripped)
end

---@param block Block
---@return integer
local function items_in(block)
	if block.t == "BulletList" or block.t == "OrderedList" then
		return #block.content
	end
	if block.t == "Div" and block.identifier == "refs" then
		local n = 0
		for _, entry in ipairs(block.content) do
			if entry.t == "Div" and entry.identifier:match("^ref%-") then n = n + 1 end
		end
		return n
	end
	return 0
end

---@class SectionLimit
---@field unit string   "words", the noun after the number, or "items"
---@field max integer

---Parse every "max N [unit]" in a heading.
---@param title string
---@return SectionLimit[]
local function parse_limits(title)
	---@type SectionLimit[]
	local limits = {}
	for max, unit in title:gmatch("max%s+(%d+)%s*(%a*)") do
		table.insert(limits, {
			unit = unit ~= "" and unit or "items",
			max = tonumber(max) --[[@as integer]],
		})
	end
	return limits
end

---@class LimitedSection
---@field title string
---@field level integer
---@field limits SectionLimit[]
---@field words integer
---@field items integer

---@param blocks Block[]
---@return LimitedSection[]
local function measure(blocks)
	---@type LimitedSection[]
	local sections = {}
	---@type LimitedSection?
	local current = nil

	for _, b in ipairs(blocks) do
		if b.t == "Header" then
			if current and b.level <= current.level then
				current = nil
			end
			local title = meta.as_string(b)
			local limits = parse_limits(title)
			if #limits > 0 then
				current = {
					-- Drop the trailing "(max …)" so reports read cleanly.
					title = (title:gsub("%s*%b()%s*$", "")),
					level = b.level,
					limits = limits,
					words = 0,
					items = 0,
				}
				table.insert(sections, current)
			end
		elseif current then
			current.words = current.words + words_in(b)
			current.items = current.items + items_in(b)
		end
	end

	return sections
end

---@param doc Pandoc
---@return Pandoc
function Pandoc(doc)
	local cfg = doc.meta["section-limits"]
	local report = meta.is_truthy(meta.meta_get(cfg, "report", false))
	local strict = meta.is_truthy(meta.meta_get(cfg, "strict", false))

	---@type string[]
	local over = {}
	for _, s in ipairs(measure(doc.blocks)) do
		---@type string[]
		local parts = {}
		for _, l in ipairs(s.limits) do
			local n = l.unit == "words" and s.words or s.items
			local part = string.format("%d / %d %s", n, l.max, l.unit)
			if n > l.max then
				part = part .. string.format(" (over by %d)", n - l.max)
				table.insert(over, s.title .. ": " .. part)
			end
			table.insert(parts, part)
		end
		if report then
			io.stderr:write("[section-limits] " .. s.title .. ": " .. table.concat(parts, ", ") .. "\n")
		end
	end

	if #over == 0 then return doc end

	local msg = "[section-limits] over limit:\n  " .. table.concat(over, "\n  ")
	if strict then
		-- Level 0 strips the Lua position prefix, matching the other
		-- strict-mode errors (00-wordcount, csv, diagrams).
		error(msg .. "\nstrict mode enabled, failing build", 0)
	end
	io.stderr:write("[section-limits] WARNING: " .. #over .. " limit(s) exceeded\n")

	return doc
end
