vim.cmd.packadd("crates.nvim")

local crates = require("crates")

crates.setup({
	on_attach = function(buffer)
		local options = { buffer = buffer, silent = true }
		vim.keymap.set(
			"n",
			"<leader>cp",
			crates.show_popup,
			vim.tbl_extend("force", options, { desc = "Crates: popup" })
		)
		vim.keymap.set(
			"n",
			"<leader>cu",
			crates.update_crate,
			vim.tbl_extend("force", options, { desc = "Crates: update crate" })
		)
		vim.keymap.set(
			"n",
			"<leader>cU",
			crates.upgrade_crate,
			vim.tbl_extend("force", options, { desc = "Crates: upgrade crate" })
		)
	end,
})
