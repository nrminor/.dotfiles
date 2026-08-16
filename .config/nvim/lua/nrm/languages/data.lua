vim.cmd.packadd("csvview.nvim")
vim.cmd.packadd("vim-dadbod")
vim.cmd.packadd("vim-dadbod-ui")
vim.cmd.packadd("vim-dadbod-completion")

require("csvview").setup({
	parser = {
		comments = { "#", "//" },
		delimiter = { ft = { csv = ",", tsv = "\t" }, fallbacks = { ",", "\t", ";", "|", ":" } },
	},
	view = { display_mode = "border", sticky_header = { enabled = true } },
	keymaps = {
		textobject_field_inner = { "if", mode = { "o", "x" } },
		textobject_field_outer = { "af", mode = { "o", "x" } },
	},
})

vim.keymap.set("n", "<leader>cv", "<cmd>CsvViewToggle<cr>", { desc = "Toggle CSV view", silent = true })
vim.keymap.set("n", "<leader>ci", "<cmd>CsvViewInfo<cr>", { desc = "CSV view info", silent = true })

vim.api.nvim_create_autocmd("FileType", {
	desc = "Use Dadbod completion in SQL buffers",
	pattern = { "sql", "mysql", "plsql" },
	callback = function()
		vim.bo.omnifunc = "vim_dadbod_completion#omni"
	end,
})

vim.keymap.set("n", "<leader>db", "<cmd>DBUIToggle<cr>", { desc = "Toggle Dadbod UI", silent = true })
vim.keymap.set("n", "<leader>dba", "<cmd>DBUIAddConnection<cr>", { desc = "Dadbod add connection", silent = true })
