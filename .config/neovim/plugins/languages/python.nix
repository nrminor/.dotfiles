{ pkgs, ... }:
{
  extraPackages = with pkgs; [
    ruff
  ];

  plugins.lsp.servers = {
    ty = {
      enable = true;
    };

    ruff = {
      enable = true;
      settings = {
        lineLength = 100;
        lint = {
          select = [ "ALL" ];
          ignore = [
            "D"
            "S101"
            "E501"
            "PTH123"
            "TD003"
          ];
        };
      };
    };
  };
}
