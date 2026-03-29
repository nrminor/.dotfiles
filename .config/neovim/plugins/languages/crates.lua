local crates = require("crates")

crates.setup({
  autoload = true,
  autoupdate = true,
  completion = {
    blink = {
      use_custom_kind = true
    }
  },
  lsp = {
    enabled = true
  },

  on_attach = function(bufnr)
    local opts = { buffer = bufnr, silent = true }
    vim.keymap.set("n", "<leader>cp", crates.show_popup, vim.tbl_extend("force", opts, { desc = "Crates: popup" }))
    vim.keymap.set("n", "<leader>cu", crates.update_crate,
      vim.tbl_extend("force", opts, { desc = "Crates: update crate" }))
    vim.keymap.set("n", "<leader>cU", crates.upgrade_crate,
      vim.tbl_extend("force", opts, { desc = "Crates: upgrade crate" }))
  end,
})
