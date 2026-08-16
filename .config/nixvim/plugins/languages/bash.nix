{ pkgs, ... }:
{
  extraPackages = with pkgs; [
    shellcheck
    shfmt
  ];

  plugins.lsp.servers.bashls = {
    enable = true;
  };
}
