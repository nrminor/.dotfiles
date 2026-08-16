local search_keys = { n = true, N = true, ["*"] = true, ["#"] = true }

vim.on_key(function(key)
	if vim.v.hlsearch == 1 and not search_keys[vim.fn.keytrans(key)] then
		vim.schedule(vim.cmd.nohlsearch)
	end
end, vim.api.nvim_create_namespace("auto_hlsearch"))

local function set_background_from_system()
	local theme_script = vim.fn.expand("~/.config/nushell/theme.nu")
	if vim.fn.executable("nu") == 0 or vim.fn.filereadable(theme_script) == 0 then
		return
	end

	local result = vim.system({ "nu", theme_script, "mode" }, { text = true }):wait()
	if result.code ~= 0 then
		vim.notify("Failed to read theme mode from Nushell", vim.log.levels.WARN, { title = "theme sync" })
		return
	end

	vim.o.background = vim.trim(result.stdout) == "dark" and "dark" or "light"
end

vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained" }, {
	desc = "Sync background with Nushell theme mode",
	callback = set_background_from_system,
})

vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight on yank",
	callback = function()
		vim.highlight.on_yank()
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	desc = "Automatically close quickfix window on selection",
	pattern = "qf",
	callback = function(event)
		vim.keymap.set("n", "<CR>", "<CR><Cmd>cclose<CR>", { buffer = event.buf })
	end,
})
