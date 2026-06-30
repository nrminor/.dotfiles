{ pkgs, ... }:
{
  extraPlugins = [
    pkgs.vimPlugins.csvview-nvim
  ];

  extraConfigLua = builtins.readFile ./csv.lua;

  keymaps = [
    {
      mode = "n";
      key = "<leader>cv";
      action = "<cmd>CsvViewToggle<cr>";
      options.desc = "Toggle CSV view";
    }
    {
      mode = "n";
      key = "<leader>ci";
      action = "<cmd>CsvViewInfo<cr>";
      options.desc = "CSV view info";
    }
  ];
}
