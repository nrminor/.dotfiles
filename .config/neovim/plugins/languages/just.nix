{ pkgs, ... }:
{
  extraPackages = with pkgs; [
    just-lsp
  ];

  extraConfigLua = ''
    vim.lsp.config["just-lsp"] = {
      cmd = { "${pkgs.just-lsp}/bin/just-lsp" },
      filetypes = { "just" },
      root_markers = { "justfile", "Justfile", ".git" },
    }
    vim.lsp.enable("just-lsp")
  '';
}
