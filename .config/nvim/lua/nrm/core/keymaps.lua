local function map(mode, lhs, rhs, description, options)
	vim.keymap.set(
		mode,
		lhs,
		rhs,
		vim.tbl_extend("force", {
			desc = description,
			silent = true,
		}, options or {})
	)
end

local function copy_buffer_path()
	local path = vim.api.nvim_buf_get_name(0)
	if path == "" then
		vim.notify("Current buffer has no file path", vim.log.levels.WARN)
		return
	end

	path = vim.fs.normalize(path)
	vim.fn.setreg("+", path)
	vim.notify("Copied: " .. path)
end

map("n", "<Space>", "<Nop>")
map("n", "L", "$", "Jump End of [L]ine")
map("n", "H", "^", "Jump Start of [L]ine")
map("n", "U", "<C-r>", "Redo")
map("n", "<C-s>", "<Cmd>write<CR>", "Save Current Buffer")
map("n", "<D-p>", copy_buffer_path, "Copy Buffer Path")
map("n", "<D-c>", copy_buffer_path, "Copy Buffer Path")
map("n", "<Leader>no", "<Cmd>nohlsearch<CR>", "[N]o Highlight")
map("n", "<Leader>w", "<Cmd>write<CR>", "[W]rite Buffer", { silent = false })
map("n", "<Leader>q", "<Cmd>quit<CR>", "[Q]uit Buffer", { silent = false })
map("n", "<Leader>z", "<Cmd>wq<CR>", "[W]rite [Q]uit Buffer", { silent = false })
map("v", "<", "<gv", "Visual Mode Outdent")
map("v", ">", ">gv", "Visual Mode Indent")

map("n", "gn", "<Cmd>bnext<CR>", "[G]o [N]ext Buffer")
map("n", "gb", "<Cmd>bprevious<CR>", "[G]o [B]ack Buffer (Previous)")
map("n", "gp", "<Cmd>bprevious<CR>", "[G]o [P]revious Buffer")

map("n", "<Leader>w-", "<C-w>s", "Split [W]indow Vertical")
map("n", "<Leader>w|", "<C-w>v", "Split [W]indow Horizontal")
map("n", "<Leader>wd", "<C-w>c", "Delete [W]indow")
map("n", "<Leader>wr", "<C-w>c", "Rotate [W]indow")
map("n", "<Leader>=", "<C-w>=", "Resize Windows Equal")

local window_directions = { Left = "h", Down = "j", Up = "k", Right = "l" }

local function navigate(direction)
	return function()
		local kitty_command = "KittyNavigate" .. direction
		local tmux_command = "TmuxNavigate" .. direction
		if vim.fn.exists(":" .. kitty_command) ~= 0 and vim.env.TERM == "xterm-kitty" then
			vim.cmd(kitty_command)
		elseif vim.fn.exists(":" .. tmux_command) ~= 0 then
			vim.cmd(tmux_command)
		else
			vim.cmd.wincmd(window_directions[direction])
		end
	end
end

map("n", "<C-h>", navigate("Left"), "Navigate Window Left")
map("n", "<C-j>", navigate("Down"), "Navigate Window Down")
map("n", "<C-k>", navigate("Up"), "Navigate Window Up")
map("n", "<C-l>", navigate("Right"), "Navigate Window Right")

map("n", "<Leader><Tab><Tab>", "<Cmd>tabnew<CR>", "Open new tab")
map("n", "<Leader><Tab>d", "<Cmd>tabclose<CR>", "Close current tab")
map("n", "<Leader>tl", function()
	if vim.fn.tabpagenr() == vim.fn.tabpagenr("$") then
		vim.cmd.tabfirst()
	else
		vim.cmd.tabnext()
	end
end, "Move to next tab (wraps around)")
map("n", "<Leader>th", function()
	if vim.fn.tabpagenr() == 1 then
		vim.cmd.tablast()
	else
		vim.cmd.tabprevious()
	end
end, "Move to previous tab (wraps around)")

map("t", "<Esc>", [[<C-\><C-n>]], "Enter normal mode")
map("t", "jj", [[<C-\><C-n>]], "Enter normal mode")
map("t", "<C-h>", "<Cmd>wincmd h<CR>", "Move to left window", { silent = false })
map("t", "<C-l>", "<Cmd>wincmd l<CR>", "Move to right window", { silent = false })
map("t", "<C-k>", "<Cmd>wincmd j<CR>", "Move to bottom window", { silent = false })
map("t", "<Space>", "<Space>", "Remove input delay on space in terminal", { silent = false })
