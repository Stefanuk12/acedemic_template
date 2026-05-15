-- luacheck configuration for the Pandoc-filter codebase.
--
-- The filters/*.lua files are Pandoc Lua filters: they read from the
-- global `pandoc` library and may set globals named after AST node types
-- (`Pandoc`, `Meta`, `CodeBlock`, ...) which Pandoc picks up by name.
-- Without this rc, luacheck flags all of those as "undefined / non-
-- standard global" — pure noise that hides real warnings.

std = "max"

-- The pandoc.* library is read globally inside filters.
read_globals = { "pandoc" }

-- Pandoc filter entry points are set as globals. List the AST node types
-- the filters in this repo currently define; extend as new filters are
-- added. See https://pandoc.org/lua-filters.html#typewise-traversal.
globals = {
	"Pandoc",
	"Meta",
	"Block",
	"Blocks",
	"Inline",
	"Inlines",
	"BlockQuote",
	"BulletList",
	"CodeBlock",
	"Cite",
	"Code",
	"DefinitionList",
	"Div",
	"Emph",
	"Figure",
	"Header",
	"HorizontalRule",
	"Image",
	"LineBlock",
	"LineBreak",
	"Link",
	"Math",
	"Note",
	"OrderedList",
	"Para",
	"Plain",
	"Quoted",
	"RawBlock",
	"RawInline",
	"SmallCaps",
	"SoftBreak",
	"Space",
	"Span",
	"Str",
	"Strikeout",
	"Strong",
	"Subscript",
	"Superscript",
	"Table",
	"Underline",
}

-- Skip generated, vendored, and Nix-managed trees. These are reachable
-- from the working tree via symlinks created by direnv / `nix develop`,
-- so without explicit excludes luacheck descends into the entire pinned
-- nixpkgs source.
exclude_files = {
	".direnv/",
	"build/",
	"templates/eisvogel/",
	"types/",
}

-- The wrapping outer parens in filters/00-wordcount.lua (heading_text and
-- with_commas) intentionally discard gsub's second return; treat that
-- value-truncation idiom as ok.
max_line_length = 120
