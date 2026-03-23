{ pkgs, ... }:
{
  extraPackages = with pkgs; [
    superhtml
  ];

  plugins.lsp.servers.superhtml = {
    enable = true;
    package = null;
  };
}
