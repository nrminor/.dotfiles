{
  # Auto-clear search highlight when pressing any key that isn't search navigation
  extraConfigLua = ''
    local search_keys = { n = true, N = true, ["*"] = true, ["#"] = true }
    vim.on_key(function(key)
      if vim.v.hlsearch == 1 then
        local decoded = vim.fn.keytrans(key)
        if not search_keys[decoded] then
          vim.schedule(function()
            vim.cmd.nohlsearch()
          end)
        end
      end
    end, vim.api.nvim_create_namespace("auto_hlsearch"))

    local function set_background_from_system()
      local theme_script = vim.fn.expand("~/.config/nushell/theme.nu")
      local result = vim.system({ "nu", theme_script, "mode" }, { text = true }):wait()

      if result.code ~= 0 then
        vim.notify(
          "Failed to read theme mode from Nushell",
          vim.log.levels.WARN,
          { title = "theme sync" }
        )
        return
      end

      local mode = vim.trim(result.stdout)
      vim.o.background = (mode == "dark") and "dark" or "light"
    end

    vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained" }, {
      desc = "Sync background with Nushell theme mode",
      callback = set_background_from_system,
    })
  '';

  autoCmd = [
    # Miscellaneous
    {
      desc = "Highlight on yank";
      event = [ "TextYankPost" ];
      callback = {
        __raw =
          # lua
          ''
            function()
              vim.highlight.on_yank()
            end
          '';
      };
    }
    {
      desc = "Automatically close quickfix window on selection";
      event = [ "FileType" ];
      pattern = [ "qf" ];
      command = "nnoremap <buffer> <CR> <CR>:cclose<CR>";
    }
    {
      desc = "Open fff when starting on a directory";
      event = [ "VimEnter" ];
      callback = {
        __raw =
          # lua
          ''
            function()
              if vim.fn.argc() ~= 1 then
                return
              end

              local arg = vim.fn.argv(0)
              if vim.fn.isdirectory(arg) == 0 then
                return
              end

              if vim.bo.filetype == "netrw" then
                vim.cmd("enew")
              end

              vim.cmd.cd(vim.fn.fnamemodify(arg, ":p"))
              vim.schedule(function()
                require("fff").find_files()
              end)
            end
          '';
      };
    }
  ];
}
