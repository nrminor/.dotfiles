{ pkgs, lib, ... }:
{
  extraPackages = with pkgs; [
    ruff
    basedpyright
  ];

  plugins.lsp.servers = {
    basedpyright = {
      enable = true;
      settings = {
        basedpyright = {
          analysis = {
            typeCheckingMode = "basic";
          };
        };
      };
    };

    ruff = {
      enable = true;
      settings = {
        lineLength = 100;
        lint = {
          select = [ "ALL" ];
          ignore = [ "D" "S101" "E501" "PTH123" "TD003" ];
        };
      };
    };
  };
}
