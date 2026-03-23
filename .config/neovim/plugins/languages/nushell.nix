{ pkgs, ... }:
{
  # Nushell's built-in LSP
  plugins.lsp.servers.nushell = {
    enable = true;
  };
}
