\appendix

# Appendix A

Words inside the appendix only contribute to the wordcount when the
include-appendix toggle is set. The unique token APPENDIXSECTIONTOKEN
is grep-asserted in check-inverse to confirm the appendix body still
reaches the rendered LaTeX through filters/06-frontmatter.lua + 07-authors.lua.
