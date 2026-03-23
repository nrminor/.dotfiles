{
  colorschemes = {
    catppuccin = {
      enable = true;
      settings = {
        flavour = "macchiato";
        transparent_background = true;
        no_bold = true;
        no_italic = true;
        integrations = {
          blink_cmp = true;
          gitsigns = true;
          indent_blankline = {
            enabled = false;
            scope_color = "sapphire";
            colored_indent_levels = false;
          };
          native_lsp = {
            enabled = true;
          };
          symbols_outline = true;
          telescope = true;
          treesitter = true;
          treesitter_context = true;
        };
      };
    };
  };
}
