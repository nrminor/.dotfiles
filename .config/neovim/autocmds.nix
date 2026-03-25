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
