-- filters/02-draft.lua
--
-- Adds a diagonal "DRAFT" watermark to every page when `draft: true`
-- is set in YAML. Uses LaTeX's draftwatermark package, injected via
-- header-includes so it integrates with Eisvogel without touching
-- the template.
--
-- YAML metadata:
--   draft: true | false   (default: false)
--   draft-text: "DRAFT"   (text to display; default: "DRAFT")

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local meta = require("_meta")

---@param doc Pandoc
---@return Pandoc
function Pandoc(doc)
	if not meta.is_truthy(doc.meta.draft) then return doc end

	local text = "DRAFT"
	if doc.meta["draft-text"] then
		text = meta.as_string(doc.meta["draft-text"])
	end

	local watermark = pandoc.RawBlock("latex", string.format([[
\usepackage{draftwatermark}
\SetWatermarkText{%s}
\SetWatermarkScale{5}
\SetWatermarkColor[gray]{0.9}
]], text))

	meta.append_meta_blocks(doc.meta, "header-includes", { watermark })

	return doc
end
