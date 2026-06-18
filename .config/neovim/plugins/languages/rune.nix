{ oyuiPackage, ... }:
{
  extraConfigLua = ''
    vim.filetype.add({
      extension = {
        rn = "rune",
      },
    })

    local oyui_config_paths = {
      [vim.fn.fnamemodify(vim.fn.expand("~/.config/oyui/config.rn"), ":p")] = true,
      [vim.fn.fnamemodify(vim.fn.expand("~/.dotfiles/.config/oyui/config.rn"), ":p")] = true,
    }

    vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
      desc = "Start Oyui LSP only for Oyui config files",
      pattern = "*.rn",
      callback = function(args)
        local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(args.buf), ":p")

        if not oyui_config_paths[path] then
          return
        end

        vim.lsp.start({
          name = "oyui_ls",
          cmd = { "${oyuiPackage}/bin/oyui", "language-server" },
          root_dir = vim.fn.fnamemodify(path, ":h"),
        }, { bufnr = args.buf })
      end,
    })
  '';
}
