-- filters/03-anonymous.lua
--
-- Blanks the author for blind review when `anonymous: true` is set.
-- The cover page shows "Anonymous" instead of the real author, and
-- the page footer (which Eisvogel populates from the same field)
-- follows suit. Run in conjunction with --metadata-file=blind.yaml
-- if you want even tighter control over which fields leak.
--
-- YAML metadata:
--   anonymous: true | false   (default: false)

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local meta = require("_meta")

---@param doc Pandoc
---@return Pandoc
function Pandoc(doc)
	if not meta.is_truthy(doc.meta.anonymous) then return doc end
	doc.meta.author = pandoc.MetaInlines({ pandoc.Str("Anonymous") })
	return doc
end
