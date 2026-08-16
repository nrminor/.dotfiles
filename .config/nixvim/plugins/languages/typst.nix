{ pkgs, ... }:
{
  extraPackages = with pkgs; [
    typstyle
  ];

  # Tinymist is the Typst language server
  plugins.lsp.servers.tinymist = {
    enable = true;
    package = null;
  };
}
