{ pkgs, ... }:
{
  extraPackages = with pkgs; [
    air-formatter
  ];

  # Air is an R language server and formatter
  # It's not in nixvim's built-in LSP list, so we configure it manually
  extraConfigLua = ''
    vim.lsp.config["air"] = {
      cmd = { "${pkgs.air-formatter}/bin/air", "language-server" },
      filetypes = { "r", "rmd" },
      root_markers = { ".Rproj", "DESCRIPTION", ".git" },
    }
    vim.lsp.enable("air")
  '';
}
