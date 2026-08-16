{ pkgs, pkgs-stable, ... }:
{
  autoGroups = {
    lint = {
      clear = true;
    };
  };

  extraPackages = with pkgs; [
    selene
    pkgs-stable.statix
  ];

  plugins.lint = {
    enable = true;

    lintersByFt = {
      nix = [ "statix" ];
    };

    autoCmd = {
      callback.__raw = ''
        function()
          require('lint').try_lint()
        end
      '';
      group = "lint";
      event = [
        "BufEnter"
        "BufWritePost"
        "InsertLeave"
        # "TextChanged"
        # "TextChangedI"
      ];
    };
  };
}
