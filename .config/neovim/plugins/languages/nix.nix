{ lib, pkgs, ... }:
{
  extraPackages = with pkgs; [
    nixfmt
  ];

  plugins = {
    nix.enable = true;
    nix-develop.enable = true;

    lsp.servers = {
      nixd = {
        enable = true;
        settings = {
          nixpkgs = {
            expr = ''import (builtins.getFlake "nixpkgs") { }'';
          };
          formatting = {
            command = [ "${lib.getExe pkgs.nixfmt}" ];
          };
        };
      };
    };
  };
}
