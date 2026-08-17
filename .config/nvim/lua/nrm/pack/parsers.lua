local languages = {
  "bash",
  "c",
  "cpp",
  "css",
  "dockerfile",
  "elixir",
  "gleam",
  "go",
  "haskell",
  "html",
  "javascript",
  "json",
  "just",
  "kdl",
  "lua",
  "make",
  "markdown",
  "markdown_inline",
  "nextflow",
  "nix",
  "nu",
  "ocaml",
  "ocaml_interface",
  "python",
  "r",
  "rust",
  "scheme",
  "sql",
  "toml",
  "tsx",
  "typescript",
  "typst",
  "yaml",
  "zig",
}

local function register_custom_parsers()
  require("nvim-treesitter.parsers").nextflow = {
    install_info = {
      url = "https://github.com/nextflow-io/tree-sitter-nextflow",
      revision = "69a72c6cf4e90609b8558fc05d7d17a5f3df7894",
      queries = "queries",
    },
  }
end

return {
  languages = languages,
  register_custom_parsers = register_custom_parsers,
}
