vim.api.nvim_create_user_command("RotateWindows", function()
	local ignored_filetypes = { "neo-tree", "fidget", "Outline", "toggleterm", "qf", "notify" }
	local windows = {}

	for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buffer = vim.api.nvim_win_get_buf(window)
		if not vim.tbl_contains(ignored_filetypes, vim.bo[buffer].filetype) then
			windows[#windows + 1] = { window = window, buffer = buffer }
		end
	end

	if #windows == 0 then
		return
	elseif #windows == 1 then
		vim.api.nvim_err_writeln("There is no other window to rotate with.")
	elseif #windows == 2 then
		vim.api.nvim_win_set_buf(windows[1].window, windows[2].buffer)
		vim.api.nvim_win_set_buf(windows[2].window, windows[1].buffer)
	else
		vim.api.nvim_err_writeln("You can only swap 2 open windows. Found " .. #windows .. ".")
	end
end, { desc = "Rotate windows in a clockwise direction" })
