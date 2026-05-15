-- filters/00-wordcount.lua
--
-- Count words in the document with configurable inclusion rules,
-- and optionally display the count on the cover page.
--
-- YAML metadata (all under the `wordcount:` map):
--
--   wordcount:
--     show: true               # display on cover (default: false)
--
--     # By default the count covers only body prose. Opt in to widen:
--     include-cover:       false   # title, subtitle, author, abstract
--     include-references:  false   # everything after # References / # Bibliography
--     include-appendix:    false   # everything after \appendix
--     include-citations:   false   # in-text [@key] citations
--     include-quotations:  false   # block quotes (BlockQuote)
--
--     # Skip specific sections by the identifier on their heading:
--     exclude-sections: []         # e.g. [sec:methods, sec:limitations]
--
-- Always-skipped: CodeBlock, RawBlock, raw inline code/LaTeX/HTML.
--
-- The formatted count is exposed as the `word-count` metadata field
-- (so `$word-count$` works in custom template snippets), regardless
-- of `show`.
--
-- The `00-` filename prefix ensures this filter runs before any
-- diagram-rendering filters that transform the AST.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local meta = require("_meta")

---@param text string
---@return integer
local function count_words(text)
	local n = 0
	for _ in text:gmatch("%S+") do n = n + 1 end
	return n
end

---@param n integer
---@return string
local function with_commas(n)
	return (tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

---Lower-case stripped heading text for matching. Outer parens force
---a single-value return (gsub leaks a count past the annotation).
---@param block Block
---@return string
local function heading_text(block)
	return (meta.as_string(block):lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

---@class WordcountOpts
---@field show boolean
---@field include_cover boolean
---@field include_references boolean
---@field include_appendix boolean
---@field include_citations boolean
---@field include_quotations boolean
---@field exclude_sections table<string, boolean>

---@param cfg any
---@return WordcountOpts
local function read_opts(cfg)
	return {
		show               = meta.is_truthy(meta.meta_get(cfg, "show", false)),
		include_cover      = meta.is_truthy(meta.meta_get(cfg, "include-cover", false)),
		include_references = meta.is_truthy(meta.meta_get(cfg, "include-references", false)),
		include_appendix   = meta.is_truthy(meta.meta_get(cfg, "include-appendix", false)),
		include_citations  = meta.is_truthy(meta.meta_get(cfg, "include-citations", false)),
		include_quotations = meta.is_truthy(meta.meta_get(cfg, "include-quotations", false)),
		exclude_sections   = meta.as_set(meta.meta_get(cfg, "exclude-sections", nil)),
	}
end

---Walk the body once, applying section-state rules and inclusion
---options to determine which blocks contribute to the count.
---@param blocks Block[]
---@param opts WordcountOpts
---@return integer
local function count_body(blocks, opts)
	local count = 0
	local in_references = false
	local in_appendix = false
	-- When entering an excluded section at heading level L, set this
	-- to L. Cleared when we hit the next heading at level <= L.
	local excluded_until_level = nil

	for _, b in ipairs(blocks) do
		local include = true

		-- ---- Section state machine ----
		if b.t == "Header" then
			-- Exit any active exclusion first (we may be leaving one).
			if excluded_until_level and b.level <= excluded_until_level then
				excluded_until_level = nil
			end
			-- Detect references section by heading text.
			local h = heading_text(b)
			if h == "references" or h == "bibliography" then
				in_references = true
			end
			-- Enter exclusion if this heading's identifier is listed.
			if b.identifier and opts.exclude_sections[b.identifier] then
				excluded_until_level = b.level
			end
		end

		-- Detect appendix marker (raw \appendix in src/99-appendix.md).
		-- The appendix supersedes the references section: any references
		-- bibliography ends here, and from this point on the appendix
		-- inclusion rule (not the references one) applies. %f[%A] is a
		-- Lua-pattern word boundary that prevents \appendixname,
		-- \appendixsection, etc. from tripping the transition.
		if b.t == "RawBlock" and b.format == "latex" and b.text:match("\\appendix%f[%A]") then
			in_appendix = true
			in_references = false
			include = false  -- the marker block itself contributes nothing
		end

		-- ---- Apply inclusion rules ----
		if excluded_until_level then include = false end
		if in_references and not opts.include_references then include = false end
		if in_appendix and not opts.include_appendix then include = false end
		if b.t == "CodeBlock" or b.t == "RawBlock" then include = false end
		if b.t == "BlockQuote" and not opts.include_quotations then include = false end

		if include then
			local processed = b
			if not opts.include_citations then
				processed = pandoc.walk_block(processed, {
					Cite = function(_) return {} end,
				})
			end
			count = count + count_words(meta.as_string(processed))
		end
	end

	return count
end

---@param doc_meta any
---@return integer
local function count_cover(doc_meta)
	local count = 0
	for _, key in ipairs({ "title", "subtitle", "author", "abstract" }) do
		local v = doc_meta[key]
		if v then
			count = count + count_words(meta.as_string(v))
		end
	end
	return count
end

---Enforce the `wordcount.limit` (warn) and `wordcount.strict` (fail)
---options. Raises a Lua error under strict overflow so pandoc surfaces
---it through its filter-error path; emits a stderr warning otherwise.
---@param cfg any
---@param count integer
---@param formatted string
local function enforce_limit(cfg, count, formatted)
	local limit_meta = meta.meta_get(cfg, "limit", nil)
	if not limit_meta then return end
	local limit = tonumber(meta.as_string(limit_meta))
	if not (limit and count > limit) then return end

	local msg = string.format(
		"[wordcount] %s words exceeds limit of %d (over by %d)",
		formatted, limit, count - limit)
	if meta.is_truthy(meta.meta_get(cfg, "strict", false)) then
		-- Raise rather than os.exit(1): pandoc surfaces the message
		-- through its normal filter-error path, so callers (make,
		-- pre-commit, CI) see a clean failure with context instead of
		-- the bare exit code an os.exit would produce.
		error(msg .. " — strict mode enabled, failing build", 0)
	end
	io.stderr:write("[wordcount] WARNING: " .. msg .. ".\n")
end

---Append the word-count to the cover-page subtitle.
---@param doc_meta any
---@param formatted string
local function show_on_cover(doc_meta, formatted)
	local label = formatted .. " words"
	local existing = doc_meta.subtitle
	if existing then
		local existing_text = meta.as_string(existing)
		doc_meta.subtitle = pandoc.MetaInlines({
			pandoc.Str(existing_text .. " · " .. label),
		})
	else
		doc_meta.subtitle = pandoc.MetaInlines({ pandoc.Str(label) })
	end
end

---@param doc Pandoc
---@return Pandoc
function Pandoc(doc)
	local cfg = doc.meta.wordcount
	local opts = read_opts(cfg)

	local count = count_body(doc.blocks, opts)
	if opts.include_cover then
		count = count + count_cover(doc.meta)
	end

	local formatted = with_commas(count)

	-- Expose for template use (avoids clashing with `wordcount:` config map).
	doc.meta["word-count"] = pandoc.MetaInlines({ pandoc.Str(formatted) })

	enforce_limit(cfg, count, formatted)

	if opts.show then
		show_on_cover(doc.meta, formatted)
	end

	return doc
end
