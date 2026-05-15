-- filters/01-cover-style.lua
--
-- Map a `cover-style: <preset>` YAML field to the four titlepage-*
-- metadata values that the Eisvogel template reads. When set, the
-- preset overrides any explicit titlepage-* values in the YAML.
--
-- YAML metadata field:
--   cover-style: navy | burgundy | forest | slate | crimson | plain
--
-- To manage colours by hand instead, omit `cover-style` (or set it
-- to "custom") and provide explicit titlepage-color / titlepage-
-- text-color / titlepage-rule-color / titlepage-rule-height fields.
--
-- The `01-` filename prefix puts this filter after the word counter
-- but ahead of the diagram filters; ordering doesn't actually matter
-- for this filter since it only writes to metadata.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local meta = require("_meta")

---@class CoverPreset
---@field bg string      Background colour (hex, no leading `#`)
---@field text string    Title / subtitle / author text colour
---@field rule string    Colour of the dividing rule beneath the title
---@field rule_h integer Rule height in pt (0 hides it entirely)

---@type table<string, CoverPreset>
local presets = {
	navy     = { bg = "1F4E79", text = "FFFFFF", rule = "FFFFFF", rule_h = 2 },
	burgundy = { bg = "800020", text = "FFFFFF", rule = "FFFFFF", rule_h = 2 },
	forest   = { bg = "2D5016", text = "FFFFFF", rule = "FFFFFF", rule_h = 2 },
	slate    = { bg = "36454F", text = "FFFFFF", rule = "FFFFFF", rule_h = 2 },
	crimson  = { bg = "990033", text = "FFFFFF", rule = "FFFFFF", rule_h = 2 },
	plain    = { bg = "FFFFFF", text = "000000", rule = "000000", rule_h = 0 },
}

---Set a string-valued metadata field.
---@param doc_meta any
---@param key string
---@param value string
local function set_meta_string(doc_meta, key, value)
	doc_meta[key] = pandoc.MetaInlines({ pandoc.Str(value) })
end

---@param doc Pandoc
---@return Pandoc
function Pandoc(doc)
	local style = doc.meta["cover-style"]
	if not style then return doc end

	local name = meta.as_string(style):lower():match("^%s*(.-)%s*$")
	if name == "" or name == "custom" or name == "none" then return doc end

	local p = presets[name]
	if not p then
		local available = {}
		for k in pairs(presets) do table.insert(available, k) end
		table.sort(available)
		io.stderr:write(string.format(
			"[cover-style] unknown preset %q; available: %s. Falling back to explicit titlepage-* fields.\n",
			name, table.concat(available, ", ")))
		return doc
	end

	set_meta_string(doc.meta, "titlepage-color",       p.bg)
	set_meta_string(doc.meta, "titlepage-text-color",  p.text)
	set_meta_string(doc.meta, "titlepage-rule-color",  p.rule)
	set_meta_string(doc.meta, "titlepage-rule-height", tostring(p.rule_h))

	return doc
end
