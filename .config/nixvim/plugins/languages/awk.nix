{ pkgs, ... }:
{
  extraPackages = with pkgs; [
    gawk
    awk-language-server
  ];

  plugins.lsp.servers.awk_ls = {
    enable = true;
    package = null; # installed via extraPackages
  };
}
