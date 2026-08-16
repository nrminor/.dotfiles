{ fffPlugin, ... }:
{
  extraPlugins = [ fffPlugin ];

  extraConfigLua = ''
    require("fff").setup({
      lazy_sync = true,
      layout = {
        height = 0.8,
        width = 0.8,
        prompt_position = "bottom",
        preview_position = "right",
        preview_size = 0.5,
      },
    })
  '';

  keymaps = [
    {
      mode = "n";
      key = "<leader>ff";
      action = ''<cmd>lua require("fff").find_files()<cr>'';
      options = {
        desc = "Find files (fff)";
      };
    }
    {
      mode = "n";
      key = "<leader><space>";
      action = ''<cmd>lua require("fff").find_files()<cr>'';
      options = {
        desc = "Find files (fff)";
      };
    }
    {
      mode = "n";
      key = "<leader>fw";
      action = ''<cmd>lua require("fff").live_grep()<cr>'';
      options = {
        desc = "Live grep (fff)";
      };
    }
    {
      mode = "n";
      key = "<leader>/";
      action = ''<cmd>lua require("fff").live_grep()<cr>'';
      options = {
        desc = "Live grep (fff)";
      };
    }
    {
      mode = "n";
      key = "<leader>fc";
      action = ''<cmd>lua require("fff").live_grep({ query = vim.fn.expand("<cword>") })<cr>'';
      options = {
        desc = "Search current word (fff)";
      };
    }
  ];
}
