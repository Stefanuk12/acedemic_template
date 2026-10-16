-- filters/_meta.lua
--
-- Shared YAML-metadata coercion and word-counting helpers for the
-- metadata filters (00-wordcount, 02-draft, 03-anonymous, 04-todos,
-- 05-glossary, 06-frontmatter, 07-authors, 08-section-limits). Loaded via the package.path shim
-- documented in those filters; the leading underscore keeps this
-- file out of the default $(FILTERS) glob in Makefile so Pandoc
-- does not try to invoke it as a filter directly.

local M = {}

---@param value any
---@return string
function M.as_string(value)
	return pandoc.utils.stringify(value)
end

---Truthy check that accepts the Lua boolean `true` and the YAML keywords
---`true` / `yes` / `on` (case-insensitive, with surrounding whitespace).
---Rejects everything else, including the literal strings `"false"`,
---`"no"`, `"off"`, and any nil/empty value.
---@param value any
---@return boolean
function M.is_truthy(value)
	if value == true then return true end
	if not value then return false end
	local s = M.as_string(value):lower():match("^%s*(.-)%s*$")
	return s == "true" or s == "yes" or s == "on"
end

---Read a sub-key from a metadata map; returns `default` if absent.
---@param meta any
---@param key string
---@param default any
---@return any
function M.meta_get(meta, key, default)
	if meta == nil then return default end
	if type(meta) == "table" and meta[key] ~= nil then return meta[key] end
	return default
end

---Stringify each entry of a MetaList into plain strings.
---@param meta_list any
---@return string[]
function M.as_list(meta_list)
	local out = {}
	if type(meta_list) == "table" then
		for _, v in ipairs(meta_list) do
			table.insert(out, M.as_string(v))
		end
	end
	return out
end

---Build a hash-set of identifiers from a MetaList.
---@param meta_list any
---@return table<string, boolean>
function M.as_set(meta_list)
	local set = {}
	if type(meta_list) == "table" then
		for _, v in ipairs(meta_list) do
			set[M.as_string(v)] = true
		end
	end
	return set
end

---Count whitespace-separated words in `value`: a string, or any pandoc
---element / list (Block, Blocks, Inlines, MetaInlines, MetaBlocks).
---
---Walks the inline leaves (Str, Code, Math) rather than stringifying
---the whole value: pandoc.utils.stringify joins list items, table cells
---and adjacent blocks with no separator, so "first / second" in a list
---would count as the single word "firstsecond". Raw inlines are not
---counted.
---@param value any
---@return integer
function M.count_words(value)
	local n = 0
	---@param text string
	local function add(text)
		for _ in text:gmatch("%S+") do n = n + 1 end
	end
	if type(value) == "string" then
		add(value)
		return n
	end
	-- Pandoc elements are userdata, lists are tables; both have :walk.
	local kind = type(value)
	if (kind == "table" or kind == "userdata") and value.walk then
		value:walk({
			Str = function(s) add(s.text) end,
			Code = function(c) add(c.text) end,
			Math = function(m) add(m.text) end,
		})
		return n
	end
	add(M.as_string(value))
	return n
end

---Append `blocks_to_add` to a MetaBlocks-typed metadata field, creating
---the field if it does not yet exist. Used for shared accumulators like
---`include-before` (06-frontmatter, 07-authors) and `header-includes`
---(02-draft).
---
---Pandoc 3 dislikes nested MetaList{MetaBlocks{...}}, so we keep the
---field flat: a single MetaBlocks containing all blocks.
---@param doc_meta any
---@param key string
---@param blocks_to_add Block[]
function M.append_meta_blocks(doc_meta, key, blocks_to_add)
	local existing = doc_meta[key]
	if existing and type(existing) == "table" and existing[1] then
		for _, b in ipairs(blocks_to_add) do
			table.insert(existing, b)
		end
	else
		doc_meta[key] = pandoc.MetaBlocks(blocks_to_add)
	end
end

return M
