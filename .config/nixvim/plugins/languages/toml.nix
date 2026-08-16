{ pkgs, ... }:
{
  extraPackages = with pkgs; [
    taplo
  ];

  # Taplo serves as both LSP and formatter for TOML
  plugins.lsp.servers.taplo = {
    enable = true;
  };
}
