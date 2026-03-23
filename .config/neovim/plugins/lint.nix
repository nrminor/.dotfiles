{ pkgs, ... }:
{
  autoGroups = {
    lint = {
      clear = true;
    };
  };

  extraPackages = with pkgs; [
    selene
    statix
  ];

  plugins.lint = {
    enable = true;

    lintersByFt = {
      lua = [ "selene" ];
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
