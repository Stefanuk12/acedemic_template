-- Consumer-filter fixture for mkReport-extra-filters. Only needs to
-- exist and load: a missing path fails the build before pandoc runs.
function Pandoc(doc)
	return doc
end
