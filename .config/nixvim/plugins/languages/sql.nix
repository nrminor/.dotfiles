{ pkgs, ... }:
{
  extraPackages = with pkgs; [
    sqls
  ];

  # SQL LSP
  plugins.lsp.servers.sqls = {
    enable = true;
    package = null;
  };

  # Dadbod — interactive database client from inside neovim
  extraPlugins = with pkgs.vimPlugins; [
    vim-dadbod
    vim-dadbod-ui
    vim-dadbod-completion
  ];

  extraConfigLua = ''
    -- Dadbod completion integration with blink/nvim-cmp
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "sql", "mysql", "plsql" },
      callback = function()
        -- vim-dadbod-completion sets up omni completion
        vim.bo.omnifunc = "vim_dadbod_completion#omni"
      end,
    })
  '';

  keymaps = [
    {
      mode = "n";
      key = "<leader>db";
      action = "<cmd>DBUIToggle<cr>";
      options.desc = "Toggle Dadbod UI";
    }
    {
      mode = "n";
      key = "<leader>dba";
      action = "<cmd>DBUIAddConnection<cr>";
      options.desc = "Dadbod add connection";
    }
  ];
}
