{
  plugins.gitsigns = {
    enable = true;
    settings = {
      on_attach = {
        __raw =
          # lua
          ''
            function(bufnr) 
              local gitsigns = require("gitsigns")

              local function map(mode, l, r, opts)
                opts = opts or {}
                opts.buffer = bufnr
                vim.keymap.set(mode, l, r, opts)
              end

              -- Navigation
              map("n", "]c", function()
                if vim.wo.diff then
                  vim.cmd.normal({"]c", bang = true})
                else
                  gitsigns.nav_hunk("next")
                end
              end)

              map("n", "[c", function()
                if vim.wo.diff then
                  vim.cmd.normal({"[c", bang = true})
                else
                  gitsigns.nav_hunk("prev")
                end
              end)

              -- Actions
              map("n", "<leader>hs", gitsigns.stage_hunk, { desc = "stage" })
              map("n", "<leader>hr", gitsigns.reset_hunk, { desc = "reset" })

              map("v", "<leader>hs", function()
                gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
              end, { desc = "stage selection" })

              map("v", "<leader>hr", function()
                gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
              end, { desc = "reset selection" })

              map("n", "<leader>hS", gitsigns.stage_buffer, { desc = "stage buffer" })
              map("n", "<leader>hR", gitsigns.reset_buffer, { desc = "reset buffer" })
              map("n", "<leader>hp", gitsigns.preview_hunk, { desc = "preview" })
              map("n", "<leader>hi", gitsigns.preview_hunk_inline, { desc = "preview inline" })

              map("n", "<leader>hb", function()
                gitsigns.blame_line({ full = true })
              end, { desc = "blame line" })

              map("n", "<leader>hd", gitsigns.diffthis, { desc = "diff this" })

              map("n", "<leader>hD", function()
                gitsigns.diffthis("~")
              end, { desc = "diff ~" })

              map("n", "<leader>hQ", function() gitsigns.setqflist("all") end, { desc = "qflist all" })
              map("n", "<leader>hq", gitsigns.setqflist, { desc = "qflist" })

              -- Toggles
              map("n", "<leader>tb", gitsigns.toggle_current_line_blame, { desc = "Toggle git blame (line)" })
              map("n", "<leader>td", gitsigns.toggle_deleted, { desc = "Toggle git deleted lines" })
              map("n", "<leader>tw", gitsigns.toggle_word_diff, { desc = "Toggle git word diff" })

              -- Text object
              map({"o", "x"}, "ih", gitsigns.select_hunk)
            end
          '';
      };
    };
  };
}
