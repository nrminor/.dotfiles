local rustowl = require("rustowl")

rustowl.setup({
  auto_attach = true,
  auto_enable = false, -- manual toggle; less noisy
  idle_time = 500,
  highlight_style = "undercurl",
  client = {
    on_attach = function(_, bufnr)
      local opts = { buffer = bufnr, silent = true }
      vim.keymap.set("n", "<leader>rot", "<cmd>Rustowl toggle<cr>",
        vim.tbl_extend("force", opts, { desc = "RustOwl: toggle" }))
      vim.keymap.set("n", "<leader>roe", "<cmd>Rustowl enable<cr>",
        vim.tbl_extend("force", opts, { desc = "RustOwl: enable" }))
      vim.keymap.set("n", "<leader>rod", "<cmd>Rustowl disable<cr>",
        vim.tbl_extend("force", opts, { desc = "RustOwl: disable" }))
      vim.keymap.set("n", "<leader>ror", "<cmd>Rustowl restart_client<cr>",
        vim.tbl_extend("force", opts, { desc = "RustOwl: restart client" }))
    end,
  },
})
