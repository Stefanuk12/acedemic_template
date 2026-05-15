-- filters/_collect-citations.lua
--
-- One-shot helper for `make check-refs`. Walks the AST collecting
-- every Cite key, then emits the sorted unique list to stderr (one
-- per line) and produces no document output. The leading underscore
-- in the filename keeps it out of the default $(FILTERS) glob —
-- check-refs invokes it explicitly.
--
-- Pandoc parses pandoc-crossref's `[@fig:foo]`, `[@tbl:foo]`,
-- `[@eq:foo]`, `[@lst:foo]`, `[@sec:foo]` references as Cite nodes
-- before pandoc-crossref converts them, so we filter those prefixes
-- out — they are cross-references to figures/tables/etc., not
-- bibliography citations.

---@type table<string, boolean>
local CROSSREF_PREFIXES = { fig = true, tbl = true, eq = true, lst = true, sec = true }
---@type table<string, boolean>
local seen = {}

---@param c Cite
function Cite(c)
	for _, citation in ipairs(c.citations) do
		local id = citation.id
		local prefix = id:match("^([a-z]+):")
		if not (prefix and CROSSREF_PREFIXES[prefix]) then
			seen[id] = true
		end
	end
end

---@return Pandoc
function Pandoc(_)
	---@type string[]
	local keys = {}
	for k in pairs(seen) do table.insert(keys, k) end
	table.sort(keys)
	for _, k in ipairs(keys) do
		io.stderr:write(k .. "\n")
	end
	-- Return an empty Pandoc to suppress output.
	return pandoc.Pandoc({}, pandoc.Meta({}))
end
